import { DRINKABLE_SLUGS } from '../engine/appetite.js';
import { shiftDateISO, weekdayOfLocalDate } from '../engine/time.js';

export type AppetiteLevel = 'HUNGRY' | 'NORMAL' | 'LOW';

export type AppetiteHistoryDay = {
  date: string;
  level: AppetiteLevel | null;
};

export type AppetitePattern =
  | {
      id: 'late_dinner';
      title: string;
      body: string;
      action: { label: string; dinnerMin: number } | null;
      count: number;
      total: number;
    }
  | {
      id: 'after_training';
      title: string;
      body: string;
      action: null;
      count: number;
      total: number;
    };

export type LowDayFood = {
  name: string;
  tag: 'Drinkable' | 'No prep' | 'Dense';
  eaten: number;
  offered: number;
};

export type AppetiteHistory = {
  days: AppetiteHistoryDay[];
  percentEatenNormal: number;
  percentEatenLow: number;
  percentEatenLowBefore: number | null;
  patterns: AppetitePattern[];
  lowDayFoods: LowDayFood[];
};

export type AppetiteHistoryInput = {
  todayISO: string;
  targetKcal: number;
  /** Date → answered level. */
  levels: Record<string, AppetiteLevel>;
  /** Date → kcal consumed. */
  consumedByDate: Record<string, number>;
  /** Date → last meal minute-from-midnight. */
  lastMealMinByDate: Record<string, number>;
  /** Local dates that had a workout. */
  workoutDates: string[];
  /** Prescriptions offered on LOW days. */
  lowDayPrescriptions: {
    date: string;
    accepted: boolean;
    items: { name: string; slug: string | null; tags: string[] }[];
  }[];
};

const LATE_DINNER_MIN = 21 * 60;
const HISTORY_DAYS = 28;

/** Monday on or before `iso` (Mon=start of week). */
export function mondayOnOrBefore(iso: string): string {
  const dow = weekdayOfLocalDate(iso); // 0 = Sun
  const sinceMon = dow === 0 ? 6 : dow - 1;
  return shiftDateISO(iso, -sinceMon);
}

/** Four Mon–Sun weeks ending with the week that contains today. */
export function historyWindow(todayISO: string): string[] {
  const thisMonday = mondayOnOrBefore(todayISO);
  const start = shiftDateISO(thisMonday, -21);
  return Array.from({ length: HISTORY_DAYS }, (_, i) => shiftDateISO(start, i));
}

function avgPercent(ratios: number[], targetKcal: number): number {
  if (ratios.length === 0 || targetKcal <= 0) return 0;
  const sum = ratios.reduce((a, c) => a + Math.min(1, c / targetKcal), 0);
  return Math.round((sum / ratios.length) * 100);
}

export function foodTag(item: { slug: string | null; tags: string[] }): LowDayFood['tag'] {
  if (item.slug && DRINKABLE_SLUGS.has(item.slug)) return 'Drinkable';
  if (item.tags.includes('no_cook')) return 'No prep';
  return 'Dense';
}

/** Pure builder — fed by the route from Prisma rows. */
export function buildAppetiteHistory(input: AppetiteHistoryInput): AppetiteHistory {
  const dates = historyWindow(input.todayISO);
  const workoutSet = new Set(input.workoutDates);

  const days: AppetiteHistoryDay[] = dates.map((date) => ({
    date,
    level: date > input.todayISO ? null : (input.levels[date] ?? null),
  }));

  const consumedOn = (date: string) => input.consumedByDate[date] ?? 0;

  const normalDates = days.filter((d) => d.level === 'NORMAL' || d.level === 'HUNGRY').map((d) => d.date);
  const lowDates = days.filter((d) => d.level === 'LOW').map((d) => d.date);

  const percentEatenNormal = avgPercent(
    normalDates.map(consumedOn),
    input.targetKcal,
  );
  const percentEatenLow = avgPercent(lowDates.map(consumedOn), input.targetKcal);

  const firstSmall = Object.entries(input.levels)
    .filter(([, level]) => level === 'LOW')
    .map(([date]) => date)
    .sort()[0] ?? null;
  let percentEatenLowBefore: number | null = null;
  if (firstSmall) {
    const before = [
      ...new Set([...Object.keys(input.consumedByDate), ...Object.keys(input.levels)]),
    ].filter((d) => d < firstSmall && consumedOn(d) > 0);
    const priorLowish = before.filter((d) => consumedOn(d) < input.targetKcal * 0.85);
    const sample = priorLowish.length > 0 ? priorLowish : before;
    if (sample.length > 0) {
      percentEatenLowBefore = avgPercent(sample.map(consumedOn), input.targetKcal);
    }
  }

  const patterns: AppetitePattern[] = [];

  if (lowDates.length >= 3) {
    let lateCount = 0;
    for (const date of lowDates) {
      const prev = shiftDateISO(date, -1);
      const lastMin = input.lastMealMinByDate[prev];
      if (lastMin != null && lastMin > LATE_DINNER_MIN) lateCount += 1;
    }
    if (lateCount / lowDates.length >= 0.6) {
      patterns.push({
        id: 'late_dinner',
        title: 'Late dinners → low mornings',
        body: `${lateCount} of your ${lowDates.length} low days came after dinner past 21:00.`,
        action: { label: 'Move dinner to 20:00', dinnerMin: 1200 },
        count: lateCount,
        total: lowDates.length,
      });
    }
  }

  const hungryDates = days.filter((d) => d.level === 'HUNGRY').map((d) => d.date);
  if (hungryDates.length >= 3) {
    let afterTraining = 0;
    for (const date of hungryDates) {
      if (workoutSet.has(shiftDateISO(date, -1))) afterTraining += 1;
    }
    if (afterTraining / hungryDates.length >= 0.6) {
      patterns.push({
        id: 'after_training',
        title: 'Hungrier after training',
        body: `${afterTraining} of ${hungryDates.length} hungry days were the day after a workout. I already add the calories.`,
        action: null,
        count: afterTraining,
        total: hungryDates.length,
      });
    }
  }

  const foodStats = new Map<string, { tag: LowDayFood['tag']; eaten: number; offered: number }>();
  for (const rx of input.lowDayPrescriptions) {
    if (!lowDates.includes(rx.date) && !input.levels[rx.date]) {
      // Still count if the prescription's day was LOW even outside the Mon-aligned window edge cases
    }
    const onLow = input.levels[rx.date] === 'LOW';
    if (!onLow) continue;
    for (const item of rx.items) {
      const cur = foodStats.get(item.name) ?? { tag: foodTag(item), eaten: 0, offered: 0 };
      cur.offered += 1;
      if (rx.accepted) cur.eaten += 1;
      foodStats.set(item.name, cur);
    }
  }

  const lowDayFoods = [...foodStats.entries()]
    .map(([name, s]) => ({ name, tag: s.tag, eaten: s.eaten, offered: s.offered }))
    .sort((a, b) => {
      const ra = a.offered === 0 ? 0 : a.eaten / a.offered;
      const rb = b.offered === 0 ? 0 : b.eaten / b.offered;
      if (rb !== ra) return rb - ra;
      return b.offered - a.offered;
    })
    .slice(0, 3);

  return {
    days,
    percentEatenNormal,
    percentEatenLow,
    percentEatenLowBefore,
    patterns,
    lowDayFoods,
  };
}
