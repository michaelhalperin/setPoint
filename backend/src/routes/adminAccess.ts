import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { generateInviteCode, normalizeInviteCode } from '../access/invites.js';
import { AccountNotFoundError, deleteAccount, deleteAccounts } from '../account/deleteAccount.js';
import { summarizeEvents } from '../analytics/events.js';
import { getPrisma } from '../db/client.js';
import { env, isProd } from '../env.js';
import { FLAGS, isFlagKey } from '../flags/index.js';
import { getPhotoStore } from '../photos/store.js';
import { requireAdmin } from './admin.js';

const role = z.enum(['USER', 'TRAINER', 'ADMIN']);
const cohort = z.string().trim().min(1).max(64);

const createInvite = z.object({
  /** Leave out for a random 8-character code. */
  code: z.string().min(3).max(32).optional(),
  cohort: cohort.optional(),
  role: role.optional(),
  maxUses: z.number().int().positive().optional(),
  expiresAt: z.string().datetime().optional(),
  note: z.string().max(200).optional(),
});

const updateUser = z.object({
  role: role.optional(),
  /** null takes them out of their cohort. */
  cohort: cohort.nullable().optional(),
  /** Let someone in without a code. Their pending session upgrades on its next request. */
  access: z.literal(true).optional(),
});

const deleteUsersBody = z.object({
  ids: z.array(z.string().min(1)).min(1).max(500),
});

const updateFlag = z.object({
  /** On for everyone. */
  enabled: z.boolean().optional(),
  cohorts: z.array(cohort).optional(),
  roles: z.array(role).optional(),
  userIds: z.array(z.string().min(1)).optional(),
  note: z.string().max(200).nullable().optional(),
});

const userQuery = z.object({
  cohort: z.string().optional(),
  role: role.optional(),
  /** Only accounts still waiting for an invite. */
  pending: z.enum(['true', 'false']).optional(),
  /** Part of an email address. */
  q: z.string().max(100).optional(),
});

const analyticsQuery = z.object({
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional(),
  cohort: z.string().optional(),
});

const ANALYTICS_DEFAULT_DAYS = 14;
const ANALYTICS_MAX_ROWS = 100_000;

const userFields = {
  id: true,
  email: true,
  role: true,
  cohort: true,
  accessGrantedAt: true,
  createdAt: true,
  inviteCode: { select: { code: true } },
  onboarding: { select: { completedAt: true } },
  _count: { select: { meals: true } },
} as const;

