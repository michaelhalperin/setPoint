/** Milliseconds elapsed since local midnight in the given IANA timezone. */
export function msSinceLocalMidnight(date: Date, timeZone: string): number {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour12: false,
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(date);

  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? '0');
  const hours = get('hour') % 24;
  const minutes = get('minute');
  const seconds = get('second');

  return ((hours * 60 + minutes) * 60 + seconds) * 1000 + date.getMilliseconds();
}

/**
 * The instant of the most recent local midnight for `date` in `timeZone`.
 * (Assumes no DST transition between that midnight and `date` — fine for a
 * "meals logged today" boundary.)
 */
export function startOfLocalDay(date: Date, timeZone: string): Date {
  return new Date(date.getTime() - msSinceLocalMidnight(date, timeZone));
}

/** The local calendar date in `timeZone` as an ISO `YYYY-MM-DD` string. */
export function localDateISO(date: Date, timeZone: string): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
}

/** A `YYYY-MM-DD` string as a UTC-midnight Date (for Prisma `@db.Date` columns). */
export function dateOnly(iso: string): Date {
  return new Date(`${iso}T00:00:00.000Z`);
}

/** Shifts a `YYYY-MM-DD` string by whole days (UTC-anchored, DST-immune). */
export function shiftDateISO(iso: string, days: number): string {
  const shifted = new Date(dateOnly(iso).getTime() + days * 86_400_000);
  return shifted.toISOString().slice(0, 10);
}
