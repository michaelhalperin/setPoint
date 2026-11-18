import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import {
  DEFAULT_ALERT_RULES,
  SWITCHES,
  VERSION_RE,
  compareVersions,
  getSwitches,
  isSwitchKey,
  readAlertRules,
  readAudit,
  readErrors,
  readMaintenance,
  readTestAccounts,
  readVersionGate,
  setSwitch,
  setTestAccount,
  switchOn,
  writeConfig,
} from '../admin2/store.js';
import { buildDigest, storeDigest } from '../admin/digest.js';
import { AI_DAILY_BUDGET_USD, estimateUsd } from '../admin/ops.js';
import { OnboardingIncompleteError, buildHome } from '../dashboard/index.js';
import { getPrisma } from '../db/client.js';
import { runScoreConfidenceJob } from '../jobs/scoreConfidence.js';
import { runSettleDayJob } from '../jobs/settleDay.js';
import { runWeighInReminderJob } from '../jobs/weighInReminder.js';
import { createManagerVoice } from '../managerVoice/factory.js';
import { getPhotoStore } from '../photos/store.js';
import { retryPhotoDeletions } from '../photos/cleanup.js';
import { createPushSender } from '../push/factory.js';
import { loadStapleFoods, prescribe } from '../solver/index.js';
import { requireAdmin } from './admin.js';

const DAY_MS = 86_400_000;
const id = z.object({ id: z.string().min(1) });

const runBody = z.object({
  /** One person only. Needed for simulation. */
  userId: z.string().min(1).optional(),
  /** Pretend it is this moment. Test accounts only. */
  at: z.string().datetime().optional(),
  /** Required to touch real people or everyone. */
  confirm: z.boolean().optional(),
});

const broadcastBody = z.object({
  segment: z.enum(['all', 'quiet', 'user']),
  userId: z.string().min(1).optional(),
  title: z.string().trim().min(1).max(60).default('SetPoint'),
  message: z.string().trim().min(1).max(240),
  /** Count who would get it; send nothing. */
  dryRun: z.boolean().default(true),
});

const catalogPatch = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  servingG: z.number().positive().max(5000).nullable().optional(),
  kcal100g: z.number().min(0).max(1000).optional(),
  proteinG100g: z.number().min(0).max(100).optional(),
  carbsG100g: z.number().min(0).max(100).optional(),
  fatG100g: z.number().min(0).max(100).optional(),
});

