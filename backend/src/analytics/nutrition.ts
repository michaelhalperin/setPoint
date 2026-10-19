import { localDateISO, shiftDateISO } from '../engine/time.js';

/**
 * Food and weight numbers for the owner's dashboard, read straight from meals,
 * day results and weigh-ins — so a fixed or deleted meal is always counted as it
 * is now. Pure functions; the admin routes do the queries.
 */

export type MealRow = { userId: string; loggedAt: Date; kcal: number; proteinG: number };
export type PersonTargets = { timezone: string; kcalTarget: number | null; proteinTargetG: number | null };
export type OutcomeRow = { userId: string; date: Date; kind: string; kcalConsumed: number; kcalTarget: number };
export type WeightRow = { userId: string; weightKg: number; measuredAt: Date };

const round = (n: number, places = 0) => {
  const f = 10 ** places;
  return Math.round(n * f) / f;
};

/** One person's last `days` local days: what they ate against their target. */
export function personDays(
  meals: MealRow[],
  person: PersonTargets,
  outcomes: OutcomeRow[],
  days: number,
  now: Date = new Date(),
) {
  const today = localDateISO(now, person.timezone);
  const byDate = new Map<string, { kcal: number; proteinG: number; meals: number }>();
  for (const m of meals) {
    const date = localDateISO(m.loggedAt, person.timezone);
    const d = byDate.get(date) ?? { kcal: 0, proteinG: 0, meals: 0 };
    d.kcal += m.kcal;
    d.proteinG += m.proteinG;
    d.meals += 1;
    byDate.set(date, d);
  }
  const outcomeByDate = new Map(outcomes.map((o) => [o.date.toISOString().slice(0, 10), o]));
  const out = [];
  for (let i = days - 1; i >= 0; i -= 1) {
    const date = shiftDateISO(today, -i);
    const eaten = byDate.get(date) ?? { kcal: 0, proteinG: 0, meals: 0 };
    const outcome = outcomeByDate.get(date);
    // A settled day's target includes training; otherwise the plan's daily target.
    const targetKcal = outcome?.kcalTarget ?? person.kcalTarget;
    out.push({
      date,
      kcal: eaten.kcal,
      targetKcal,
      proteinG: round(eaten.proteinG),
      targetProteinG: person.proteinTargetG,
      meals: eaten.meals,
      kind: outcome?.kind ?? (date === today ? 'TODAY' : null),
    });
  }
  return out;
}

/**
 * Across people: how close settled days came to target, and protein against
 * target on days with food. `targets` covers everyone whose meals are passed.
 */
export function nutritionOverview(
  outcomes: OutcomeRow[],
  meals: MealRow[],
  targets: Map<string, PersonTargets>,
) {
  const byDate = new Map<string, number[]>();
  let missed = 0;
  const shares: number[] = [];
  for (const o of outcomes) {
    if (o.kind === 'MISSED' || o.kcalConsumed <= 0) {
      missed += 1;
      continue;
    }
    if (o.kcalTarget <= 0) continue;
    const share = o.kcalConsumed / o.kcalTarget;
    shares.push(share);
    const date = o.date.toISOString().slice(0, 10);
    byDate.set(date, [...(byDate.get(date) ?? []), share]);
  }

  // Protein per person per local day, against that person's target.
  const proteinDays = new Map<string, number>();
  for (const m of meals) {
    const t = targets.get(m.userId);
    if (!t) continue;
    const key = `${m.userId}|${localDateISO(m.loggedAt, t.timezone)}`;
    proteinDays.set(key, (proteinDays.get(key) ?? 0) + m.proteinG);
  }
  const proteinShares: number[] = [];
  let proteinGrams = 0;
  for (const [key, grams] of proteinDays) {
    proteinGrams += grams;
    const target = targets.get(key.split('|')[0]!)?.proteinTargetG;
    if (target && target > 0) proteinShares.push(grams / target);
  }
  const avg = (xs: number[]) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null);

  return {
    calories: {
      avgShareOfTarget: avg(shares),
      daysWithFood: shares.length,
      missedDays: missed,
      daily: [...byDate]
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([date, xs]) => ({ date, avgShareOfTarget: avg(xs), people: xs.length })),
    },
    protein: {
      avgShareOfTarget: avg(proteinShares),
      avgGramsPerDay: proteinDays.size ? round(proteinGrams / proteinDays.size) : null,
      personDays: proteinDays.size,
    },
  };
}

/** Weight change per week for each person with two weigh-ins at least 3 days apart. */
export function weightTrends(rows: WeightRow[], goals: Map<string, string>) {
  const byUser = new Map<string, WeightRow[]>();
  for (const r of rows) byUser.set(r.userId, [...(byUser.get(r.userId) ?? []), r]);
  const people: { userId: string; goal: string | null; kgPerWeek: number; fromKg: number; toKg: number }[] = [];
  for (const [userId, entries] of byUser) {
    const sorted = [...entries].sort((a, b) => a.measuredAt.getTime() - b.measuredAt.getTime());
    const first = sorted[0]!;
    const last = sorted[sorted.length - 1]!;
    const days = (last.measuredAt.getTime() - first.measuredAt.getTime()) / 86_400_000;
    if (sorted.length < 2 || days < 3) continue;
    people.push({
      userId,
      goal: goals.get(userId) ?? null,
      kgPerWeek: round((last.weightKg - first.weightKg) / (days / 7), 2),
      fromKg: first.weightKg,
      toKg: last.weightKg,
    });
  }
  const avgOf = (xs: number[]) => (xs.length ? round(xs.reduce((a, b) => a + b, 0) / xs.length, 2) : null);
  const byGoal: Record<string, { people: number; avgKgPerWeek: number | null }> = {};
  for (const goal of new Set(people.map((p) => p.goal ?? 'UNKNOWN'))) {
    const xs = people.filter((p) => (p.goal ?? 'UNKNOWN') === goal).map((p) => p.kgPerWeek);
    byGoal[goal] = { people: xs.length, avgKgPerWeek: avgOf(xs) };
  }
  return { people: people.length, avgKgPerWeek: avgOf(people.map((p) => p.kgPerWeek)), byGoal };
}
