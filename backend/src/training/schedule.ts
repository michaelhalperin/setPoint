import { localDateISO, localDayRange, msSinceLocalMidnight, shiftDateISO, startOfLocalDay } from '../engine/time.js';

/**
 * Rules for planning sessions ahead: how far, and how "this and all after" moves
 * a weekly series. Pure; the workouts route does the queries.
 */

/** Sessions can be planned up to 8 weeks ahead. */
export const PLAN_HORIZON_DAYS = 56;
/** …and added up to a week back, for one done without the watch. */
export const PAST_ADD_DAYS = 7;

/** Why a new session can't start then, or null when it can. */
export function startProblem(start: Date, now: Date, timeZone: string): string | null {
  if (Number.isNaN(start.getTime())) return 'invalid start';
  const today = startOfLocalDay(now, timeZone);
  if (start < new Date(today.getTime() - PAST_ADD_DAYS * 86_400_000)) return 'more than a week ago';
  const lastDay = localDayRange(shiftDateISO(localDateISO(now, timeZone), PLAN_HORIZON_DAYS), timeZone).end;
  if (start >= lastDay) return 'more than 8 weeks ahead';
  return null;
}

/** An edit applies to a session only before it starts. */
export function canEdit(session: { source: string; start: Date }, now: Date): boolean {
  return session.source === 'PLANNED' && session.start > now;
}

function daysBetween(fromISO: string, toISO: string): number {
  const ms = (iso: string) => Date.UTC(Number(iso.slice(0, 4)), Number(iso.slice(5, 7)) - 1, Number(iso.slice(8, 10)));
  return Math.round((ms(toISO) - ms(fromISO)) / 86_400_000);
}

/**
 * "This and all after": the edited session moved from `oldStart` to `newStart`.
 * Each later one moves by the same number of days and takes the new time of day,
 * so "Mondays 18:00 → Tuesdays 07:00" stays on the clock across DST.
 */
export function followingStarts(
  rows: { id: string; start: Date }[],
  oldStart: Date,
  newStart: Date,
  timeZone: string,
): Map<string, Date> {
  const dayShift = daysBetween(localDateISO(oldStart, timeZone), localDateISO(newStart, timeZone));
  const minute = Math.round(msSinceLocalMidnight(newStart, timeZone) / 60_000);
  const out = new Map<string, Date>();
  for (const row of rows) {
    const date = shiftDateISO(localDateISO(row.start, timeZone), dayShift);
    out.set(row.id, new Date(localDayRange(date, timeZone).start.getTime() + minute * 60_000));
  }
  return out;
}
