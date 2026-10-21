import { PRE_WORKOUT_LOOKBACK_MIN, REFUEL_MIN_KCAL, REFUEL_WINDOW_MIN } from '../engine/training.js';

/**
 * Plain-word status for the Train screen: did the person eat around a session?
 * Pure; the workouts route passes the day's sessions and meals.
 */

export type SessionLike = { start: Date; durationMin: number };
export type MealLike = { loggedAt: Date; kcal: number };

/** done · missed · due (the refuel window is open now) · planned (hasn't happened yet). */
export type RefuelStatus = 'done' | 'missed' | 'due' | 'planned';

const SNACK_MIN_KCAL = 150;
const DINNER_LOOKBACK_MIN = 90;

const endOf = (w: SessionLike) => w.start.getTime() + w.durationMin * 60_000;

function refuelled(w: SessionLike, meals: MealLike[]): boolean {
  const ended = endOf(w);
  const until = ended + REFUEL_WINDOW_MIN * 60_000;
  return meals.some((m) => m.kcal >= REFUEL_MIN_KCAL && m.loggedAt.getTime() >= ended && m.loggedAt.getTime() <= until);
}

/** The first meal that counted as a refuel after any of the day's finished sessions. */
export function refuelMealFor(sessions: SessionLike[], meals: MealLike[]): { at: string; kcal: number } | null {
  for (const w of sessions) {
    const ended = endOf(w);
    const until = ended + REFUEL_WINDOW_MIN * 60_000;
    const meal = meals
      .filter((m) => m.kcal >= REFUEL_MIN_KCAL && m.loggedAt.getTime() >= ended && m.loggedAt.getTime() <= until)
      .sort((a, b) => a.loggedAt.getTime() - b.loggedAt.getTime())[0];
    if (meal) return { at: meal.loggedAt.toISOString(), kcal: meal.kcal };
  }
  return null;
}

/** The day's status, from its sessions in time order. Null on a rest day. */
export function refuelStatus(sessions: SessionLike[], meals: MealLike[], now: Date): RefuelStatus | null {
  if (!sessions.length) return null;
  const finished = sessions.filter((w) => endOf(w) <= now.getTime());
  if (!finished.length) return 'planned';
  if (finished.some((w) => refuelled(w, meals))) return 'done';
  const last = finished[finished.length - 1]!;
  return endOf(last) + REFUEL_WINDOW_MIN * 60_000 > now.getTime() ? 'due' : 'missed';
}

/** Which of today's steps are done: a snack before, the session itself, the refuel, dinner. */
export function todaySteps(
  first: SessionLike | undefined,
  dinnerAt: Date,
  meals: MealLike[],
  now: Date,
): { before: boolean; workout: boolean; refuel: boolean; dinner: boolean } {
  const t = (d: Date) => d.getTime();
  const ateBetween = (from: number, to: number, min: number) => meals.some((m) => m.kcal >= min && t(m.loggedAt) >= from && t(m.loggedAt) < to);
  if (!first) {
    return { before: false, workout: false, refuel: false, dinner: ateBetween(t(dinnerAt) - DINNER_LOOKBACK_MIN * 60_000, Infinity, REFUEL_MIN_KCAL) };
  }
  const start = t(first.start);
  const end = endOf(first);
  return {
    before: ateBetween(start - PRE_WORKOUT_LOOKBACK_MIN * 60_000, start, SNACK_MIN_KCAL),
    workout: end <= t(now),
    refuel: refuelled(first, meals),
    dinner: ateBetween(Math.max(end + REFUEL_WINDOW_MIN * 60_000, t(dinnerAt) - DINNER_LOOKBACK_MIN * 60_000), Infinity, REFUEL_MIN_KCAL),
  };
}
