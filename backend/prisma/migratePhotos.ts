/**
 * One-off: moves legacy inline meal photos (Meal.photoUrl data URLs) into
 * object storage and clears them from Postgres. Safe to re-run; a row that
 * fails to upload is left untouched and reported.
 *
 * Needs DATABASE_URL and the PHOTO_* env vars.
 * Run: pnpm --filter @setpoint/backend exec tsx prisma/migratePhotos.ts
 */
import { getPrisma } from '../src/db/client.js';
import { getPhotoStore } from '../src/photos/store.js';

const DATA_URL = /^data:([^;,]+);base64,(.+)$/s;

async function main(): Promise<void> {
  const photos = getPhotoStore();
  if (!photos) throw new Error('Set the PHOTO_* env vars before migrating photos.');
  const prisma = getPrisma();

  const failed: string[] = [];
  let moved = 0;

  for (;;) {
    const batch = await prisma.meal.findMany({
      where: { photoUrl: { startsWith: 'data:' }, id: { notIn: failed } },
      select: { id: true, userId: true, photoUrl: true },
      take: 25,
    });
    if (batch.length === 0) break;

    for (const meal of batch) {
      const match = DATA_URL.exec(meal.photoUrl ?? '');
      try {
        if (!match) throw new Error('not a base64 data URL');
        const key = await photos.put(meal.userId, Buffer.from(match[2]!, 'base64'), match[1]!);
        await prisma.meal.update({ where: { id: meal.id }, data: { photoKey: key, photoUrl: null } });
        moved += 1;
      } catch (err) {
        failed.push(meal.id);
        console.error(`meal ${meal.id}: ${(err as Error).message}`);
      }
    }
  }

  console.log(`Moved ${moved} photo(s) to storage; ${failed.length} failed.`);
  await prisma.$disconnect();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
