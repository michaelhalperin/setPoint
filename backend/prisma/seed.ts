/**
 * Seeds the curated staple-food list (`src/data/stapleFoods.ts`) into the
 * FoodItem table. The prescription solver (plan §2) draws from these.
 *
 * Run: pnpm --filter @setpoint/backend db:seed
 */
import { STAPLE_FOODS } from '../src/data/stapleFoods.js';
import { getPrisma } from '../src/db/client.js';

async function main(): Promise<void> {
  const prisma = getPrisma();
  let created = 0;
  let updated = 0;

  for (const food of STAPLE_FOODS) {
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

  console.log(
    `Seeded staple foods: ${created} created, ${updated} updated (${STAPLE_FOODS.length} total).`,
  );
  await prisma.$disconnect();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
