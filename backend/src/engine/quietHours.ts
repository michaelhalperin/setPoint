/**
 * Minutes since local midnight (0..1439) for `date` in the given IANA timezone.
 * Uses Intl so DST is handled without a dependency.
 */
export function localMinutesOfDay(date: Date, timeZone: string): number {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour12: false,
    hour: '2-digit',
    minute: '2-digit',
  }).formatToParts(date);

  const hour = Number(parts.find((p) => p.type === 'hour')?.value ?? '0') % 24;
  const minute = Number(parts.find((p) => p.type === 'minute')?.value ?? '0');
  return hour * 60 + minute;
}

/**
 * Whether `nowMin` falls inside the half-open window [startMin, endMin),
 * handling windows that wrap past midnight (e.g. 23:00 → 07:00).
 * A zero-width window (start === end) means "no quiet hours".
 */
export function isWithinQuietHours(nowMin: number, startMin: number, endMin: number): boolean {
  if (startMin === endMin) return false;
  if (startMin < endMin) return nowMin >= startMin && nowMin < endMin;
  return nowMin >= startMin || nowMin < endMin;
}
