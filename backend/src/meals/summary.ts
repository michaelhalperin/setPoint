const round1 = (n: number): number => Math.round(n * 10) / 10;

export type MealItem = {
  name: string;
  quantity: string;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
};

export type MealSummary = {
  id: string;
  loggedAt: string;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  source: string;
  summary: string | null;
  photoUrl: string | null;
  notes: string | null;
  items: MealItem[];
  parseConfidence: number | null;
};

export type MealSummaryRow = {
  id: string;
  loggedAt: Date;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  source: string;
  rawInput: string | null;
  photoUrl: string | null;
  notes?: string | null;
  items?: unknown;
  parseConfidence?: number | null;
};

export function toMealSummary(row: MealSummaryRow): MealSummary {
  return {
    id: row.id,
    loggedAt: row.loggedAt.toISOString(),
    kcal: row.kcal,
    proteinG: round1(row.proteinG),
    carbsG: round1(row.carbsG),
    fatG: round1(row.fatG),
    source: row.source,
    summary: row.rawInput,
    photoUrl: row.photoUrl ?? null,
    notes: row.notes ?? null,
    items: asItems(row.items),
    parseConfidence: row.parseConfidence ?? null,
  };
}

function asItems(value: unknown): MealItem[] {
  if (!Array.isArray(value)) return [];
  const items: MealItem[] = [];
  for (const raw of value) {
    if (!raw || typeof raw !== 'object') continue;
    const o = raw as Record<string, unknown>;
    if (typeof o.name !== 'string' || o.name.trim() === '') continue;
    items.push({
      name: o.name,
      quantity: typeof o.quantity === 'string' ? o.quantity : '',
      kcal: Math.round(Number(o.kcal) || 0),
      proteinG: round1(Number(o.proteinG) || 0),
      carbsG: round1(Number(o.carbsG) || 0),
      fatG: round1(Number(o.fatG) || 0),
    });
  }
  return items;
}
