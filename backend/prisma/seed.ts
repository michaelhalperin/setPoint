/**
 * Seeds the curated staple-food list the prescription solver draws from (§2).
 * ~40 low-friction staples with hardcoded macros. Swap to USDA FoodData Central
 * or Open Food Facts later for breadth.
 *
 * Run: pnpm --filter @setpoint/backend db:seed
 */
import { getPrisma } from '../src/db/client.js';

type Seed = {
  slug: string;
  name: string;
  servingDesc: string;
  servingGrams?: number;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  tags: string[];
  allergens: string[];
};

// Allergen tokens: egg, dairy, gluten, wheat, peanut, tree_nut, soy, fish, shellfish, sesame
// Tag vocab: vegetarian, vegan, high_protein, no_cook, portable
const FOODS: Seed[] = [
  // --- eggs & dairy ---
  { slug: 'eggs-2-large', name: '2 large eggs', servingDesc: '2 large eggs, cooked', servingGrams: 100, kcal: 156, proteinG: 12.6, carbsG: 1.1, fatG: 10.6, tags: ['vegetarian', 'high_protein'], allergens: ['egg'] },
  { slug: 'hard-boiled-eggs', name: 'Hard-boiled eggs', servingDesc: '2 eggs', servingGrams: 100, kcal: 156, proteinG: 12.6, carbsG: 1.1, fatG: 10.6, tags: ['vegetarian', 'high_protein', 'no_cook', 'portable'], allergens: ['egg'] },
  { slug: 'greek-yogurt-plain', name: 'Plain nonfat Greek yogurt', servingDesc: '1 cup (170 g)', servingGrams: 170, kcal: 100, proteinG: 17, carbsG: 6, fatG: 0.7, tags: ['vegetarian', 'high_protein', 'no_cook'], allergens: ['dairy'] },
  { slug: 'cottage-cheese', name: '2% cottage cheese', servingDesc: '1 cup (226 g)', servingGrams: 226, kcal: 194, proteinG: 27, carbsG: 8, fatG: 5.5, tags: ['vegetarian', 'high_protein', 'no_cook'], allergens: ['dairy'] },
  { slug: 'whole-milk', name: 'Whole milk', servingDesc: '1 cup (240 ml)', servingGrams: 240, kcal: 149, proteinG: 8, carbsG: 12, fatG: 8, tags: ['vegetarian', 'no_cook'], allergens: ['dairy'] },
  { slug: 'cheddar-cheese', name: 'Cheddar cheese', servingDesc: '1 slice (28 g)', servingGrams: 28, kcal: 113, proteinG: 7, carbsG: 0.4, fatG: 9, tags: ['vegetarian', 'no_cook'], allergens: ['dairy'] },
  { slug: 'string-cheese', name: 'String cheese', servingDesc: '2 sticks (56 g)', servingGrams: 56, kcal: 160, proteinG: 14, carbsG: 2, fatG: 11, tags: ['vegetarian', 'high_protein', 'no_cook', 'portable'], allergens: ['dairy'] },

  // --- meat & fish ---
  { slug: 'chicken-breast', name: 'Chicken breast', servingDesc: 'cooked, 150 g', servingGrams: 150, kcal: 248, proteinG: 46.5, carbsG: 0, fatG: 5.4, tags: ['high_protein'], allergens: [] },
  { slug: 'rotisserie-chicken', name: 'Rotisserie chicken', servingDesc: '150 g mixed', servingGrams: 150, kcal: 260, proteinG: 35, carbsG: 0, fatG: 13, tags: ['high_protein', 'no_cook'], allergens: [] },
  { slug: 'ground-beef-90', name: 'Ground beef (90% lean)', servingDesc: 'cooked, 150 g', servingGrams: 150, kcal: 273, proteinG: 34, carbsG: 0, fatG: 14, tags: ['high_protein'], allergens: [] },
  { slug: 'deli-turkey', name: 'Deli turkey slices', servingDesc: '3 slices (84 g)', servingGrams: 84, kcal: 90, proteinG: 17, carbsG: 2, fatG: 1.5, tags: ['high_protein', 'no_cook', 'portable'], allergens: [] },
  { slug: 'canned-tuna', name: 'Canned tuna in water', servingDesc: '1 can (142 g), drained', servingGrams: 142, kcal: 179, proteinG: 39, carbsG: 0, fatG: 1.3, tags: ['high_protein', 'no_cook', 'portable'], allergens: ['fish'] },
  { slug: 'salmon-fillet', name: 'Salmon fillet', servingDesc: 'cooked, 150 g', servingGrams: 150, kcal: 280, proteinG: 39, carbsG: 0, fatG: 12.5, tags: ['high_protein'], allergens: ['fish'] },

  // --- plant protein & nuts ---
  { slug: 'firm-tofu', name: 'Firm tofu', servingDesc: '150 g', servingGrams: 150, kcal: 173, proteinG: 18, carbsG: 4, fatG: 10, tags: ['vegan', 'vegetarian', 'high_protein'], allergens: ['soy'] },
  { slug: 'edamame', name: 'Shelled edamame', servingDesc: '1 cup (155 g)', servingGrams: 155, kcal: 188, proteinG: 18, carbsG: 14, fatG: 8, tags: ['vegan', 'vegetarian', 'high_protein'], allergens: ['soy'] },
  { slug: 'black-beans', name: 'Black beans', servingDesc: '1 cup (172 g) cooked', servingGrams: 172, kcal: 227, proteinG: 15, carbsG: 41, fatG: 0.9, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: [] },
  { slug: 'lentils', name: 'Lentils', servingDesc: '1 cup (198 g) cooked', servingGrams: 198, kcal: 230, proteinG: 18, carbsG: 40, fatG: 0.8, tags: ['vegan', 'vegetarian'], allergens: [] },
  { slug: 'chickpeas', name: 'Chickpeas', servingDesc: '1 cup (164 g) cooked', servingGrams: 164, kcal: 269, proteinG: 15, carbsG: 45, fatG: 4, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: [] },
  { slug: 'hummus', name: 'Hummus', servingDesc: '1/4 cup (60 g)', servingGrams: 60, kcal: 145, proteinG: 4, carbsG: 12, fatG: 9, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: ['sesame'] },
  { slug: 'peanut-butter', name: 'Peanut butter', servingDesc: '2 tbsp (32 g)', servingGrams: 32, kcal: 190, proteinG: 8, carbsG: 7, fatG: 16, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: ['peanut'] },
  { slug: 'almonds', name: 'Almonds', servingDesc: '1 oz (28 g)', servingGrams: 28, kcal: 164, proteinG: 6, carbsG: 6, fatG: 14, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: ['tree_nut'] },
  { slug: 'mixed-nuts', name: 'Mixed nuts', servingDesc: '1 oz (28 g)', servingGrams: 28, kcal: 173, proteinG: 5, carbsG: 6, fatG: 15, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: ['tree_nut', 'peanut'] },
  { slug: 'trail-mix', name: 'Trail mix', servingDesc: '1/4 cup (40 g)', servingGrams: 40, kcal: 200, proteinG: 5, carbsG: 20, fatG: 13, tags: ['vegetarian', 'no_cook', 'portable'], allergens: ['tree_nut', 'peanut'] },

  // --- carbs ---
  { slug: 'white-rice', name: 'White rice', servingDesc: '1 cup (158 g) cooked', servingGrams: 158, kcal: 205, proteinG: 4.3, carbsG: 45, fatG: 0.4, tags: ['vegan', 'vegetarian'], allergens: [] },
  { slug: 'pasta', name: 'Pasta', servingDesc: '1 cup (140 g) cooked', servingGrams: 140, kcal: 221, proteinG: 8, carbsG: 43, fatG: 1.3, tags: ['vegan', 'vegetarian'], allergens: ['gluten', 'wheat'] },
  { slug: 'rolled-oats', name: 'Rolled oats', servingDesc: '1/2 cup (40 g) dry', servingGrams: 40, kcal: 152, proteinG: 5, carbsG: 27, fatG: 2.5, tags: ['vegan', 'vegetarian'], allergens: [] },
  { slug: 'instant-oatmeal-packet', name: 'Instant oatmeal packet', servingDesc: '1 packet (43 g), prepared', servingGrams: 43, kcal: 160, proteinG: 4, carbsG: 32, fatG: 2, tags: ['vegan', 'vegetarian', 'portable'], allergens: [] },
  { slug: 'whole-wheat-bread', name: 'Whole wheat bread', servingDesc: '2 slices (56 g)', servingGrams: 56, kcal: 160, proteinG: 8, carbsG: 28, fatG: 2, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: ['gluten', 'wheat'] },
  { slug: 'bagel', name: 'Plain bagel', servingDesc: '1 bagel (98 g)', servingGrams: 98, kcal: 257, proteinG: 10, carbsG: 50, fatG: 1.5, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: ['gluten', 'wheat'] },
  { slug: 'banana', name: 'Banana', servingDesc: '1 medium (118 g)', servingGrams: 118, kcal: 105, proteinG: 1.3, carbsG: 27, fatG: 0.4, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: [] },
  { slug: 'baked-potato', name: 'Baked potato', servingDesc: '1 medium (173 g)', servingGrams: 173, kcal: 161, proteinG: 4.3, carbsG: 37, fatG: 0.2, tags: ['vegan', 'vegetarian'], allergens: [] },
  { slug: 'sweet-potato', name: 'Sweet potato', servingDesc: '1 medium (150 g) baked', servingGrams: 150, kcal: 135, proteinG: 3, carbsG: 31, fatG: 0.2, tags: ['vegan', 'vegetarian'], allergens: [] },

  // --- fats ---
  { slug: 'olive-oil', name: 'Olive oil', servingDesc: '1 tbsp (14 g)', servingGrams: 14, kcal: 119, proteinG: 0, carbsG: 0, fatG: 14, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: [] },
  { slug: 'avocado', name: 'Avocado', servingDesc: '1/2 medium (100 g)', servingGrams: 100, kcal: 160, proteinG: 2, carbsG: 9, fatG: 15, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: [] },

  // --- convenience & composed ---
  { slug: 'whey-protein-shake', name: 'Whey protein shake', servingDesc: '1 scoop (32 g) in water', servingGrams: 32, kcal: 120, proteinG: 24, carbsG: 3, fatG: 1.5, tags: ['vegetarian', 'high_protein', 'no_cook', 'portable'], allergens: ['dairy'] },
  { slug: 'protein-bar', name: 'Protein bar', servingDesc: '1 bar (60 g)', servingGrams: 60, kcal: 220, proteinG: 20, carbsG: 22, fatG: 7, tags: ['vegetarian', 'high_protein', 'no_cook', 'portable'], allergens: ['dairy', 'soy', 'tree_nut'] },
  { slug: 'granola', name: 'Granola', servingDesc: '1/2 cup (55 g)', servingGrams: 55, kcal: 250, proteinG: 6, carbsG: 37, fatG: 9, tags: ['vegetarian', 'no_cook'], allergens: ['tree_nut'] },
  { slug: 'cereal-with-milk', name: 'Cereal with milk', servingDesc: '1 cup cereal + 1/2 cup milk', servingGrams: 200, kcal: 210, proteinG: 8, carbsG: 40, fatG: 3.5, tags: ['vegetarian', 'no_cook'], allergens: ['dairy', 'gluten'] },
  { slug: 'greek-yogurt-granola', name: 'Greek yogurt with granola', servingDesc: '1 cup yogurt + 1/2 cup granola', servingGrams: 225, kcal: 350, proteinG: 23, carbsG: 43, fatG: 9, tags: ['vegetarian', 'high_protein', 'no_cook'], allergens: ['dairy', 'tree_nut'] },
  { slug: 'pb-banana-toast', name: 'Peanut butter & banana toast', servingDesc: '2 slices toast + 2 tbsp PB + 1 banana', servingGrams: 240, kcal: 455, proteinG: 16, carbsG: 58, fatG: 19, tags: ['vegan', 'vegetarian'], allergens: ['gluten', 'wheat', 'peanut'] },
  { slug: 'tuna-crackers', name: 'Tuna with crackers', servingDesc: '1 can tuna + 6 crackers', servingGrams: 200, kcal: 280, proteinG: 40, carbsG: 18, fatG: 4, tags: ['high_protein', 'no_cook', 'portable'], allergens: ['fish', 'gluten', 'wheat'] },
  { slug: 'burrito-bowl', name: 'Chicken burrito bowl', servingDesc: 'chicken, rice, beans (400 g)', servingGrams: 400, kcal: 520, proteinG: 38, carbsG: 55, fatG: 14, tags: ['high_protein'], allergens: [] },
];

async function main(): Promise<void> {
  const prisma = getPrisma();
  let created = 0;
  let updated = 0;

  for (const food of FOODS) {
    const result = await prisma.foodItem.upsert({
      where: { slug: food.slug },
      create: { ...food, source: 'CURATED', isStaple: true },
      update: {
        name: food.name,
        servingDesc: food.servingDesc,
        servingGrams: food.servingGrams,
        kcal: food.kcal,
        proteinG: food.proteinG,
        carbsG: food.carbsG,
        fatG: food.fatG,
        tags: food.tags,
        allergens: food.allergens,
      },
    });
    if (result.createdAt.getTime() === result.updatedAt.getTime()) created += 1;
    else updated += 1;
  }

  console.log(`Seeded staple foods: ${created} created, ${updated} updated (${FOODS.length} total).`);
  await prisma.$disconnect();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
