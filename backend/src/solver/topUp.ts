import type { Lang } from '../i18n/index.js';
import { filterAllowedFoods } from './exclusions.js';
import type { PrescriptionLineItem, PrescriptionResult, SolverFood } from './types.js';

/**
 * What the meal the user just ate looked like, read from its text: a bowl
 * (oats, yogurt), something on bread, or a cooked plate. Decides what an
 * add-on can go into — oil belongs on rice, peanut butter in oats.
 */
export type MealShape = 'bowl' | 'bread' | 'plate';
/** Where an add-on goes: into the meal's shape, or next to anything. */
export type AddOnUse = MealShape | 'side';

type AddOn = {
  slug: string;
  /** Most servings that still reads like a normal amount. */
  maxQty: number;
  goesWith: AddOnUse[];
  /** Two from the same group (almonds + cashews) is one idea twice. */
  group: 'milk' | 'nuts' | 'spread' | 'fat' | 'fruit' | 'cereal' | 'cheese';
};

/**
 * Add-ons: small, calorie-dense things you add to a meal you're already eating
 * or drink on the side — the "same bite, more calories" lever for people who
 * can't face a second plate.
 */
export const ADD_ONS: AddOn[] = [
  { slug: 'whole-milk', maxQty: 2, goesWith: ['side'], group: 'milk' },
  { slug: 'chocolate-milk', maxQty: 2, goesWith: ['side'], group: 'milk' },
  { slug: 'kefir', maxQty: 2, goesWith: ['side', 'bowl'], group: 'milk' },
  { slug: 'ready-protein-shake', maxQty: 1, goesWith: ['side'], group: 'milk' },
  { slug: 'peanut-butter', maxQty: 1, goesWith: ['bowl', 'bread'], group: 'spread' },
  { slug: 'almond-butter', maxQty: 1, goesWith: ['bowl', 'bread'], group: 'spread' },
  { slug: 'tahini', maxQty: 1, goesWith: ['plate', 'bread'], group: 'spread' },
  { slug: 'granola', maxQty: 1, goesWith: ['bowl'], group: 'cereal' },
  { slug: 'medjool-dates', maxQty: 1, goesWith: ['side', 'bowl'], group: 'fruit' },
  { slug: 'avocado', maxQty: 1, goesWith: ['plate', 'bread'], group: 'fruit' },
  { slug: 'almonds', maxQty: 2, goesWith: ['side', 'bowl'], group: 'nuts' },
  { slug: 'cashews', maxQty: 2, goesWith: ['side'], group: 'nuts' },
  { slug: 'trail-mix', maxQty: 1, goesWith: ['side'], group: 'nuts' },
  { slug: 'olive-oil', maxQty: 2, goesWith: ['plate'], group: 'fat' },
  { slug: 'butter', maxQty: 1, goesWith: ['plate', 'bread'], group: 'fat' },
  { slug: 'cheddar-cheese', maxQty: 2, goesWith: ['plate', 'bread'], group: 'cheese' },
];

export const ADD_ON_SLUGS = ADD_ONS.map((a) => a.slug);

