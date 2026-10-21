import { mealItemsSchema } from '../meals/items.js';
import { namedSummary, prescribe } from '../solver/prescribe.js';
import type { SolverFood } from '../solver/types.js';

export const SNACK_BEFORE_MIN_KCAL = 150;
export const SNACK_BEFORE_MAX_KCAL = 400;
export const SNACK_BEFORE_TARGET_KCAL = 250;
export const SNACK_BEFORE_PROTEIN_G = 18;
export const SNACK_BEFORE_LOOKBACK_MIN = 90;

export type SnackItem = {
  name: string;
  quantity: string;
  kcal: number;
  proteinG: number;
};

export type SnackBefore = {
  name: string;
  kcal: number;
  source: 'usual' | 'history' | 'suggested';
  proteinG?: number;
  items?: SnackItem[];
};

export type SnackHistoryMeal = {
  loggedAt: Date;
  kcal: number;
  rawInput?: string | null;
  items?: unknown;
};

export type SnackSavedMeal = {
  name: string;
  kcal: number;
  items?: unknown;
  useCount: number;
  lastUsedAt: Date | null;
  useInCheckIns: boolean;
};

type Candidate = SnackBefore & { score: number };

/** A snack for the 90 minutes before a session: what they already eat, then a light staple that fits. */
export function pickSnackBefore(input: {
  meals: SnackHistoryMeal[];
  workouts: { start: Date }[];
  savedMeals: SnackSavedMeal[];
  dislikedFoods?: string[];
  excludedTokens?: string[];
  pantryTokens?: string[];
  solverFoods?: SolverFood[];
  drinkableOk?: boolean;
}): SnackBefore | null {
  const blocked = [...(input.dislikedFoods ?? []), ...(input.excludedTokens ?? [])];
  const pantry = input.pantryTokens ?? [];
  const candidates: Candidate[] = [];

  const repeats = new Map<string, number>();
  for (const meal of input.meals) {
    const key = normalizeName(mealName(meal));
    if (!key) continue;
    repeats.set(key, (repeats.get(key) ?? 0) + 1);
  }

  for (const meal of input.meals) {
    const picked = fromMeal(meal, blocked);
    if (!picked) continue;
    const beforeSession = input.workouts.some((workout) => {
      const at = meal.loggedAt.getTime();
      const from = workout.start.getTime() - SNACK_BEFORE_LOOKBACK_MIN * 60_000;
      return at >= from && at <= workout.start.getTime();
    });
    const hour = meal.loggedAt.getHours();
    candidates.push({
      ...picked,
      source: 'history',
      score: score(picked, {
        pantry,
        beforeSession,
        afternoon: hour >= 14 && hour <= 18,
        repeats: repeats.get(normalizeName(picked.name)) ?? 1,
        hasItems: (picked.items?.length ?? 0) > 0,
      }),
    });
  }

  for (const saved of input.savedMeals) {
    const picked = fromSaved(saved, blocked);
    if (!picked) continue;
    candidates.push({
      ...picked,
      source: 'usual',
      score: score(picked, {
        pantry,
        usual: true,
        useCount: saved.useCount,
        checkInPlate: saved.useInCheckIns,
        recent: saved.lastUsedAt != null,
      }),
    });
  }

  candidates.sort((a, b) => b.score - a.score || a.name.localeCompare(b.name));
  if (candidates[0]) {
    const { score: _score, ...snack } = candidates[0];
    return snack;
  }

  if (!input.solverFoods?.length) return null;
  const rx = prescribe(input.solverFoods, {
    targetKcal: SNACK_BEFORE_TARGET_KCAL,
    targetProteinG: SNACK_BEFORE_PROTEIN_G,
    excludedTokens: input.excludedTokens ?? [],
    pantryTokens: pantry,
    preferLowFriction: true,
    preferDrinkable: input.drinkableOk ?? true,
  });
  if (!rx || rx.items.length === 0) return null;
  return { name: namedSummary(rx), kcal: rx.totalKcal, source: 'suggested' };
}

function isSnackSize(kcal: number): boolean {
  return kcal >= SNACK_BEFORE_MIN_KCAL && kcal <= SNACK_BEFORE_MAX_KCAL;
}

function plateItems(raw: unknown): SnackItem[] {
  return mealItemsSchema.catch([]).parse(raw).map((item) => ({
    name: item.name,
    quantity: item.quantity,
    kcal: item.kcal,
    proteinG: item.proteinG,
  }));
}

function fromMeal(meal: SnackHistoryMeal, blocked: string[]): SnackBefore | null {
  if (!isSnackSize(meal.kcal)) return null;
  const name = mealName(meal);
  if (!name || isBlocked(name, blocked)) return null;
  const items = plateItems(meal.items);
  const proteinG = items.reduce((sum, item) => sum + item.proteinG, 0);
  return { name, kcal: meal.kcal, source: 'history', proteinG, items: items.length > 0 ? items : undefined };
}

function fromSaved(meal: SnackSavedMeal, blocked: string[]): SnackBefore | null {
  if (!isSnackSize(meal.kcal)) return null;
  const name = meal.name.trim() || mealName({ loggedAt: new Date(0), kcal: meal.kcal, items: meal.items });
  if (!name || isBlocked(name, blocked)) return null;
  const items = plateItems(meal.items);
  const proteinG = items.reduce((sum, item) => sum + item.proteinG, 0);
  return { name, kcal: meal.kcal, source: 'usual', proteinG, items: items.length > 0 ? items : undefined };
}

export function mealName(meal: Pick<SnackHistoryMeal, 'rawInput' | 'items'>): string {
  const items = mealItemsSchema.catch([]).parse(meal.items);
  if (items.length === 1) return items[0]!.name;
  if (items.length > 1) return items.slice(0, 2).map((i) => i.name).join(' + ');
  return meal.rawInput?.trim() || '';
}

function isBlocked(name: string, tokens: string[]): boolean {
  const n = name.toLowerCase();
  return tokens.some((raw) => {
    const token = raw.trim().toLowerCase().replace(/[_-]+/g, ' ');
    return token.length >= 2 && n.includes(token);
  });
}

function normalizeName(name: string): string {
  return name.trim().toLowerCase().replace(/\s+/g, ' ');
}

function score(
  snack: SnackBefore,
  extras: {
    pantry: string[];
    beforeSession?: boolean;
    afternoon?: boolean;
    repeats?: number;
    hasItems?: boolean;
    usual?: boolean;
    useCount?: number;
    checkInPlate?: boolean;
    recent?: boolean;
  },
): number {
  const kcalFit = 1 - Math.min(1, Math.abs(snack.kcal - SNACK_BEFORE_TARGET_KCAL) / 200);
  let value = 4 * kcalFit;
  if (extras.beforeSession) value += 32;
  if (extras.afternoon) value += 10;
  if (extras.hasItems) value += 6;
  if (extras.repeats) value += 6 + extras.repeats;
  if (extras.usual) value += 6;
  if (extras.useCount) value += Math.min(8, extras.useCount);
  if (extras.checkInPlate) value += 4;
  if (extras.recent) value += 2;
  if (extras.pantry.some((t) => snack.name.toLowerCase().includes(t.replace(/[_-]+/g, ' ')))) value += 5;
  return value;
}
