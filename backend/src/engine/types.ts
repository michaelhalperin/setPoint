/** Engine-local types. The engine never imports the Prisma client — the job
 *  layer maps database rows onto these shapes. */

export type Mode = 'BASIC' | 'SMART';

export type Goal = 'BULK' | 'DIET' | 'MAINTAIN';

export const clamp = (value: number, lo: number, hi: number): number =>
  Math.min(hi, Math.max(lo, value));

export const MS_PER_HOUR = 3_600_000;

export const hoursBetween = (earlier: Date, later: Date): number =>
  Math.max(0, (later.getTime() - earlier.getTime()) / MS_PER_HOUR);