/** One line on how to actually get it down, per add-on and where it goes. */
const HOW: Record<string, Partial<Record<AddOnUse, { en: string; he: string }>>> = {
  'whole-milk': { side: { en: 'A glass with the meal', he: 'כוס לצד הארוחה' } },
  'chocolate-milk': { side: { en: 'Drink it with the meal or right after', he: 'לשתות עם הארוחה או מיד אחריה' } },
  kefir: {
    side: { en: 'Drink it on the side', he: 'לשתות לצד הארוחה' },
    bowl: { en: 'Pour it over your bowl', he: 'לשפוך על הקערה' },
  },
  'ready-protein-shake': { side: { en: 'Sip it with the meal', he: 'ללגום עם הארוחה' } },
  'peanut-butter': {
    bowl: { en: 'Stir it into your bowl', he: 'לערבב לתוך הקערה' },
    bread: { en: 'Spread it on your bread', he: 'למרוח על הלחם' },
  },
  'almond-butter': {
    bowl: { en: 'Stir it into your bowl', he: 'לערבב לתוך הקערה' },
    bread: { en: 'Spread it on your bread', he: 'למרוח על הלחם' },
  },
  tahini: {
    plate: { en: 'Pour it over your plate', he: 'לשפוך על הצלחת' },
    bread: { en: 'Spread it on your bread', he: 'למרוח על הלחם' },
  },
  granola: { bowl: { en: 'Pour it on top', he: 'לפזר מעל' } },
  'medjool-dates': {
    side: { en: 'Eat them after the meal', he: 'לאכול אחרי הארוחה' },
    bowl: { en: 'Chop them into your bowl', he: 'לקצוץ לתוך הקערה' },
  },
  avocado: {
    plate: { en: 'Slice it onto your plate', he: 'לפרוס לצלחת' },
    bread: { en: 'Mash it onto your bread', he: 'למעוך על הלחם' },
  },
  almonds: {
    side: { en: 'A handful after the meal', he: 'חופן אחרי הארוחה' },
    bowl: { en: 'Scatter them on top', he: 'לפזר מעל' },
  },
  cashews: { side: { en: 'A handful after the meal', he: 'חופן אחרי הארוחה' } },
  'trail-mix': { side: { en: 'A handful after the meal', he: 'חופן אחרי הארוחה' } },
  'olive-oil': { plate: { en: 'Drizzle it over your plate', he: 'לזלף על הצלחת' } },
  butter: {
    plate: { en: 'Melt it into the rice, pasta or potatoes', he: 'להמיס לתוך האורז, הפסטה או תפוחי האדמה' },
    bread: { en: 'Spread it on your bread', he: 'למרוח על הלחם' },
  },
  'cheddar-cheese': {
    plate: { en: 'Grate or melt it over your plate', he: 'לגרר או להמיס מעל הצלחת' },
    bread: { en: 'Add it to your bread', he: 'להוסיף ללחם' },
  },
};

export function topUpHow(slug: string, use: AddOnUse, lang: Lang = 'en'): string {
  const line = HOW[slug]?.[use] ?? HOW[slug]?.side;
  return line ? line[lang] : '';
}

const SHAPE_WORDS: Record<MealShape, RegExp> = {
  bowl: /oat|porridge|yog(h)?urt|cereal|muesli|granola|smoothie|acai|chia|skyr|שיבולת|דייסה|יוגורט|קורנפלקס|דגני|גרנולה|סמוד/i,
  bread: /toast|sandwich|bread|bagel|wrap|pita|roll\b|burger|croissant|tortilla|טוסט|כריך|סנדוויץ|לחם|פיתה|בייגל|לאפה|טורטי|המבורגר/i,
  plate: /rice|pasta|noodle|spaghetti|chicken|beef|steak|fish|salmon|tuna|salad|potato|quinoa|couscous|lentil|beans|curry|stir.?fry|shakshuka|schnitzel|אורז|פסטה|עוף|בשר|דג|סלמון|טונה|סלט|תפוח.? אדמה|קינואה|קוסקוס|עדשים|שקשוקה|שניצל|פתיתים/i,
};

/** The meal's shape from what was logged, or null when the text doesn't say. */
export function mealShapeOf(text: string): MealShape | null {
  let best: MealShape | null = null;
  let bestHits = 0;
  // Ties go to bread: a "chicken sandwich" is eaten as a sandwich.
  for (const shape of ['bread', 'plate', 'bowl'] as MealShape[]) {
    const hits = (text.match(new RegExp(SHAPE_WORDS[shape].source, 'gi')) ?? []).length;
    if (hits > bestHits) {
      best = shape;
      bestHits = hits;
    }
  }
  return best;
}

