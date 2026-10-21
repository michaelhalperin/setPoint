/**
 * Searchable USDA catalog. Separate from FoodItem (solver staples) and
 * BarcodeFood (Open Food Facts cache).
 */

export type CatalogFoodView = {
  id: string;
  fdcId: number;
  name: string;
  category: string | null;
  servingG: number | null;
  servingDesc: string | null;
  kcal100g: number;
  proteinG100g: number;
  carbsG100g: number;
  fatG100g: number;
  dataType: string;
};

export type CatalogFoodRow = CatalogFoodView;

const round1 = (n: number): number => Math.round(n * 10) / 10;

export function normalizeSearchQuery(raw: string): string | null {
  const q = raw.replace(/\s+/g, ' ').trim();
  if (q.length < 2 || q.length > 80) return null;
  return q;
}

/** Prefix matches first, then whole-word, then contains; shorter names win ties. */
export function rankCatalogName(name: string, query: string): number {
  const n = name.toLowerCase();
  const q = query.toLowerCase();
  if (n === q) return 0;
  if (n.startsWith(q)) return 1;
  const boundary = n.indexOf(` ${q}`);
  if (boundary >= 0) return 2;
  if (n.includes(q)) return 3;
  return 9;
}

export function searchCatalogRows(rows: CatalogFoodRow[], query: string, limit = 20): CatalogFoodView[] {
  const q = normalizeSearchQuery(query);
  if (!q) return [];
  const needle = q.toLowerCase();
  return rows
    .filter((row) => row.name.toLowerCase().includes(needle))
    .sort((a, b) => {
      const rank = rankCatalogName(a.name, q) - rankCatalogName(b.name, q);
      if (rank !== 0) return rank;
      const type = Number(a.dataType !== 'foundation') - Number(b.dataType !== 'foundation');
      if (type !== 0) return type;
      return a.name.length - b.name.length || a.name.localeCompare(b.name);
    })
    .slice(0, limit)
    .map(toCatalogFoodView);
}

export type CatalogSearchDeps = {
  prisma: {
    catalogFood: {
      findMany: (args: {
        where: { name: { contains: string; mode: 'insensitive' } };
        take: number;
      }) => Promise<CatalogFoodRow[]>;
    };
  };
};

export type CatalogLookupDeps = {
  prisma: {
    catalogFood: {
      findUnique: (args: { where: { id: string } }) => Promise<CatalogFoodRow | null>;
    };
  };
};

export async function searchCatalog(deps: CatalogSearchDeps, raw: string): Promise<CatalogFoodView[]> {
  const q = normalizeSearchQuery(raw);
  if (!q) return [];
  const rows = await deps.prisma.catalogFood.findMany({
    where: { name: { contains: q, mode: 'insensitive' } },
    take: 80,
  });
  return searchCatalogRows(rows, q, 20);
}

export async function getCatalogFood(deps: CatalogLookupDeps, id: string): Promise<CatalogFoodView | null> {
  const row = await deps.prisma.catalogFood.findUnique({ where: { id } });
  return row ? toCatalogFoodView(row) : null;
}

export function macrosForGrams(
  food: Pick<CatalogFoodRow, 'kcal100g' | 'proteinG100g' | 'carbsG100g' | 'fatG100g'>,
  grams: number,
): { grams: number; kcal: number; proteinG: number; carbsG: number; fatG: number } {
  const g = grams > 0 ? grams : 100;
  const factor = g / 100;
  return {
    grams: round1(g),
    kcal: Math.round(food.kcal100g * factor),
    proteinG: round1(food.proteinG100g * factor),
    carbsG: round1(food.carbsG100g * factor),
    fatG: round1(food.fatG100g * factor),
  };
}

export function defaultGrams(food: Pick<CatalogFoodRow, 'servingG'>): number {
  return food.servingG && food.servingG > 0 ? food.servingG : 100;
}

export function toCatalogFoodView(row: CatalogFoodRow): CatalogFoodView {
  return {
    id: row.id,
    fdcId: row.fdcId,
    name: row.name,
    category: row.category,
    servingG: row.servingG,
    servingDesc: row.servingDesc,
    kcal100g: row.kcal100g,
    proteinG100g: row.proteinG100g,
    carbsG100g: row.carbsG100g,
    fatG100g: row.fatG100g,
    dataType: row.dataType,
  };
}
