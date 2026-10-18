import type { PrismaClient } from '@prisma/client';
import { checkInSlotAt, mealTimesOn } from '../engine/mealSchedule.js';
import { localDateISO, localWeekday, msSinceLocalMidnight, startOfLocalDay } from '../engine/time.js';
import { computePrescriptionTarget, excludedTokensFor, loadStapleFoods, prescribe } from '../solver/index.js';

/**
 * Opens a real meal check-in (with prescription) for this user, or reuses one
 * that is still open. Dev/tools only — mirrors startTalk for the sheet.
 */
export async function startCheckIn(
  prisma: PrismaClient,
  userId: string,
  now = new Date(),
): Promise<{ checkInId: string }> {
  const open = await prisma.checkIn.findFirst({
    where: {
      userId,
      status: { in: ['PENDING', 'DEFERRED'] },
      tier: { lt: 3 },
      prescription: { isNot: null },
    },
    orderBy: { createdAt: 'desc' },
    select: { id: true },
  });
  if (open) return { checkInId: open.id };

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      timezone: true,
      onboarding: {
        select: {
          breakfastMin: true,
          lunchMin: true,
          dinnerMin: true,
          weekendBreakfastMin: true,
          weekendLunchMin: true,
          weekendDinnerMin: true,
          weekendDays: true,
          dailyKcalTarget: true,
          dailyProteinTargetG: true,
          dislikedFoods: true,
          pantryTokens: true,
          prepTimeMaxMin: true,
          drinkableOk: true,
        },
      },
    },
  });
  if (!user?.onboarding) {
    throw Object.assign(new Error('onboarding required'), { statusCode: 409 });
  }

  const profile = user.onboarding;
  const times = mealTimesOn(profile, localWeekday(now, user.timezone));
  const nowMin = Math.floor(msSinceLocalMidnight(now, user.timezone) / 60_000);
  const slot = checkInSlotAt(nowMin, times) ?? 'lunch';
  const dayStart = startOfLocalDay(now, user.timezone);

  const todayMeals = await prisma.meal.findMany({
    where: { userId, loggedAt: { gte: dayStart } },
    select: { kcal: true, proteinG: true },
  });
  const consumedKcal = todayMeals.reduce((sum, m) => sum + m.kcal, 0);
  const consumedProteinG = todayMeals.reduce((sum, m) => sum + m.proteinG, 0);
  const target = computePrescriptionTarget({
    dailyKcalTarget: profile.dailyKcalTarget,
    consumedKcal,
    dailyProteinTargetG: profile.dailyProteinTargetG,
    consumedProteinG,
  });

  const [{ solverFoods, foodIdBySlug }, excludedTokens] = await Promise.all([
    loadStapleFoods(prisma),
    excludedTokensFor(prisma, userId, profile.dislikedFoods),
  ]);
  const rx = prescribe(solverFoods, {
    targetKcal: target.targetKcal,
    targetProteinG: target.targetProteinG,
    excludedTokens,
    pantryTokens: profile.pantryTokens ?? [],
    prepTimeMaxMin: profile.prepTimeMaxMin,
    preferLowFriction: true,
    preferCalorieDense: false,
    preferDrinkable: profile.drinkableOk ?? true,
  });
  if (!rx) {
    throw Object.assign(new Error('no option fits your food restrictions'), { statusCode: 409 });
  }

  const episodeKey = `dev:force:${localDateISO(now, user.timezone)}:${now.getTime()}`;
  const checkIn = await prisma.checkIn.create({
    data: {
      userId,
      tier: 2,
      status: 'PENDING',
      deliveryStatus: 'CREATED',
      message: 'Time to eat.',
      slot,
      episodeKey,
      kind: 'MEAL',
      prescription: {
        create: {
          userId,
          targetKcal: rx.targetKcal,
          targetProteinG: rx.targetProteinG,
          totalKcal: rx.totalKcal,
          totalProteinG: rx.totalProteinG,
          totalCarbsG: rx.totalCarbsG,
          totalFatG: rx.totalFatG,
          status: 'OFFERED',
          items: {
            create: rx.items.map((i) => ({
              foodItemId: foodIdBySlug.get(i.slug) ?? null,
              name: i.name,
              quantity: i.quantity,
              unit: 'serving',
              kcal: i.kcal,
              proteinG: i.proteinG,
              carbsG: i.carbsG,
              fatG: i.fatG,
            })),
          },
        },
      },
    },
  });

  return { checkInId: checkIn.id };
}
