import type { PrismaClient } from '@prisma/client';
import { localMinutesOfDay } from '../engine/quietHours.js';
import { langOf, type Lang } from '../i18n/index.js';
import { deliverCheckIn } from '../push/deliver.js';
import type { PushSender } from '../push/types.js';

/** A weigh-in is due once the last one is this old. Matches `needsWeighIn` on Today. */
const DUE_AFTER_MS = 7 * 24 * 3_600_000;
/** Reminded at most this often, so a skipped weigh-in is nudged twice a week, not daily. */
const REMIND_EVERY_MS = 3 * 24 * 3_600_000;
/** A new account isn't asked to weigh in before it has had a couple of days. */
const MIN_ACCOUNT_AGE_MS = 2 * 24 * 3_600_000;
/** Local 10:00–19:00: a wide window, because the scoring timer can run unevenly; one reminder per 3 days still holds. */
const WINDOW_START_MIN = 10 * 60;
const WINDOW_END_MIN = 19 * 60;

export type WeighInReminderSummary = { considered: number; sent: number; failed: number };

export function inReminderWindow(now: Date, timezone: string): boolean {
  const min = localMinutesOfDay(now, timezone);
  return min >= WINDOW_START_MIN && min < WINDOW_END_MIN;
}

export function weighInCopy(lang: Lang): { title: string; body: string } {
  return lang === 'he'
    ? { title: 'הגיע הזמן להישקל', body: 'עברה שבוע. זה לוקח עשר שניות, וכך התוכנית נשארת מדויקת.' }
    : { title: 'Weigh-in time', body: 'It’s been a week. Ten seconds keeps your plan accurate.' };
}

const keyOf = (userId: string) => `weighin-reminder:${userId}`;

/**
 * Sends the weekly weigh-in reminder: its own notification, separate from meal check-ins.
 * Only to people with a weight goal, check-ins on, a device, and a weigh-in a week old.
 * The last send is kept in AppConfig, so no migration and no double send.
 */
export async function runWeighInReminderJob(deps: {
  prisma: PrismaClient;
  push: PushSender;
  now?: Date;
}): Promise<WeighInReminderSummary> {
  const now = deps.now ?? new Date();
  const summary: WeighInReminderSummary = { considered: 0, sent: 0, failed: 0 };
  const users = await deps.prisma.user.findMany({
    where: {
      onboarding: { is: { completedAt: { not: null, lt: new Date(now.getTime() - MIN_ACCOUNT_AGE_MS) }, goal: { not: 'MAINTAIN' } } },
      safetyScreening: { is: { enforcementEnabled: true } },
      pushTokens: { some: { kind: 'alert' } },
      weightEntries: { none: { measuredAt: { gt: new Date(now.getTime() - DUE_AFTER_MS) } } },
    },
    select: { id: true, timezone: true, language: true, escalationState: { select: { checkInsPaused: true } } },
  });

  for (const user of users) {
    if (user.escalationState?.checkInsPaused) continue;
    if (!inReminderWindow(now, user.timezone)) continue;
    summary.considered += 1;

    const last = await deps.prisma.appConfig.findUnique({ where: { key: keyOf(user.id) } });
    const lastAt = (last?.value as { at?: string } | null)?.at;
    if (lastAt && now.getTime() - new Date(lastAt).getTime() < REMIND_EVERY_MS) continue;

    const copy = weighInCopy(langOf(user.language));
    const outcome = await deliverCheckIn({
      prisma: deps.prisma,
      push: deps.push,
      userId: user.id,
      payload: { userId: user.id, checkInId: '', tier: 1, title: copy.title, body: copy.body, weighIn: true },
    });
    if (outcome.status === 'SENT') {
      summary.sent += 1;
      await deps.prisma.appConfig.upsert({
        where: { key: keyOf(user.id) },
        create: { key: keyOf(user.id), value: { at: now.toISOString() } },
        update: { value: { at: now.toISOString() } },
      });
    } else {
      summary.failed += 1;
    }
  }
  return summary;
}
