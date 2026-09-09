import type { Goal } from '../engine/types.js';

export type DayKind = 'ON_TRACK' | 'UNDER' | 'OVER' | 'MISSED';

/** Home-screen framing state. Urgency is reserved for under-eating (plan §5.2). */
export type FramingState = 'under' | 'over' | 'on_track';

export const CLASSIFY_CONFIG = {
  /** A settled day below this fraction of target counts as UNDER. */
  underDayRatio: 0.85,
  /** Above this fraction of target counts as OVER. */
  overDayRatio: 1.15,

  /** On the home screen, this many kcal still to eat shows the under-eating accent. */
  homeUnderKcal: 100,
  /** This many kcal past target reads as OVER (quiet, neutral — never urgent). */
  homeOverKcal: 150,
} as const;

/** Classifies a *completed* day for the settlement view (plan §5.7). */
export function classifyDay(
  consumedKcal: number,
  targetKcal: number,
  config = CLASSIFY_CONFIG,
): DayKind {
  if (consumedKcal <= 0) return 'MISSED';
  if (targetKcal <= 0) return 'ON_TRACK';
  const ratio = consumedKcal / targetKcal;
  if (ratio < config.underDayRatio) return 'UNDER';
  if (ratio > config.overDayRatio) return 'OVER';
  return 'ON_TRACK';
}

/**
 * Home-screen framing (plan §5.2): the accent and primary CTA are reserved for
 * under-eating and apply regardless of goal; going over gets a quiet, neutral
 * treatment. `heroKcal` is the signed gap (positive = still to eat).
 */
export function homeFraming(
  goal: Goal,
  consumedKcal: number,
  targetKcal: number,
  config = CLASSIFY_CONFIG,
): {
  goal: Goal;
  state: FramingState;
  accent: boolean;
  primaryCta: 'log_meal' | null;
  heroKcal: number;
} {
  const heroKcal = Math.round(targetKcal - consumedKcal);

  let state: FramingState;
  if (heroKcal >= config.homeUnderKcal) state = 'under';
  else if (heroKcal <= -config.homeOverKcal) state = 'over';
  else state = 'on_track';

  return {
    goal,
    state,
    accent: state === 'under',
    primaryCta: state === 'under' ? 'log_meal' : null,
    heroKcal,
  };
}