export const TOP_UP_CONFIG = {
  /** A top-up that lands below this share of the ask isn't worth showing. */
  minShare: 0.5,
  /** Penalty (kcal-equivalent) for a second item — one thing is easier. */
  secondItemPenalty: 60,
  /** Bonus (kcal-equivalent) for a drink when drinks are welcome. */
  drinkBonus: 30,
  /** Bonus (kcal-equivalent) for going into the meal: it's the same bite. */
  intoMealBonus: 55,
  /** Bonus (kcal-equivalent) per gram of protein, up to what the day is short. */
  proteinBonusPerG: 4,
  /** Penalty for an add-on the user topped up with in the last few days. */
  recentPenalty: 90,
  /** Most of the day-to-day shuffle (kcal-equivalent) so it doesn't repeat. */
  jitter: 60,
  /** Alternatives the card can swap to. */
  maxOptions: 3,
} as const;

export type TopUpItem = PrescriptionLineItem & { use: AddOnUse };
export type TopUpOption = Omit<PrescriptionResult, 'items'> & { items: TopUpItem[] };

type Option = { addOn: AddOn; food: SolverFood; qty: number; kcal: number; use: AddOnUse };

const round1 = (n: number): number => Math.round(n * 10) / 10;

/** Stable 0..1 from a string — same seed, same shuffle. */
function hash01(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i += 1) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return (h >>> 0) / 4294967295;
}

/**
 * Up to three distinct ways to close `targetKcal` with one or two add-ons,
 * best first, never breaking a restriction. Each fits the meal just eaten
 * (`shape`; null = only things eaten or drunk on the side), leans to protein
 * when the day is short on it, and avoids what was topped up with lately.
 * `seed` (user + day + slot) shuffles near-ties so it isn't the same every
 * day; without one it's fully deterministic.
 */
export function pickTopUps(
  foods: SolverFood[],
  input: {
    targetKcal: number;
    excludedTokens: string[];
    drinkableOk?: boolean;
    shape?: MealShape | null;
    /** Text of what was just eaten — an add-on already in it isn't suggested. */
    mealText?: string;
    proteinShortG?: number;
    recentSlugs?: string[];
    seed?: string;
  },
): TopUpOption[] {
  if (input.targetKcal <= 0) return [];
  const bySlug = new Map(ADD_ONS.map((a) => [a.slug, a]));
  const allowed = filterAllowedFoods(
    foods.filter((f) => bySlug.has(f.slug)),
    input.excludedTokens,
  );
  const mealText = (input.mealText ?? '').toLowerCase();
  const recent = new Set(input.recentSlugs ?? []);
  const drinkOk = input.drinkableOk ?? true;
  const proteinShort = Math.max(0, input.proteinShortG ?? 0);

  const options: Option[] = [];
  for (const food of allowed) {
    const addOn = bySlug.get(food.slug)!;
    if (mealText && mealText.includes(food.name.toLowerCase())) continue;
    const use: AddOnUse | undefined =
      input.shape && addOn.goesWith.includes(input.shape) ? input.shape : addOn.goesWith.includes('side') ? 'side' : undefined;
    if (!use) continue;
    if (use === 'side' && addOn.group === 'milk' && !drinkOk) continue;
    for (let qty = 1; qty <= addOn.maxQty; qty += 1) {
      options.push({ addOn, food, qty, kcal: food.kcal * qty, use });
    }
  }

  const itemScore = (o: Option): number => {
    const protein = Math.min(o.food.proteinG * o.qty, proteinShort) * TOP_UP_CONFIG.proteinBonusPerG;
    const drink = drinkOk && o.addOn.group === 'milk' ? TOP_UP_CONFIG.drinkBonus : 0;
    const fits = o.use !== 'side' ? TOP_UP_CONFIG.intoMealBonus : 0;
    const stale = recent.has(o.food.slug) ? TOP_UP_CONFIG.recentPenalty : 0;
    const shuffle = input.seed ? hash01(`${input.seed}:${o.food.slug}`) * TOP_UP_CONFIG.jitter : ADD_ON_SLUGS.indexOf(o.food.slug);
    return protein + drink + fits - stale - shuffle;
  };
  const cost = (combo: Option[]): number => {
    const kcal = combo.reduce((a, o) => a + o.kcal, 0);
    // Undershooting is worse than a little over: the point is eating enough.
    const miss = kcal >= input.targetKcal ? kcal - input.targetKcal : (input.targetKcal - kcal) * 1.5;
    const extra = combo.length > 1 ? TOP_UP_CONFIG.secondItemPenalty : 0;
    return miss + extra - combo.reduce((a, o) => a + itemScore(o), 0);
  };

  const combos: { combo: Option[]; cost: number }[] = [];
  for (let i = 0; i < options.length; i += 1) {
    const a = options[i]!;
    combos.push({ combo: [a], cost: cost([a]) });
    for (let j = i + 1; j < options.length; j += 1) {
      const b = options[j]!;
      if (b.addOn.group === a.addOn.group) continue;
      combos.push({ combo: [a, b], cost: cost([a, b]) });
    }
  }
  combos.sort((x, y) => x.cost - y.cost);

  const picked: TopUpOption[] = [];
  const used = new Set<string>();
  for (const { combo } of combos) {
    if (picked.length >= TOP_UP_CONFIG.maxOptions) break;
    if (combo.some((o) => used.has(o.food.slug))) continue;
    const kcal = combo.reduce((a, o) => a + o.kcal, 0);
    if (kcal < input.targetKcal * TOP_UP_CONFIG.minShare) continue;
    for (const o of combo) used.add(o.food.slug);
    picked.push(toOption(combo, input.targetKcal));
  }
  return picked;
}

