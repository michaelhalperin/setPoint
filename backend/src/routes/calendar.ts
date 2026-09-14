import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { requireEntitlement } from '../subscription/requireEntitlement.js';
import { localDateISO, startOfLocalDay } from '../engine/time.js';
import { toMinuteBlocks } from '../engine/calendarBusy.js';
import { clearBusy, replaceBusyWindow } from '../calendar/replaceBusy.js';

const iso = z.string().min(10);

const busyBody = z.object({
  from: iso,
  to: iso,
  blocks: z
    .array(z.object({ start: iso, end: iso }))
    .max(200),
});

export async function calendarRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  app.put('/busy', async (req) => {
    const body = busyBody.parse(req.body);
    const from = new Date(body.from);
    const to = new Date(body.to);
    if (!(to.getTime() - from.getTime() > 0) || to.getTime() - from.getTime() > 48 * 3_600_000) {
      throw app.httpErrors.badRequest('busy window must be between 0 and 48 hours');
    }
    const userId = (req as AuthedRequest).userId;
    await requireEntitlement(app, userId);
    const stored = await replaceBusyWindow(
      getPrisma(),
      userId,
      from,
      to,
      body.blocks.map((b) => ({ start: new Date(b.start), end: new Date(b.end) })),
    );
    return { stored };
  });

  app.get('/', async (req) => {
    const prisma = getPrisma();
    const userId = (req as AuthedRequest).userId;
    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: { onboarding: true },
    });
    if (!user?.onboarding) throw app.httpErrors.conflict('onboarding not complete');
    const p = user.onboarding;
    const now = new Date();
    const weekAgo = new Date(now.getTime() - 7 * 86_400_000);
    const weekEnd = new Date(now.getTime() + 7 * 86_400_000);
    const [moved, blocks] = await Promise.all([
      prisma.checkIn.count({
        where: { userId, movedFromMin: { not: null }, createdAt: { gte: weekAgo } },
      }),
      prisma.calendarBusyBlock.findMany({
        where: { userId, start: { lt: weekEnd }, end: { gt: weekAgo } },
        select: { start: true, end: true },
        orderBy: { start: 'asc' },
      }),
    ]);
    const week: { date: string; startMin: number; endMin: number }[] = [];
    for (let i = 0; i < 7; i += 1) {
      const day = new Date(now.getTime() + i * 86_400_000);
      const dayStart = startOfLocalDay(day, user.timezone);
      const date = localDateISO(dayStart, user.timezone);
      for (const block of toMinuteBlocks(blocks, dayStart, user.timezone)) {
        week.push({ date, startMin: block.startMin, endMin: block.endMin });
      }
    }
    return {
      enabled: p.calendarEnabled,
      leadMin: p.calendarLeadMin,
      minBlockMin: p.calendarMinBlockMin,
      workdaysOnly: p.calendarWorkdaysOnly,
      includeAllDay: p.calendarIncludeAllDay,
      mealsMovedThisWeek: moved,
      week,
    };
  });

  app.delete('/', async (req) => {
    const prisma = getPrisma();
    const userId = (req as AuthedRequest).userId;
    await prisma.onboardingProfile.updateMany({
      where: { userId },
      data: { calendarEnabled: false },
    });
    await clearBusy(prisma, userId);
    return { enabled: false };
  });
}