/** The control room: switches, test runs, broadcasts, subscriptions, health, catalog, view-as. */
export async function adminControlRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAdmin(app));
  const prisma = getPrisma();

  // ── Control ───────────────────────────────────────────────────────────────
  app.get('/control', async () => {
    const [switches, version, maintenance, rules, testAccounts] = await Promise.all([
      getSwitches(prisma),
      readVersionGate(prisma),
      readMaintenance(prisma),
      readAlertRules(prisma),
      readTestAccounts(prisma),
    ]);
    return {
      switches: Object.entries(SWITCHES).map(([key, d]) => ({
        key,
        label: d.label,
        hint: d.hint,
        on: switches[key as keyof typeof SWITCHES],
      })),
      version,
      maintenance,
      rules,
      testAccounts,
    };
  });

  app.put('/control/switch/:key', async (req) => {
    const { key } = z.object({ key: z.string() }).parse(req.params);
    if (!isSwitchKey(key)) throw app.httpErrors.notFound('no such switch');
    const { on } = z.object({ on: z.boolean() }).parse(req.body);
    return { switches: await setSwitch(prisma, key, on) };
  });

  app.put('/control/version', async (req) => {
    const body = z
      .object({
        min: z.string().regex(VERSION_RE).nullable(),
        latest: z.string().regex(VERSION_RE).nullable(),
      })
      .parse(req.body);
    if (body.min && body.latest && compareVersions(body.min, body.latest) > 0) {
      throw app.httpErrors.badRequest('minimum can’t be above latest');
    }
    await writeConfig(prisma, 'admin:version', body);
    return body;
  });

  app.put('/control/maintenance', async (req) => {
    const body = z
      .object({ active: z.boolean(), en: z.string().max(240).default(''), he: z.string().max(240).default('') })
      .parse(req.body);
    if (body.active && !body.en.trim()) throw app.httpErrors.badRequest('write the English message first');
    const value = { ...body, updatedAt: new Date().toISOString() };
    await writeConfig(prisma, 'admin:maintenance', value);
    return value;
  });

  app.put('/control/alert-rules', async (req) => {
    const body = z
      .object({
        cronMissed: z.object({ on: z.boolean() }),
        pushFailure: z.object({ on: z.boolean(), pct: z.number().min(1).max(100) }),
        aiSpend: z.object({ on: z.boolean(), usd: z.number().min(0.5).max(1000) }),
        serverErrors: z.object({ on: z.boolean(), count: z.number().int().min(1).max(500) }),
        safetyTrip: z.object({ on: z.boolean() }),
      })
      .parse(req.body);
    await writeConfig(prisma, 'admin:alert-rules', body);
    return body;
  });

  app.post('/test-accounts/:id', async (req) => {
    const { id: userId } = id.parse(req.params);
    const { on } = z.object({ on: z.boolean() }).parse(req.body);
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { id: true } });
    if (!user) throw app.httpErrors.notFound('no such person');
    return { testAccounts: await setTestAccount(prisma, userId, on) };
  });

  // ── Test lab: run a job now, or as of another moment for a test account ──
  app.post('/run/:job', async (req) => {
    const { job } = z.object({ job: z.enum(['score', 'settle', 'weigh-in', 'digest', 'cleanup-photos']) }).parse(req.params);
    const body = runBody.parse(req.body ?? {});

    if (body.at && !body.userId) throw app.httpErrors.badRequest('simulating a time needs one test person');
    if (body.userId) {
      const tests = await readTestAccounts(prisma);
      const isTest = tests.includes(body.userId);
      if (body.at && !isTest) throw app.httpErrors.forbidden('only test accounts can be moved in time');
      if (!isTest && !body.confirm) throw app.httpErrors.badRequest('this is a real person: confirm first');
    } else if (!body.confirm) {
      throw app.httpErrors.badRequest('this runs for everyone: confirm first');
    }

    const now = body.at ? new Date(body.at) : undefined;
    const userIds = body.userId ? [body.userId] : undefined;
    const started = Date.now();
    const result = await (async (): Promise<unknown> => {
      switch (job) {
        case 'score':
          return runScoreConfidenceJob({ prisma, push: createPushSender(), voice: createManagerVoice(), now, userIds });
        case 'settle':
          return runSettleDayJob({ prisma, voice: createManagerVoice(), now, userIds });
        case 'weigh-in':
          return runWeighInReminderJob({ prisma, push: createPushSender(), now, userIds });
        case 'digest': {
          const digest = await buildDigest(prisma, 'daily', new Date());
          await storeDigest(prisma, digest);
          return { stored: 'daily' };
        }
        case 'cleanup-photos': {
          const photos = getPhotoStore();
          return photos ? retryPhotoDeletions(prisma, photos) : { note: 'photo store unconfigured' };
        }
      }
    })();
    return { job, ms: Date.now() - started, simulatedAt: body.at ?? null, result };
  });

  // ── Broadcast push ────────────────────────────────────────────────────────
  app.post('/broadcast', async (req) => {
    const body = broadcastBody.parse(req.body);
    if (body.segment === 'user' && !body.userId) throw app.httpErrors.badRequest('pick a person');
    const now = Date.now();
    const quietSince = new Date(now - 3 * DAY_MS);

    const users = await prisma.user.findMany({
      where: {
        ...(body.segment === 'user' ? { id: body.userId } : {}),
        ...(body.segment === 'quiet'
          ? { onboarding: { is: { completedAt: { not: null } } }, meals: { none: { loggedAt: { gt: quietSince } } } }
          : {}),
      },
      select: { id: true, pushTokens: { where: { kind: 'alert' }, select: { token: true } } },
      take: 2000,
    });
    const reachable = users.filter((u) => u.pushTokens.length > 0);
    const preview = { people: users.length, reachable: reachable.length, noToken: users.length - reachable.length };
    if (body.dryRun) return { dryRun: true, ...preview };

    if (!(await switchOn(prisma, 'pushes'))) throw app.httpErrors.conflict('pushes are switched off');
    if (reachable.length > 500) throw app.httpErrors.badRequest('too many people for one send (max 500)');

    const sender = createPushSender();
    let sent = 0;
    let failed = 0;
    for (const u of reachable) {
      const r = await sender.send(
        u.pushTokens.map((t) => t.token),
        { userId: u.id, checkInId: 'broadcast-admin', tier: 1, title: body.title, body: body.message, plain: true },
      );
      sent += r.sent;
      failed += r.failed;
      if (r.invalidTokens.length > 0) await prisma.pushToken.deleteMany({ where: { token: { in: r.invalidTokens } } });
    }
    return { dryRun: false, ...preview, sent, failed };
  });

  // ── Solver dry-run: nothing is saved ──────────────────────────────────────
  app.post('/solver', async (req) => {
    const body = z
      .object({
        targetKcal: z.number().int().min(100).max(2500),
        proteinG: z.number().min(0).max(200).nullable().default(null),
        excludedTokens: z.array(z.string().min(1).max(40)).max(20).default([]),
      })
      .parse(req.body);
    const { solverFoods } = await loadStapleFoods(prisma);
    const result = prescribe(solverFoods, {
      targetKcal: body.targetKcal,
      targetProteinG: body.proteinG,
      excludedTokens: body.excludedTokens,
    });
    return { result };
  });

  // ── Subscriptions ─────────────────────────────────────────────────────────
  app.get('/subscriptions', async () => {
    const now = new Date();
    const rows = await prisma.user.findMany({
      where: { subscriptionStatus: { not: null } },
      select: {
        id: true,
        email: true,
        displayName: true,
        subscriptionStatus: true,
        subscriptionExpiresAt: true,
        subscriptionProductId: true,
      },
      orderBy: { subscriptionExpiresAt: 'asc' },
      take: 500,
    });
    const people = rows.map((r) => ({ ...r, granted: r.subscriptionProductId === 'admin-grant', live: !!r.subscriptionExpiresAt && r.subscriptionExpiresAt > now && r.subscriptionStatus !== 'REVOKED' }));
    return {
      people,
      counts: {
        paying: people.filter((p) => p.live && !p.granted && p.subscriptionStatus === 'ACTIVE').length,
        trial: people.filter((p) => p.live && p.subscriptionStatus === 'TRIALING').length,
        granted: people.filter((p) => p.granted && p.live).length,
      },
    };
  });

  app.post('/users/:id/subscription', async (req) => {
    const { id: userId } = id.parse(req.params);
    const body = z
      .discriminatedUnion('action', [
        z.object({ action: z.literal('grant'), days: z.number().int().min(1).max(366) }),
        z.object({ action: z.literal('revoke') }),
      ])
      .parse(req.body);
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { subscriptionExpiresAt: true, subscriptionProductId: true } });
    if (!user) throw app.httpErrors.notFound('no such person');
    if (body.action === 'revoke') {
      await prisma.user.update({ where: { id: userId }, data: { subscriptionStatus: 'REVOKED' } });
      return { ok: true };
    }
    // Extends from the later of now and the current expiry, so a grant never shortens a paid plan.
    const from = Math.max(Date.now(), user.subscriptionExpiresAt?.getTime() ?? 0);
    const expires = new Date(from + body.days * DAY_MS);
    await prisma.user.update({
      where: { id: userId },
      data: {
        subscriptionStatus: 'ACTIVE',
        subscriptionExpiresAt: expires,
        subscriptionProductId: user.subscriptionProductId ?? 'admin-grant',
      },
    });
    return { ok: true, expiresAt: expires.toISOString() };
  });

  // ── Health: errors, delivery problems, alerts ─────────────────────────────
  app.get('/health-feed', async () => {
    const now = new Date();
    const day = new Date(now.getTime() - DAY_MS);
    const [rules, errors, heartbeat, checkIns, aiRows, trips, photoQueue] = await Promise.all([
      readAlertRules(prisma),
      readErrors(prisma),
      prisma.schedulerHeartbeat.findUnique({ where: { job: 'score' } }),
      prisma.checkIn.findMany({
        where: { createdAt: { gte: day } },
        select: { deliveryStatus: true, lastPushError: true, createdAt: true, userId: true },
      }),
      prisma.aiUsage.findMany({ where: { createdAt: { gte: day } }, select: { kind: true } }),
      prisma.expertSafetyTrip.count({ where: { createdAt: { gte: day } } }),
      prisma.pendingPhotoDeletion.count(),
    ]);

    const failed = checkIns.filter((c) => c.deliveryStatus === 'FAILED');
    const failPct = checkIns.length ? Math.round((failed.length / checkIns.length) * 1000) / 10 : 0;
    const spend = Math.round(aiRows.reduce((s, r) => s + estimateUsd(r.kind, 1), 0) * 100) / 100;
    const lastHourErrors = errors.filter((e) => now.getTime() - new Date(e.at).getTime() < 3_600_000).length;
    const minutesSinceRun = heartbeat ? Math.round((now.getTime() - heartbeat.lastRunAt.getTime()) / 60_000) : null;

    type Alert = { key: string; level: 'warn' | 'bad'; title: string; detail: string };
    const alerts: Alert[] = [];
    if (rules.cronMissed.on && (minutesSinceRun === null || minutesSinceRun > 30 || heartbeat?.lastOk === false)) {
      alerts.push({ key: 'cron', level: 'bad', title: 'Scoring job is late or failing', detail: minutesSinceRun === null ? 'It has never run.' : `Last run ${minutesSinceRun} min ago${heartbeat?.lastOk === false ? ', and it failed' : ''}.` });
    }
    if (rules.pushFailure.on && checkIns.length >= 5 && failPct > rules.pushFailure.pct) {
      alerts.push({ key: 'push', level: 'warn', title: `Push failures at ${failPct}%`, detail: `${failed.length} of ${checkIns.length} check-ins in 24 h. Limit ${rules.pushFailure.pct}%.` });
    }
    if (rules.aiSpend.on && spend > rules.aiSpend.usd) {
      alerts.push({ key: 'ai', level: 'warn', title: `AI spend $${spend} today`, detail: `Limit $${rules.aiSpend.usd}. Budget in the ops page is $${AI_DAILY_BUDGET_USD}.` });
    }
    if (rules.serverErrors.on && lastHourErrors >= rules.serverErrors.count) {
      alerts.push({ key: 'errors', level: 'bad', title: `${lastHourErrors} server errors in the last hour`, detail: `Limit ${rules.serverErrors.count}.` });
    }
    if (rules.safetyTrip.on && trips > 0) {
      alerts.push({ key: 'safety', level: 'warn', title: `${trips} expert safety trip${trips === 1 ? '' : 's'} today`, detail: 'Review them in the expert audit.' });
    }

    const hours = new Array<number>(24).fill(0);
    const hoursFailed = new Array<number>(24).fill(0);
    for (const c of checkIns) {
      const h = Math.min(23, Math.floor((now.getTime() - c.createdAt.getTime()) / 3_600_000));
      hours[23 - h] = (hours[23 - h] ?? 0) + 1;
      if (c.deliveryStatus === 'FAILED') hoursFailed[23 - h] = (hoursFailed[23 - h] ?? 0) + 1;
    }
    const failures = failed
      .slice(0, 20)
      .map((c) => ({ at: c.createdAt.toISOString(), userId: c.userId, reason: c.lastPushError ?? 'unknown' }));

    return {
      alerts,
      rules,
      defaults: DEFAULT_ALERT_RULES,
      errors: errors.slice(0, 30),
      failures,
      perHour: { sent: hours, failed: hoursFailed },
      totals: { checkIns: checkIns.length, failed: failed.length, failPct, aiSpend: spend, safetyTrips: trips, photoQueue },
    };
  });

  app.get('/audit', async () => ({ entries: (await readAudit(prisma)).slice(0, 200) }));

  // ── Funnel: where new people drop off ─────────────────────────────────────
  app.get('/funnel', async (req) => {
    const { days } = z.object({ days: z.coerce.number().int().min(7).max(90).default(30) }).parse(req.query);
    const since = new Date(Date.now() - days * DAY_MS);
    const users = await prisma.user.findMany({
      where: { createdAt: { gte: since } },
      select: {
        createdAt: true,
        onboarding: { select: { completedAt: true } },
        meals: { select: { loggedAt: true }, orderBy: { loggedAt: 'desc' }, take: 1 },
        _count: { select: { meals: true } },
      },
    });
    const age = (u: (typeof users)[number]) => Date.now() - u.createdAt.getTime();
    const lastMealDays = (u: (typeof users)[number]) => (u.meals[0] ? (u.meals[0].loggedAt.getTime() - u.createdAt.getTime()) / DAY_MS : -1);
    const steps = [
      { key: 'signed_up', label: 'Signed up', n: users.length },
      { key: 'onboarded', label: 'Finished onboarding', n: users.filter((u) => u.onboarding?.completedAt).length },
      { key: 'first_meal', label: 'Logged first meal', n: users.filter((u) => u._count.meals > 0).length },
      { key: 'day3', label: 'Still logging day 3', n: users.filter((u) => age(u) >= 3 * DAY_MS && lastMealDays(u) >= 3).length, of: users.filter((u) => age(u) >= 3 * DAY_MS).length },
      { key: 'day7', label: 'Still logging day 7', n: users.filter((u) => age(u) >= 7 * DAY_MS && lastMealDays(u) >= 7).length, of: users.filter((u) => age(u) >= 7 * DAY_MS).length },
    ];
    const quiet = await prisma.user.count({
      where: { onboarding: { is: { completedAt: { not: null } } }, meals: { some: {}, none: { loggedAt: { gt: new Date(Date.now() - 3 * DAY_MS) } } } },
    });
    return { days, steps, quiet };
  });

  // ── View as: the person's home screen, read-only ─────────────────────────
  app.get('/users/:id/view-as', async (req) => {
    const { id: userId } = id.parse(req.params);
    try {
      return await buildHome({ prisma, voice: createManagerVoice(), photos: getPhotoStore() }, userId);
    } catch (err) {
      if (err instanceof OnboardingIncompleteError) throw app.httpErrors.conflict('they have not finished onboarding');
      throw err;
    }
  });

  // ── Data export for one person (their right to a copy) ───────────────────
  app.get('/users/:id/export', async (req, reply) => {
    const { id: userId } = id.parse(req.params);
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true, email: true, displayName: true, timezone: true, language: true, role: true, group: true,
        createdAt: true, subscriptionStatus: true, subscriptionExpiresAt: true,
        onboarding: true, restrictions: true,
        meals: { orderBy: { loggedAt: 'asc' }, select: { loggedAt: true, source: true, rawInput: true, kcal: true, proteinG: true, carbsG: true, fatG: true, items: true } },
        weightEntries: { orderBy: { measuredAt: 'asc' } },
        workouts: true,
        dayOutcomes: true,
        checkIns: { select: { createdAt: true, kind: true, status: true, slot: true, message: true } },
      },
    });
    if (!user) throw app.httpErrors.notFound('no such person');
    reply.header('content-disposition', `attachment; filename="setpoint-${userId}.json"`);
    return { exportedAt: new Date().toISOString(), user };
  });

  // ── Food catalog ──────────────────────────────────────────────────────────
  app.get('/catalog', async (req) => {
    const q = z
      .object({ kind: z.enum(['catalog', 'barcode']).default('catalog'), q: z.string().max(80).optional(), limit: z.coerce.number().int().min(1).max(100).default(40) })
      .parse(req.query);
    const where = q.q ? { name: { contains: q.q, mode: 'insensitive' as const } } : {};
    const [rows, total] =
      q.kind === 'catalog'
        ? await Promise.all([
            prisma.catalogFood.findMany({ where, orderBy: { name: 'asc' }, take: q.limit, select: { id: true, name: true, servingG: true, servingDesc: true, kcal100g: true, proteinG100g: true, carbsG100g: true, fatG100g: true, updatedAt: true } }),
            prisma.catalogFood.count(),
          ])
        : await Promise.all([
            prisma.barcodeFood.findMany({ where, orderBy: { name: 'asc' }, take: q.limit, select: { id: true, name: true, servingG: true, kcal100g: true, proteinG100g: true, carbsG100g: true, fatG100g: true, updatedAt: true, code: true, brand: true } }),
            prisma.barcodeFood.count(),
          ]);
    // Per-100g kcal outside what any real food has: surfaced so a typo is easy to spot.
    const rowsOut = rows.map((r) => ({ ...r, suspicious: r.kcal100g > 900 || r.proteinG100g + r.carbsG100g + r.fatG100g > 105 }));
    return { kind: q.kind, total, rows: rowsOut };
  });

  app.patch('/catalog/:kind/:id', async (req) => {
    const { kind, id: foodId } = z.object({ kind: z.enum(['catalog', 'barcode']), id: z.string().min(1) }).parse(req.params);
    const data = catalogPatch.parse(req.body);
    if (Object.keys(data).length === 0) throw app.httpErrors.badRequest('nothing to change');
    try {
      return kind === 'catalog'
        ? await prisma.catalogFood.update({ where: { id: foodId }, data })
        : await prisma.barcodeFood.update({ where: { id: foodId }, data });
    } catch {
      throw app.httpErrors.notFound('no such food');
    }
  });
}