/** Invites, roles and cohorts — who gets in and who is who. */
export async function adminAccessRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAdmin(app));

  // The switches that live in Vercel's environment, and who's in the app.
  app.get('/status', async () => {
    const prisma = getPrisma();
    const [users, pending, onboarded, byRole, byCohort] = await Promise.all([
      prisma.user.count(),
      prisma.user.count({ where: { accessGrantedAt: null } }),
      prisma.onboardingProfile.count({ where: { completedAt: { not: null } } }),
      prisma.user.groupBy({ by: ['role'], _count: { _all: true } }),
      prisma.user.groupBy({ by: ['cohort'], _count: { _all: true }, where: { cohort: { not: null } } }),
    ]);
    return {
      environment: env.SENTRY_ENVIRONMENT || (isProd ? 'production' : env.NODE_ENV),
      switches: {
        inviteOnly: env.INVITE_ONLY === 'true',
        nearbySampleVenues: env.NEARBY_SAMPLE_VENUES === 'true',
        subscriptionGate: env.SUBSCRIPTION_GATE === 'true',
        devLogin: !isProd || env.ENABLE_DEV_LOGIN === 'true',
        wearableModifier: env.WEARABLE_MODIFIER_ENABLED === 'true',
        aiConfigured: env.ANTHROPIC_API_KEY !== '',
      },
      users: {
        total: users,
        pending,
        onboarded,
        byRole: Object.fromEntries(byRole.map((r) => [r.role, r._count._all])),
      },
      cohorts: byCohort
        .map((c) => ({ cohort: c.cohort as string, users: c._count._all }))
        .sort((a, b) => b.users - a.users),
    };
  });

  app.get('/invites', async () => {
    const invites = await getPrisma().inviteCode.findMany({ orderBy: { createdAt: 'desc' } });
    return { invites };
  });

  app.post('/invites', async (req) => {
    const body = createInvite.parse(req.body ?? {});
    const code = body.code ? normalizeInviteCode(body.code) : generateInviteCode();
    const existing = await getPrisma().inviteCode.findUnique({ where: { code } });
    if (existing) throw app.httpErrors.conflict('code already exists');
    const invite = await getPrisma().inviteCode.create({
      data: {
        code,
        cohort: body.cohort ?? null,
        role: body.role ?? 'USER',
        maxUses: body.maxUses ?? null,
        expiresAt: body.expiresAt ? new Date(body.expiresAt) : null,
        note: body.note ?? null,
      },
    });
    return { invite };
  });

  app.post('/invites/:code/disable', async (req) => {
    const { code } = z.object({ code: z.string().min(1) }).parse(req.params);
    const found = await getPrisma().inviteCode.findUnique({ where: { code: normalizeInviteCode(code) } });
    if (!found) throw app.httpErrors.notFound('no such code');
    const invite = await getPrisma().inviteCode.update({ where: { id: found.id }, data: { disabledAt: new Date() } });
    return { invite };
  });

  app.get('/users', async (req) => {
    const q = userQuery.parse(req.query);
    const users = await getPrisma().user.findMany({
      where: {
        ...(q.cohort ? { cohort: q.cohort } : {}),
        ...(q.role ? { role: q.role } : {}),
        ...(q.pending === 'true' ? { accessGrantedAt: null } : {}),
        ...(q.q ? { email: { contains: q.q, mode: 'insensitive' as const } } : {}),
      },
      select: userFields,
      orderBy: { createdAt: 'desc' },
      take: 500,
    });
    return { users };
  });

  app.patch('/users/:id', async (req) => {
    const { id } = z.object({ id: z.string().min(1) }).parse(req.params);
    const body = updateUser.parse(req.body ?? {});
    const existing = await getPrisma().user.findUnique({ where: { id }, select: { accessGrantedAt: true } });
    if (!existing) throw app.httpErrors.notFound('no such user');
    const user = await getPrisma().user.update({
      where: { id },
      data: {
        ...(body.role ? { role: body.role } : {}),
        ...(body.cohort !== undefined ? { cohort: body.cohort } : {}),
        ...(body.access ? { accessGrantedAt: existing.accessGrantedAt ?? new Date() } : {}),
      },
      select: userFields,
    });
    return { user };
  });

  // Cascading delete — same path as Settings → Delete account. For clearing
  // premade / test people from the operator page.
  app.delete('/users/:id', async (req) => {
    const { id } = z.object({ id: z.string().min(1) }).parse(req.params);
    try {
      return await deleteAccount({ prisma: getPrisma(), photos: getPhotoStore() }, id);
    } catch (err) {
      if (err instanceof AccountNotFoundError) throw app.httpErrors.notFound(err.message);
      throw err;
    }
  });

  app.post('/users/delete', async (req) => {
    const { ids } = deleteUsersBody.parse(req.body ?? {});
    return deleteAccounts({ prisma: getPrisma(), photos: getPhotoStore() }, ids);
  });

  // Every declared flag with its default and override, if any.
  app.get('/flags', async () => {
    const rows = new Map((await getPrisma().featureFlag.findMany()).map((r) => [r.key, r]));
    return {
      flags: Object.entries(FLAGS).map(([key, def]) => ({ key, ...def, override: rows.get(key) ?? null })),
    };
  });

  // Override a flag. Lists replace what was there; leave a field out to keep it.
  app.put('/flags/:key', async (req) => {
    const { key } = z.object({ key: z.string().min(1) }).parse(req.params);
    if (!isFlagKey(key)) throw app.httpErrors.notFound('no such flag');
    const body = updateFlag.parse(req.body ?? {});
    const data = {
      ...(body.enabled !== undefined ? { enabled: body.enabled } : {}),
      ...(body.cohorts ? { cohorts: body.cohorts } : {}),
      ...(body.roles ? { roles: body.roles } : {}),
      ...(body.userIds ? { userIds: body.userIds } : {}),
      ...(body.note !== undefined ? { note: body.note } : {}),
    };
    const flag = await getPrisma().featureFlag.upsert({ where: { key }, create: { key, ...data }, update: data });
    return { flag };
  });

  // Back to the default in code.
  app.delete('/flags/:key', async (req) => {
    const { key } = z.object({ key: z.string().min(1) }).parse(req.params);
    await getPrisma().featureFlag.deleteMany({ where: { key } });
    return { ok: true };
  });

  // Product numbers for a range (default: the last two weeks), optionally for one
  // cohort — e.g. ?cohort=beta.
  app.get('/analytics', async (req) => {
    const q = analyticsQuery.parse(req.query);
    const to = q.to ? new Date(q.to) : new Date();
    const from = q.from ? new Date(q.from) : new Date(to.getTime() - ANALYTICS_DEFAULT_DAYS * 86_400_000);
    const rows = await getPrisma().analyticsEvent.findMany({
      where: { occurredAt: { gte: from, lte: to }, ...(q.cohort ? { user: { cohort: q.cohort } } : {}) },
      select: { userId: true, name: true, props: true, occurredAt: true },
      orderBy: { occurredAt: 'asc' },
      take: ANALYTICS_MAX_ROWS,
    });
    const summary = summarizeEvents(rows);
    const problemUserIds = [
      ...new Set(summary.problems.recent.map((r) => r.userId).filter((id): id is string => !!id)),
    ];
    const emails = problemUserIds.length
      ? await getPrisma().user.findMany({
          where: { id: { in: problemUserIds } },
          select: { id: true, email: true },
        })
      : [];
    const emailById = new Map(emails.map((u) => [u.id, u.email]));
    return {
      range: { from: from.toISOString(), to: to.toISOString() },
      cohort: q.cohort ?? null,
      truncated: rows.length === ANALYTICS_MAX_ROWS,
      ...summary,
      problems: {
        ...summary.problems,
        recent: summary.problems.recent.map((r) => ({
          ...r,
          email: r.userId ? (emailById.get(r.userId) ?? null) : null,
        })),
      },
    };
  });
}
