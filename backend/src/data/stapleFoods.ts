/**
 * The curated staple-food list the prescription solver draws from (plan §2).
 * ~120 low-friction staples with hardcoded macros. Values are rounded from USDA
 * FoodData Central (SR Legacy / Foundation / Survey-FNDDS) at the stated serving
 * size — the "swap to USDA for breadth" step from §2, done as an offline import
 * so the solver stays fully deterministic with no runtime API dependency.
 *
 * The solver narrows this to a small candidate set per request (see
 * `SOLVER_CONFIG.maxCandidates`) before its combinatorial search, so the list
 * can keep growing without slowing prescriptions down.
 *
 * `prisma/seed.ts` loads this into the FoodItem table; the solver reads it too.
 *
 * Allergen tokens: egg, dairy, gluten, wheat, peanut, tree_nut, soy, fish, shellfish, sesame
 * Tag vocab:       vegetarian, vegan, high_protein, no_cook, portable
 */
export type StapleFood = {
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

export const STAPLE_FOODS: StapleFood[] = [
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

  // ===================================================================
  // USDA-sourced breadth (§2) — offline import, same deterministic solver
  // ===================================================================

  // --- eggs & dairy ---
  { slug: 'scrambled-eggs-3', name: '3 scrambled eggs', servingDesc: '3 large eggs with a pat of butter', servingGrams: 165, kcal: 285, proteinG: 19, carbsG: 2, fatG: 22, tags: ['vegetarian', 'high_protein'], allergens: ['egg', 'dairy'] },
  { slug: 'liquid-egg-whites', name: 'Liquid egg whites', servingDesc: '1 cup (243 g)', servingGrams: 243, kcal: 126, proteinG: 26, carbsG: 2, fatG: 0.4, tags: ['vegetarian', 'high_protein', 'no_cook'], allergens: ['egg'] },
  { slug: 'greek-yogurt-whole', name: 'Whole-milk Greek yogurt', servingDesc: '1 cup (200 g)', servingGrams: 200, kcal: 190, proteinG: 16, carbsG: 8, fatG: 10, tags: ['vegetarian', 'high_protein', 'no_cook'], allergens: ['dairy'] },
  { slug: 'skyr', name: 'Skyr', servingDesc: '1 cup (170 g)', servingGrams: 170, kcal: 110, proteinG: 19, carbsG: 7, fatG: 0.5, tags: ['vegetarian', 'high_protein', 'no_cook', 'portable'], allergens: ['dairy'] },
  { slug: 'kefir', name: 'Plain kefir', servingDesc: '1 cup (243 g)', servingGrams: 243, kcal: 160, proteinG: 9, carbsG: 12, fatG: 8, tags: ['vegetarian', 'no_cook'], allergens: ['dairy'] },
  { slug: 'two-percent-milk', name: '2% milk', servingDesc: '1 cup (244 g)', servingGrams: 244, kcal: 122, proteinG: 8, carbsG: 12, fatG: 5, tags: ['vegetarian', 'no_cook'], allergens: ['dairy'] },
  { slug: 'chocolate-milk', name: 'Chocolate milk', servingDesc: '1 cup (250 g)', servingGrams: 250, kcal: 208, proteinG: 8, carbsG: 26, fatG: 8.5, tags: ['vegetarian', 'no_cook', 'portable'], allergens: ['dairy'] },
  { slug: 'ricotta', name: 'Part-skim ricotta', servingDesc: '1/2 cup (124 g)', servingGrams: 124, kcal: 171, proteinG: 14, carbsG: 6, fatG: 10, tags: ['vegetarian', 'high_protein', 'no_cook'], allergens: ['dairy'] },
  { slug: 'mozzarella', name: 'Mozzarella', servingDesc: '1 oz (28 g)', servingGrams: 28, kcal: 85, proteinG: 6, carbsG: 1, fatG: 6, tags: ['vegetarian', 'no_cook'], allergens: ['dairy'] },
  { slug: 'feta', name: 'Feta', servingDesc: '1 oz (28 g)', servingGrams: 28, kcal: 75, proteinG: 4, carbsG: 1, fatG: 6, tags: ['vegetarian', 'no_cook'], allergens: ['dairy'] },
  { slug: 'cream-cheese', name: 'Cream cheese', servingDesc: '2 tbsp (28 g)', servingGrams: 28, kcal: 99, proteinG: 2, carbsG: 1.5, fatG: 10, tags: ['vegetarian', 'no_cook'], allergens: ['dairy'] },
  { slug: 'butter', name: 'Butter', servingDesc: '1 tbsp (14 g)', servingGrams: 14, kcal: 102, proteinG: 0.1, carbsG: 0, fatG: 11.5, tags: ['vegetarian', 'no_cook'], allergens: ['dairy'] },
  { slug: 'heavy-cream', name: 'Heavy cream', servingDesc: '2 tbsp (30 g)', servingGrams: 30, kcal: 100, proteinG: 0.6, carbsG: 0.8, fatG: 11, tags: ['vegetarian', 'no_cook'], allergens: ['dairy'] },

  // --- meat & fish ---
  { slug: 'chicken-thigh', name: 'Chicken thigh', servingDesc: 'cooked, 150 g', servingGrams: 150, kcal: 314, proteinG: 39, carbsG: 0, fatG: 17, tags: ['high_protein'], allergens: [] },
  { slug: 'ground-turkey-93', name: 'Ground turkey (93% lean)', servingDesc: 'cooked, 150 g', servingGrams: 150, kcal: 264, proteinG: 33, carbsG: 0, fatG: 14, tags: ['high_protein'], allergens: [] },
  { slug: 'sirloin-steak', name: 'Sirloin steak', servingDesc: 'cooked, 150 g', servingGrams: 150, kcal: 309, proteinG: 46, carbsG: 0, fatG: 13, tags: ['high_protein'], allergens: [] },
  { slug: 'pork-tenderloin', name: 'Pork tenderloin', servingDesc: 'cooked, 150 g', servingGrams: 150, kcal: 220, proteinG: 39, carbsG: 0, fatG: 6, tags: ['high_protein'], allergens: [] },
  { slug: 'pork-chop', name: 'Pork chop', servingDesc: 'cooked, 150 g', servingGrams: 150, kcal: 291, proteinG: 39, carbsG: 0, fatG: 14, tags: ['high_protein'], allergens: [] },
  { slug: 'sliced-ham', name: 'Sliced ham', servingDesc: '3 slices (84 g)', servingGrams: 84, kcal: 110, proteinG: 15, carbsG: 2, fatG: 4.5, tags: ['high_protein', 'no_cook', 'portable'], allergens: [] },
  { slug: 'deli-roast-beef', name: 'Deli roast beef', servingDesc: '3 slices (84 g)', servingGrams: 84, kcal: 100, proteinG: 18, carbsG: 1, fatG: 3, tags: ['high_protein', 'no_cook', 'portable'], allergens: [] },
  { slug: 'chicken-sausage', name: 'Chicken sausage', servingDesc: '1 link (85 g)', servingGrams: 85, kcal: 140, proteinG: 14, carbsG: 2, fatG: 8, tags: ['high_protein'], allergens: [] },
  { slug: 'beef-jerky', name: 'Beef jerky', servingDesc: '1 oz (28 g)', servingGrams: 28, kcal: 82, proteinG: 11, carbsG: 5, fatG: 2, tags: ['high_protein', 'no_cook', 'portable'], allergens: ['soy'] },
  { slug: 'canned-salmon', name: 'Canned salmon', servingDesc: '1 can (142 g), drained', servingGrams: 142, kcal: 190, proteinG: 30, carbsG: 0, fatG: 8, tags: ['high_protein', 'no_cook', 'portable'], allergens: ['fish'] },
  { slug: 'sardines', name: 'Sardines in oil', servingDesc: '1 can (92 g), drained', servingGrams: 92, kcal: 191, proteinG: 23, carbsG: 0, fatG: 11, tags: ['high_protein', 'no_cook', 'portable'], allergens: ['fish'] },
  { slug: 'tilapia', name: 'Tilapia fillet', servingDesc: 'cooked, 150 g', servingGrams: 150, kcal: 194, proteinG: 40, carbsG: 0, fatG: 4, tags: ['high_protein'], allergens: ['fish'] },
  { slug: 'cooked-shrimp', name: 'Cooked shrimp', servingDesc: '120 g', servingGrams: 120, kcal: 119, proteinG: 23, carbsG: 1.5, fatG: 1.7, tags: ['high_protein', 'no_cook'], allergens: ['shellfish'] },

  // --- plant protein & nuts ---
  { slug: 'tempeh', name: 'Tempeh', servingDesc: '100 g', servingGrams: 100, kcal: 192, proteinG: 20, carbsG: 8, fatG: 11, tags: ['vegan', 'vegetarian', 'high_protein'], allergens: ['soy'] },
  { slug: 'seitan', name: 'Seitan', servingDesc: '100 g', servingGrams: 100, kcal: 145, proteinG: 24, carbsG: 8, fatG: 2, tags: ['vegan', 'vegetarian', 'high_protein'], allergens: ['gluten', 'wheat'] },
  { slug: 'soy-milk', name: 'Soy milk', servingDesc: '1 cup (243 g)', servingGrams: 243, kcal: 105, proteinG: 6, carbsG: 12, fatG: 4, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: ['soy'] },
  { slug: 'kidney-beans', name: 'Kidney beans', servingDesc: '1 cup (177 g) cooked', servingGrams: 177, kcal: 225, proteinG: 15, carbsG: 40, fatG: 0.9, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: [] },
  { slug: 'refried-beans', name: 'Refried beans', servingDesc: '1 cup (238 g)', servingGrams: 238, kcal: 217, proteinG: 13, carbsG: 36, fatG: 3, tags: ['vegetarian', 'no_cook'], allergens: [] },
  { slug: 'split-pea-soup', name: 'Split pea soup', servingDesc: '1 cup (250 g)', servingGrams: 250, kcal: 190, proteinG: 11, carbsG: 32, fatG: 3, tags: ['vegetarian', 'no_cook'], allergens: [] },
  { slug: 'falafel', name: 'Falafel', servingDesc: '3 patties (51 g)', servingGrams: 51, kcal: 170, proteinG: 7, carbsG: 16, fatG: 9, tags: ['vegan', 'vegetarian'], allergens: [] },
  { slug: 'veggie-burger', name: 'Veggie burger patty', servingDesc: '1 patty (85 g)', servingGrams: 85, kcal: 130, proteinG: 12, carbsG: 9, fatG: 5, tags: ['vegetarian', 'high_protein'], allergens: ['soy'] },
  { slug: 'roasted-chickpeas', name: 'Roasted chickpeas', servingDesc: '1/3 cup (40 g)', servingGrams: 40, kcal: 160, proteinG: 7, carbsG: 20, fatG: 6, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: [] },
  { slug: 'cashews', name: 'Cashews', servingDesc: '1 oz (28 g)', servingGrams: 28, kcal: 157, proteinG: 5, carbsG: 9, fatG: 12, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: ['tree_nut'] },
  { slug: 'walnuts', name: 'Walnuts', servingDesc: '1 oz (28 g)', servingGrams: 28, kcal: 185, proteinG: 4, carbsG: 4, fatG: 18, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: ['tree_nut'] },
  { slug: 'pistachios', name: 'Pistachios', servingDesc: '1 oz (28 g)', servingGrams: 28, kcal: 159, proteinG: 6, carbsG: 8, fatG: 13, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: ['tree_nut'] },
  { slug: 'pumpkin-seeds', name: 'Pumpkin seeds', servingDesc: '1 oz (28 g)', servingGrams: 28, kcal: 158, proteinG: 9, carbsG: 3, fatG: 14, tags: ['vegan', 'vegetarian', 'high_protein', 'no_cook', 'portable'], allergens: [] },
  { slug: 'sunflower-seeds', name: 'Sunflower seeds', servingDesc: '1 oz (28 g), kernels', servingGrams: 28, kcal: 165, proteinG: 5.5, carbsG: 7, fatG: 14, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: [] },
  { slug: 'almond-butter', name: 'Almond butter', servingDesc: '2 tbsp (32 g)', servingGrams: 32, kcal: 196, proteinG: 7, carbsG: 6, fatG: 18, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: ['tree_nut'] },
  { slug: 'tahini', name: 'Tahini', servingDesc: '2 tbsp (30 g)', servingGrams: 30, kcal: 178, proteinG: 5, carbsG: 6, fatG: 16, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: ['sesame'] },
  { slug: 'chia-seeds', name: 'Chia seeds', servingDesc: '2 tbsp (28 g)', servingGrams: 28, kcal: 138, proteinG: 5, carbsG: 12, fatG: 9, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: [] },
  { slug: 'hemp-hearts', name: 'Hemp hearts', servingDesc: '3 tbsp (30 g)', servingGrams: 30, kcal: 166, proteinG: 10, carbsG: 3, fatG: 14, tags: ['vegan', 'vegetarian', 'high_protein', 'no_cook', 'portable'], allergens: [] },

  // --- carbs ---
  { slug: 'brown-rice', name: 'Brown rice', servingDesc: '1 cup (195 g) cooked', servingGrams: 195, kcal: 218, proteinG: 5, carbsG: 46, fatG: 1.6, tags: ['vegan', 'vegetarian'], allergens: [] },
  { slug: 'quinoa', name: 'Quinoa', servingDesc: '1 cup (185 g) cooked', servingGrams: 185, kcal: 222, proteinG: 8, carbsG: 39, fatG: 3.6, tags: ['vegan', 'vegetarian'], allergens: [] },
  { slug: 'couscous', name: 'Couscous', servingDesc: '1 cup (157 g) cooked', servingGrams: 157, kcal: 176, proteinG: 6, carbsG: 36, fatG: 0.3, tags: ['vegan', 'vegetarian'], allergens: ['gluten', 'wheat'] },
  { slug: 'farro', name: 'Farro', servingDesc: '1 cup (170 g) cooked', servingGrams: 170, kcal: 200, proteinG: 8, carbsG: 42, fatG: 1.5, tags: ['vegan', 'vegetarian'], allergens: ['gluten', 'wheat'] },
  { slug: 'white-bread', name: 'White bread', servingDesc: '2 slices (50 g)', servingGrams: 50, kcal: 132, proteinG: 4, carbsG: 25, fatG: 1.6, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: ['gluten', 'wheat'] },
  { slug: 'sourdough-bread', name: 'Sourdough bread', servingDesc: '2 slices (64 g)', servingGrams: 64, kcal: 165, proteinG: 6, carbsG: 32, fatG: 1.5, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: ['gluten', 'wheat'] },
  { slug: 'english-muffin', name: 'English muffin', servingDesc: '1 muffin (57 g)', servingGrams: 57, kcal: 134, proteinG: 4.4, carbsG: 26, fatG: 1, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: ['gluten', 'wheat'] },
  { slug: 'flour-tortilla', name: 'Flour tortilla', servingDesc: '1 large (72 g)', servingGrams: 72, kcal: 218, proteinG: 6, carbsG: 36, fatG: 5, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: ['gluten', 'wheat'] },
  { slug: 'corn-tortilla', name: 'Corn tortillas', servingDesc: '2 tortillas (52 g)', servingGrams: 52, kcal: 120, proteinG: 3, carbsG: 24, fatG: 1.6, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: [] },
  { slug: 'pita-bread', name: 'Pita bread', servingDesc: '1 large (60 g)', servingGrams: 60, kcal: 165, proteinG: 5.5, carbsG: 33, fatG: 0.7, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: ['gluten', 'wheat'] },
  { slug: 'crackers', name: 'Whole-grain crackers', servingDesc: '7 crackers (30 g)', servingGrams: 30, kcal: 140, proteinG: 3, carbsG: 22, fatG: 5, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: ['gluten', 'wheat'] },
  { slug: 'rice-cakes', name: 'Rice cakes', servingDesc: '2 cakes (18 g)', servingGrams: 18, kcal: 70, proteinG: 1.5, carbsG: 14, fatG: 0.5, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: [] },
  { slug: 'pretzels', name: 'Pretzels', servingDesc: '1 oz (28 g)', servingGrams: 28, kcal: 108, proteinG: 3, carbsG: 22, fatG: 1, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: ['gluten', 'wheat'] },
  { slug: 'popcorn', name: 'Air-popped popcorn', servingDesc: '3 cups (24 g)', servingGrams: 24, kcal: 93, proteinG: 3, carbsG: 19, fatG: 1, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: [] },
  { slug: 'mashed-potatoes', name: 'Mashed potatoes', servingDesc: '1 cup (210 g)', servingGrams: 210, kcal: 214, proteinG: 4, carbsG: 35, fatG: 8, tags: ['vegetarian'], allergens: ['dairy'] },
  { slug: 'corn', name: 'Corn', servingDesc: '1 cup (164 g)', servingGrams: 164, kcal: 143, proteinG: 5, carbsG: 31, fatG: 2, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: [] },
  { slug: 'green-peas', name: 'Green peas', servingDesc: '1 cup (160 g)', servingGrams: 160, kcal: 134, proteinG: 8, carbsG: 25, fatG: 0.4, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: [] },
  { slug: 'dinner-roll', name: 'Dinner roll', servingDesc: '2 rolls (57 g)', servingGrams: 57, kcal: 174, proteinG: 5, carbsG: 30, fatG: 4, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: ['gluten', 'wheat'] },
  { slug: 'pancakes', name: 'Pancakes', servingDesc: '2 pancakes (77 g)', servingGrams: 77, kcal: 175, proteinG: 5, carbsG: 22, fatG: 7, tags: ['vegetarian'], allergens: ['gluten', 'wheat', 'egg', 'dairy'] },
  { slug: 'frozen-waffles', name: 'Frozen waffles', servingDesc: '2 waffles (70 g)', servingGrams: 70, kcal: 190, proteinG: 4, carbsG: 30, fatG: 6, tags: ['vegetarian'], allergens: ['gluten', 'wheat', 'egg'] },

  // --- fruit ---
  { slug: 'apple', name: 'Apple', servingDesc: '1 medium (182 g)', servingGrams: 182, kcal: 95, proteinG: 0.5, carbsG: 25, fatG: 0.3, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: [] },
  { slug: 'orange', name: 'Orange', servingDesc: '1 medium (131 g)', servingGrams: 131, kcal: 62, proteinG: 1.2, carbsG: 15, fatG: 0.2, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: [] },
  { slug: 'grapes', name: 'Grapes', servingDesc: '1 cup (151 g)', servingGrams: 151, kcal: 104, proteinG: 1, carbsG: 27, fatG: 0.2, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: [] },
  { slug: 'blueberries', name: 'Blueberries', servingDesc: '1 cup (148 g)', servingGrams: 148, kcal: 84, proteinG: 1, carbsG: 21, fatG: 0.5, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: [] },
  { slug: 'raisins', name: 'Raisins', servingDesc: '1 small box (43 g)', servingGrams: 43, kcal: 129, proteinG: 1.3, carbsG: 34, fatG: 0.2, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: [] },
  { slug: 'medjool-dates', name: 'Medjool dates', servingDesc: '3 dates (72 g)', servingGrams: 72, kcal: 200, proteinG: 1.4, carbsG: 54, fatG: 0.1, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: [] },
  { slug: 'dried-apricots', name: 'Dried apricots', servingDesc: '1/4 cup (33 g)', servingGrams: 33, kcal: 80, proteinG: 1, carbsG: 21, fatG: 0.1, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: [] },
  { slug: 'applesauce', name: 'Applesauce cup', servingDesc: '1 cup (111 g), unsweetened', servingGrams: 111, kcal: 51, proteinG: 0.2, carbsG: 14, fatG: 0.1, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: [] },
  { slug: 'trail-mix-fruit-nut', name: 'Fruit & nut trail mix', servingDesc: '1/4 cup (38 g)', servingGrams: 38, kcal: 175, proteinG: 4, carbsG: 17, fatG: 11, tags: ['vegetarian', 'no_cook', 'portable'], allergens: ['tree_nut', 'peanut'] },

  // --- fats & condiments ---
  { slug: 'avocado-whole', name: 'Whole avocado', servingDesc: '1 medium (200 g)', servingGrams: 200, kcal: 320, proteinG: 4, carbsG: 17, fatG: 29, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: [] },
  { slug: 'olives', name: 'Olives', servingDesc: '10 large (44 g)', servingGrams: 44, kcal: 51, proteinG: 0.4, carbsG: 2.7, fatG: 4.7, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: [] },
  { slug: 'coconut-milk-canned', name: 'Canned coconut milk', servingDesc: '1/2 cup (120 g)', servingGrams: 120, kcal: 223, proteinG: 2, carbsG: 3, fatG: 24, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: [] },
  { slug: 'mayonnaise', name: 'Mayonnaise', servingDesc: '1 tbsp (14 g)', servingGrams: 14, kcal: 94, proteinG: 0.1, carbsG: 0.1, fatG: 10, tags: ['vegetarian', 'no_cook'], allergens: ['egg'] },
  { slug: 'guacamole', name: 'Guacamole', servingDesc: '1/4 cup (60 g)', servingGrams: 60, kcal: 90, proteinG: 1, carbsG: 5, fatG: 8, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: [] },

  // --- convenience & composed ---
  { slug: 'turkey-sandwich', name: 'Turkey sandwich', servingDesc: '2 slices bread, turkey, cheese', servingGrams: 200, kcal: 360, proteinG: 26, carbsG: 33, fatG: 13, tags: ['high_protein', 'no_cook', 'portable'], allergens: ['gluten', 'wheat', 'dairy'] },
  { slug: 'pbj-sandwich', name: 'Peanut butter & jelly sandwich', servingDesc: '2 slices bread, PB, jam', servingGrams: 120, kcal: 380, proteinG: 12, carbsG: 48, fatG: 17, tags: ['vegetarian', 'no_cook', 'portable'], allergens: ['gluten', 'wheat', 'peanut'] },
  { slug: 'grilled-cheese', name: 'Grilled cheese', servingDesc: '2 slices bread, 2 slices cheese', servingGrams: 130, kcal: 400, proteinG: 15, carbsG: 32, fatG: 24, tags: ['vegetarian'], allergens: ['gluten', 'wheat', 'dairy'] },
  { slug: 'bean-burrito', name: 'Bean & cheese burrito', servingDesc: '1 burrito (200 g)', servingGrams: 200, kcal: 420, proteinG: 16, carbsG: 60, fatG: 13, tags: ['vegetarian'], allergens: ['gluten', 'wheat', 'dairy'] },
  { slug: 'cheese-pizza-slice', name: 'Cheese pizza', servingDesc: '1 slice (107 g)', servingGrams: 107, kcal: 285, proteinG: 12, carbsG: 36, fatG: 10, tags: ['vegetarian', 'no_cook'], allergens: ['gluten', 'wheat', 'dairy'] },
  { slug: 'mac-and-cheese', name: 'Macaroni & cheese', servingDesc: '1 cup (200 g)', servingGrams: 200, kcal: 376, proteinG: 13, carbsG: 47, fatG: 15, tags: ['vegetarian'], allergens: ['gluten', 'wheat', 'dairy'] },
  { slug: 'ramen-packet', name: 'Instant ramen', servingDesc: '1 packet (85 g), prepared', servingGrams: 85, kcal: 380, proteinG: 8, carbsG: 52, fatG: 14, tags: ['vegan', 'vegetarian'], allergens: ['gluten', 'wheat'] },
  { slug: 'chicken-noodle-soup', name: 'Chicken noodle soup', servingDesc: '1 can (300 g)', servingGrams: 300, kcal: 180, proteinG: 10, carbsG: 24, fatG: 5, tags: [], allergens: ['gluten', 'wheat'] },
  { slug: 'canned-chili', name: 'Canned chili with beans', servingDesc: '1 cup (222 g)', servingGrams: 222, kcal: 287, proteinG: 15, carbsG: 30, fatG: 12, tags: ['high_protein', 'no_cook'], allergens: [] },
  { slug: 'lentil-soup', name: 'Lentil soup', servingDesc: '1 cup (248 g)', servingGrams: 248, kcal: 180, proteinG: 12, carbsG: 28, fatG: 3, tags: ['vegan', 'vegetarian', 'no_cook'], allergens: [] },
  { slug: 'fruit-smoothie', name: 'Fruit smoothie', servingDesc: '16 oz, fruit + yogurt', servingGrams: 450, kcal: 320, proteinG: 10, carbsG: 62, fatG: 4, tags: ['vegetarian', 'no_cook', 'portable'], allergens: ['dairy'] },
  { slug: 'protein-smoothie', name: 'Protein smoothie', servingDesc: '16 oz, fruit + protein + milk', servingGrams: 450, kcal: 380, proteinG: 32, carbsG: 45, fatG: 8, tags: ['vegetarian', 'high_protein', 'no_cook', 'portable'], allergens: ['dairy'] },
  { slug: 'yogurt-parfait', name: 'Yogurt & fruit parfait', servingDesc: 'yogurt, berries, granola', servingGrams: 280, kcal: 300, proteinG: 16, carbsG: 45, fatG: 7, tags: ['vegetarian', 'high_protein', 'no_cook', 'portable'], allergens: ['dairy', 'tree_nut'] },
  { slug: 'apple-with-peanut-butter', name: 'Apple with peanut butter', servingDesc: '1 apple + 2 tbsp PB', servingGrams: 214, kcal: 285, proteinG: 8, carbsG: 32, fatG: 16, tags: ['vegan', 'vegetarian', 'no_cook', 'portable'], allergens: ['peanut'] },
  { slug: 'cottage-cheese-with-fruit', name: 'Cottage cheese with fruit', servingDesc: '1 cup cottage cheese + fruit', servingGrams: 300, kcal: 240, proteinG: 28, carbsG: 20, fatG: 5, tags: ['vegetarian', 'high_protein', 'no_cook', 'portable'], allergens: ['dairy'] },
  { slug: 'bagel-with-cream-cheese', name: 'Bagel with cream cheese', servingDesc: '1 bagel + 2 tbsp cream cheese', servingGrams: 126, kcal: 355, proteinG: 12, carbsG: 51, fatG: 11, tags: ['vegetarian', 'no_cook'], allergens: ['gluten', 'wheat', 'dairy'] },
  { slug: 'breakfast-sandwich', name: 'Egg & cheese breakfast sandwich', servingDesc: 'muffin, egg, cheese', servingGrams: 165, kcal: 380, proteinG: 18, carbsG: 30, fatG: 21, tags: ['vegetarian', 'high_protein'], allergens: ['gluten', 'wheat', 'egg', 'dairy'] },
  { slug: 'egg-salad-sandwich', name: 'Egg salad sandwich', servingDesc: '2 slices bread + egg salad', servingGrams: 190, kcal: 390, proteinG: 15, carbsG: 30, fatG: 23, tags: ['vegetarian', 'no_cook'], allergens: ['gluten', 'wheat', 'egg'] },
  { slug: 'chicken-caesar-salad', name: 'Chicken Caesar salad', servingDesc: 'romaine, chicken, dressing (300 g)', servingGrams: 300, kcal: 400, proteinG: 32, carbsG: 12, fatG: 25, tags: ['high_protein', 'no_cook'], allergens: ['dairy', 'fish', 'egg'] },
  { slug: 'chicken-rice-bowl', name: 'Chicken & rice bowl', servingDesc: 'chicken, rice, veg (350 g)', servingGrams: 350, kcal: 480, proteinG: 40, carbsG: 52, fatG: 11, tags: ['high_protein'], allergens: [] },
  { slug: 'overnight-oats', name: 'Overnight oats', servingDesc: 'oats, milk, chia, fruit', servingGrams: 300, kcal: 350, proteinG: 13, carbsG: 55, fatG: 9, tags: ['vegetarian', 'no_cook', 'portable'], allergens: ['dairy'] },
  { slug: 'ready-protein-shake', name: 'Ready-to-drink protein shake', servingDesc: '1 bottle (325 ml)', servingGrams: 325, kcal: 160, proteinG: 30, carbsG: 5, fatG: 3, tags: ['vegetarian', 'high_protein', 'no_cook', 'portable'], allergens: ['dairy'] },
  { slug: 'nutrition-shake', name: 'Nutrition shake', servingDesc: '1 bottle (237 ml)', servingGrams: 237, kcal: 220, proteinG: 9, carbsG: 33, fatG: 6, tags: ['vegetarian', 'no_cook', 'portable'], allergens: ['dairy', 'soy'] },
  { slug: 'plant-protein-shake', name: 'Plant protein shake', servingDesc: '1 scoop in water', servingGrams: 35, kcal: 130, proteinG: 21, carbsG: 6, fatG: 2.5, tags: ['vegan', 'vegetarian', 'high_protein', 'no_cook', 'portable'], allergens: ['soy'] },
];
