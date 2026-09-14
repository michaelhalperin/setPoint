import type { PrismaClient, WorkoutKind, WorkoutSource } from '@prisma/client';

export type WorkoutInput = {
  source: WorkoutSource;
  kind: WorkoutKind;
  start: Date;
  durationMin: number;
  activeKcal: number | null;
  clientId?: string | null;
};

/** HealthKit rows upsert by clientId. Planned rows in the payload replace the next-7-day window; an HK-only sync leaves planned sessions alone. */
export async function replaceWorkouts(
  prisma: PrismaClient,
  userId: string,
  input: { plannedFrom: Date; plannedTo: Date; healthkitFrom: Date; workouts: WorkoutInput[] },
): Promise<number> {
  const planned = input.workouts.filter((w) => w.source === 'PLANNED');
  const healthkit = input.workouts.filter((w) => w.source === 'HEALTHKIT' && w.clientId);

  await prisma.$transaction(async (tx) => {
    if (planned.length > 0) {
      await tx.workout.deleteMany({
        where: {
          userId,
          source: 'PLANNED',
          start: { gte: input.plannedFrom, lt: input.plannedTo },
        },
      });
      await tx.workout.createMany({
        data: planned.map((w) => ({
          userId,
          source: 'PLANNED' as const,
          kind: w.kind,
          start: w.start,
          durationMin: w.durationMin,
          activeKcal: w.activeKcal,
          clientId: w.clientId ?? undefined,
        })),
      });
    }

    const hkIds = healthkit.map((w) => w.clientId!);
    await tx.workout.deleteMany({
      where: {
        userId,
        source: 'HEALTHKIT',
        start: { gte: input.healthkitFrom },
        ...(hkIds.length > 0 ? { clientId: { notIn: hkIds } } : {}),
      },
    });
    for (const w of healthkit) {
      const clientId = w.clientId!;
      await tx.workout.upsert({
        where: { userId_clientId: { userId, clientId } },
        create: {
          userId,
          source: 'HEALTHKIT',
          kind: w.kind,
          start: w.start,
          durationMin: w.durationMin,
          activeKcal: w.activeKcal,
          clientId,
        },
        update: {
          kind: w.kind,
          start: w.start,
          durationMin: w.durationMin,
          activeKcal: w.activeKcal,
        },
      });
    }
  });

  return planned.length + healthkit.length;
}