function toOption(combo: Option[], targetKcal: number): TopUpOption {
  // What goes into the meal reads first; the drink or handful after it.
  const items: TopUpItem[] = [...combo]
    .sort((a, b) => Number(a.use === 'side') - Number(b.use === 'side'))
    .map((o) => ({
      slug: o.food.slug,
      name: o.food.name,
      servingDesc: o.food.servingDesc,
      quantity: o.qty,
      unit: 'serving',
      kcal: Math.round(o.kcal),
      proteinG: round1(o.food.proteinG * o.qty),
      carbsG: round1(o.food.carbsG * o.qty),
      fatG: round1(o.food.fatG * o.qty),
      use: o.use,
    }));
  return {
    items,
    totalKcal: items.reduce((a, i) => a + i.kcal, 0),
    totalProteinG: round1(items.reduce((a, i) => a + i.proteinG, 0)),
    totalCarbsG: round1(items.reduce((a, i) => a + i.carbsG, 0)),
    totalFatG: round1(items.reduce((a, i) => a + i.fatG, 0)),
    targetKcal,
    targetProteinG: null,
  };
}

/** The best single top-up, or null when no add-on fits. */
export function pickTopUp(
  foods: SolverFood[],
  input: Parameters<typeof pickTopUps>[1],
): TopUpOption | null {
  return pickTopUps(foods, input)[0] ?? null;
}

/**
 * Add-ons named in recent top-up logs ("Top-up: Whole milk + …"), so the next
 * suggestion can be something else.
 */
export function addOnsInText(texts: string[], foods: SolverFood[], heNames: (name: string) => string): string[] {
  const out = new Set<string>();
  const lower = texts.map((t) => t.toLowerCase());
  for (const food of foods) {
    if (!ADD_ON_SLUGS.includes(food.slug)) continue;
    const en = food.name.toLowerCase();
    const he = heNames(food.name);
    if (lower.some((t) => t.includes(en) || t.includes(he))) out.add(food.slug);
  }
  return [...out];
}
