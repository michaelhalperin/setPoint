import type { FramingState } from './classify.js';

/**
 * The shape of today for the Today screen: the user's three meal times as
 * slots (what's logged, what's due now, what passed with nothing logged), where
 * "now" sits, and whether intake is keeping pace with their usual rhythm.
 *
 * Pure. Presentation math only — it never feeds the confidence engine, which
 * keeps its own deterministic formula (§2).
 */
export type SlotName = 'breakfast' | 'lunch' | 'dinner';
export type SlotState = 'logged' | 'now' | 'missed' | 'upcoming';

export type DaySlotView = {
  slot: SlotName;
  /** The usual meal time, minutes from local midnight. */
  atMin: number;
  state: SlotState;
  /** Today's meals that belong to this slot, in the order they were given. */
  mealIds: string[];
  kcal: number;
};

export type PaceView = {
  /** kcal the user's usual meal times say they'd have eaten by now. */
  expectedByNowKcal: number;
  /** How far under that pace (0 when on or ahead of it). */
  behindKcal: number;
  status: 'behind' | 'on_pace' | 'ahead';
  /** The next meal worth eating and a suggested size; null once nothing is still due. */
  next: { slot: SlotName; atMin: number; suggestedKcal: number } | null;
};

export type DayView = {
  /** Now, minutes from local midnight. */
  nowMin: number;
  slots: DaySlotView[];
  /** Null in quiet mode (enforcement disabled): no pace or "behind" framing at all (§3). */
  pace: PaceView | null;
};

export const DAY_CONFIG = {
  /** An empty slot reads as "now" from this long before its usual time. */
  nowLeadMin: 60,
  /** Each meal's share of expected intake ramps in across this window around its time. */
  rampStartOffsetMin: -30,
  rampEndOffsetMin: 60,
  /** Share of the day's target each meal carries. Equal thirds for v1 — tune in beta. */
  shares: { breakfast: 1 / 3, lunch: 1 / 3, dinner: 1 / 3 } as Record<SlotName, number>,
  /** A gap this large between eaten and expected reads as behind / ahead. */
  paceToleranceKcal: 300,
  /** Never suggest a next meal smaller than this. */
  minSuggestionKcal: 150,
} as const;

export type DayConfig = typeof DAY_CONFIG;

export type DayInput = {
  nowMin: number;
  mealTimes: { breakfastMin: number; lunchMin: number; dinnerMin: number };
  /** Today's meals with the local minute of day they were logged at. */
  meals: { id: string; minuteOfDay: number; kcal: number }[];
  targetKcal: number;
  consumedKcal: number;
  framingState: FramingState;
  enforcementEnabled: boolean;
};

const SLOTS: SlotName[] = ['breakfast', 'lunch', 'dinner'];
const MINUTES_PER_DAY = 1440;

const round10 = (n: number): number => Math.round(n / 10) * 10;
const round50 = (n: number): number => Math.round(n / 50) * 50;
const clamp01 = (n: number): number => Math.min(1, Math.max(0, n));

export function buildDay(input: DayInput, config: DayConfig = DAY_CONFIG): DayView {
  const { breakfastMin, lunchMin, dinnerMin } = input.mealTimes;
  const at: Record<SlotName, number> = { breakfast: breakfastMin, lunch: lunchMin, dinner: dinnerMin };

  // A meal belongs to the slot whose usual time it's closest to: the boundaries
  // sit halfway between meal times (a 12:50 meal is lunch, not a late breakfast).
  const slotEnds = [
    Math.floor((breakfastMin + lunchMin) / 2),
    Math.floor((lunchMin + dinnerMin) / 2),
    MINUTES_PER_DAY,
  ];
  const slotOf = (minute: number): SlotName =>
    minute < slotEnds[0]! ? 'breakfast' : minute < slotEnds[1]! ? 'lunch' : 'dinner';

  const slots: DaySlotView[] = SLOTS.map((slot, i) => {
    const meals = input.meals.filter((m) => slotOf(m.minuteOfDay) === slot);
    let state: SlotState;
    if (meals.length > 0) state = 'logged';
    else if (input.nowMin >= slotEnds[i]!) state = 'missed';
    else if (input.nowMin >= at[slot] - config.nowLeadMin) state = 'now';
    else state = 'upcoming';

    return {
      slot,
      atMin: at[slot],
      state,
      mealIds: meals.map((m) => m.id),
      kcal: meals.reduce((sum, m) => sum + m.kcal, 0),
    };
  });

  if (!input.enforcementEnabled) return { nowMin: input.nowMin, slots, pace: null };

  const rampSpan = config.rampEndOffsetMin - config.rampStartOffsetMin;
  const expectedShare = SLOTS.reduce(
    (sum, slot) =>
      sum + config.shares[slot] * clamp01((input.nowMin - (at[slot] + config.rampStartOffsetMin)) / rampSpan),
    0,
  );
  const expectedByNowKcal = round10(input.targetKcal * expectedShare);
  const delta = input.consumedKcal - expectedByNowKcal;
  const status: PaceView['status'] =
    delta <= -config.paceToleranceKcal ? 'behind' : delta >= config.paceToleranceKcal ? 'ahead' : 'on_pace';

  let next: PaceView['next'] = null;
  const remainingKcal = input.targetKcal - input.consumedKcal;
  if (input.framingState === 'under' && remainingKcal > 0) {
    const open = slots.filter((s) => s.state === 'now' || s.state === 'upcoming');
    const first = open[0];
    if (first) {
      next = {
        slot: first.slot,
        atMin: first.atMin,
        suggestedKcal: Math.max(config.minSuggestionKcal, round50(remainingKcal / open.length)),
      };
    }
  }

  return {
    nowMin: input.nowMin,
    slots,
    pace: { expectedByNowKcal, behindKcal: Math.max(0, round10(-delta)), status, next },
  };
}
