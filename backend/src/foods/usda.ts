/**
 * Maps a USDA FoodData Central JSON dump (Foundation Foods or SR Legacy) into
 * catalog rows: name, default serving, per-100g macros. Pure — the import
 * script downloads and writes; tests feed fixtures.
 *
 * Nutrient ids: https://fdc.nal.usda.gov/api-guide
 * Energy kcal 1008 / 2047 / 2048; protein 1003; carb 1005; fat 1004.
 */

export type CatalogFoodWrite = {
  fdcId: number;
  name: string;
  category: string | null;
  servingG: number | null;
  servingDesc: string | null;
  kcal100g: number;
  proteinG100g: number;
  carbsG100g: number;
  fatG100g: number;
  dataType: 'foundation' | 'sr_legacy';
};

type Nutrient = {
  amount?: number;
  value?: number;
  nutrientId?: number;
  nutrient?: {
    id?: number;
    number?: string;
    name?: string;
    unitName?: string;
  };
};

type Portion = {
  gramWeight?: number;
  amount?: number;
  modifier?: string;
  portionDescription?: string;
  measureUnit?: { name?: string; abbreviation?: string };
};

type UsdaFood = {
  fdcId?: number;
  description?: string;
  dataType?: string;
  foodCategory?: string | { description?: string };
  foodNutrients?: Nutrient[];
  foodPortions?: Portion[];
};

const ENERGY_KCAL_IDS = new Set([1008, 2047, 2048]);
const ENERGY_KJ_IDS = new Set([1062]);
const PROTEIN_IDS = new Set([1003]);
const CARB_IDS = new Set([1005]);
const FAT_IDS = new Set([1004]);

const round1 = (n: number): number => Math.round(n * 10) / 10;

export function foodsFromUsdaDump(payload: unknown): CatalogFoodWrite[] {
  const foods = dumpFoods(payload);
  const out: CatalogFoodWrite[] = [];
  for (const food of foods) {
    const mapped = mapUsdaFood(food);
    if (mapped) out.push(mapped);
  }
  return out;
}

export function mapUsdaFood(food: UsdaFood): CatalogFoodWrite | null {
  const fdcId = food.fdcId;
  const name = food.description?.trim();
  if (!fdcId || !name) return null;
  const nutrients = food.foodNutrients ?? [];
  const kcal100g = energyKcal(nutrients);
  if (kcal100g == null || kcal100g <= 0) return null;
  const dataType = dataTypeOf(food.dataType);
  if (!dataType) return null;
  const serving = defaultServing(food.foodPortions ?? []);
  return {
    fdcId,
    name: name.slice(0, 200),
    category: categoryOf(food.foodCategory),
    servingG: serving.grams,
    servingDesc: serving.desc,
    kcal100g: Math.round(kcal100g),
    proteinG100g: round1(nutrientAmount(nutrients, PROTEIN_IDS) ?? 0),
    carbsG100g: round1(nutrientAmount(nutrients, CARB_IDS) ?? 0),
    fatG100g: round1(nutrientAmount(nutrients, FAT_IDS) ?? 0),
    dataType,
  };
}

function dumpFoods(payload: unknown): UsdaFood[] {
  if (!payload || typeof payload !== 'object') return [];
  const rec = payload as Record<string, unknown>;
  if (Array.isArray(rec.FoundationFoods)) return rec.FoundationFoods as UsdaFood[];
  if (Array.isArray(rec.SRLegacyFoods)) return rec.SRLegacyFoods as UsdaFood[];
  if (Array.isArray(payload)) return payload as UsdaFood[];
  return [];
}

function dataTypeOf(raw: string | undefined): CatalogFoodWrite['dataType'] | null {
  const t = (raw ?? '').toLowerCase();
  if (t.includes('foundation')) return 'foundation';
  if (t.includes('sr') || t.includes('legacy')) return 'sr_legacy';
  return null;
}

function categoryOf(raw: UsdaFood['foodCategory']): string | null {
  if (!raw) return null;
  if (typeof raw === 'string') return raw.trim().slice(0, 80) || null;
  return raw.description?.trim().slice(0, 80) || null;
}

function energyKcal(nutrients: Nutrient[]): number | null {
  const kcal = nutrientAmount(nutrients, ENERGY_KCAL_IDS, 'kcal');
  if (kcal != null && kcal > 0) return kcal;
  const labeled = nutrients.find((n) => unitOf(n) === 'kcal' && num(amountOf(n)) != null);
  const labeledAmt = labeled ? num(amountOf(labeled)) : null;
  if (labeledAmt != null && labeledAmt > 0) return labeledAmt;
  const kj = nutrientAmount(nutrients, ENERGY_KJ_IDS, 'kj') ?? nutrientAmount(nutrients, ENERGY_KJ_IDS);
  if (kj != null && kj > 0) return kj / 4.184;
  return null;
}

function nutrientAmount(nutrients: Nutrient[], ids: Set<number>, unit?: string): number | null {
  for (const n of nutrients) {
    if (!ids.has(idOf(n))) continue;
    if (unit && unitOf(n) && unitOf(n) !== unit) continue;
    const value = num(amountOf(n));
    if (value != null) return value;
  }
  return null;
}

function defaultServing(portions: Portion[]): { grams: number | null; desc: string | null } {
  const usable = portions
    .map((p) => ({ grams: num(p.gramWeight), desc: portionLabel(p) }))
    .filter((p): p is { grams: number; desc: string | null } => p.grams != null && p.grams >= 20 && p.grams <= 400);
  const pick = usable[0];
  if (!pick) return { grams: 100, desc: '100 g' };
  return { grams: round1(pick.grams), desc: pick.desc ?? `${Math.round(pick.grams)} g` };
}

function portionLabel(p: Portion): string | null {
  const described = p.portionDescription?.trim();
  if (described) return described.slice(0, 80);
  const unit = p.measureUnit?.name?.trim() || p.measureUnit?.abbreviation?.trim();
  const amount = num(p.amount);
  if (unit && amount != null) {
    const bit = `${trimNum(amount)} ${unit}`;
    return p.modifier ? `${bit} ${p.modifier}`.slice(0, 80) : bit.slice(0, 80);
  }
  const grams = num(p.gramWeight);
  return grams != null ? `${Math.round(grams)} g` : null;
}

function idOf(n: Nutrient): number {
  return n.nutrient?.id ?? n.nutrientId ?? 0;
}

function amountOf(n: Nutrient): unknown {
  return n.amount ?? n.value;
}

function unitOf(n: Nutrient): string {
  return (n.nutrient?.unitName ?? '').trim().toLowerCase();
}

function num(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() !== '') {
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

function trimNum(n: number): string {
  return n === Math.round(n) ? String(n) : String(round1(n));
}
