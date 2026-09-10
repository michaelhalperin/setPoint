import type { PrismaClient } from '@prisma/client';
import type { MealImage, MealParser, ParsedMeal } from '../ai/parseMeal.js';

export class MealParsingUnavailableError extends Error {}
export class EmptyMealError extends Error {}

export type LogMealInput = {
  text?: string;
  image?: MealImage;
  loggedAt?: Date;
  /** Provide when the client already has macros (e.g. accepting a prescription). */
  macros?: { kcal: number; proteinG?: number; carbsG?: number; fatG?: number };
  prescriptionId?: string;
};

export type LogMealDeps = {
  prisma: PrismaClient;
  /** null when no AI key is configured — text/photo logging then requires explicit macros. */
  parseMeal: MealParser | null;
};

export type LoggedMeal = {
  id: string;
  loggedAt: Date;
  source: string;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
};

export type LogMealResult = {
  meal: LoggedMeal;
  parsed: ParsedMeal | null;
  /** The check-in this meal resolved, if any (logging is the "log" action, §2/§5.4). */
  resolvedCheckInId: string | null;
};

export async function logMeal(
  deps: LogMealDeps,
  userId: string,
  input: LogMealInput,
): Promise<LogMealResult> {
  const loggedAt = input.loggedAt ?? new Date();

  let parsed: ParsedMeal | null = null;
  let source: string;
  let rawInput: string | null = null;
  let parsedByAI = false;
  let parseConfidence: number | null = null;
  let macros: { kcal: number; proteinG: number; carbsG: number; fatG: number };

  if (input.macros) {
    macros = {
      kcal: Math.round(input.macros.kcal),
      proteinG: input.macros.proteinG ?? 0,
      carbsG: input.macros.carbsG ?? 0,
      fatG: input.macros.fatG ?? 0,
    };
    source = input.prescriptionId ? 'PRESCRIPTION' : 'MANUAL';
    rawInput = input.text ?? null;
  } else if (input.prescriptionId) {
    // "I ate the prescription" — log its totals as-is.
    const rx = await deps.prisma.prescription.findFirst({
      where: { id: input.prescriptionId, userId },
      select: { totalKcal: true, totalProteinG: true, totalCarbsG: true, totalFatG: true },
    });
    if (!rx) throw new EmptyMealError('prescription not found');
    macros = { kcal: rx.totalKcal, proteinG: rx.totalProteinG, carbsG: rx.totalCarbsG, fatG: rx.totalFatG };
    source = 'PRESCRIPTION';
  } else if (input.text || input.image) {
    if (!deps.parseMeal) {
      throw new MealParsingUnavailableError('AI meal parsing is not configured; send explicit macros');
    }
    parsed = await deps.parseMeal({ text: input.text, image: input.image });
    macros = { kcal: parsed.kcal, proteinG: parsed.proteinG, carbsG: parsed.carbsG, fatG: parsed.fatG };
    source = input.image ? 'PHOTO' : 'TEXT';
    rawInput = input.text ?? parsed.summary;
    parsedByAI = true;
    parseConfidence = parsed.confidence;
  } else {
    throw new EmptyMealError('provide text, an image, or macros');
  }

  const meal = await deps.prisma.meal.create({
    data: {
      userId,
      loggedAt,
      source: source as never,
      rawInput,
      parsedByAI,
      parseConfidence,
      kcal: macros.kcal,
      proteinG: macros.proteinG,
      carbsG: macros.carbsG,
      fatG: macros.fatG,
      photoUrl: input.image ? `data:${input.image.mediaType};base64,${input.image.data}` : null,
      notes: parsed?.notes ?? null,
      items: parsed?.items ?? [],
      prescriptionId: input.prescriptionId ?? null,
    },
  });

  // Resolve any open check-in — logging a meal *is* the response to it.
  const open = await deps.prisma.checkIn.findMany({
    where: { userId, status: { in: ['PENDING', 'DEFERRED'] } },
    orderBy: { createdAt: 'desc' },
  });

  let resolvedCheckInId: string | null = null;
  if (open.length > 0) {
    const ids = open.map((c) => c.id);
    await deps.prisma.checkIn.updateMany({
      where: { id: { in: ids } },
      data: { status: 'LOGGED', resolvedAt: loggedAt },
    });
    await deps.prisma.meal.update({ where: { id: meal.id }, data: { checkInId: open[0]!.id } });
    resolvedCheckInId = open[0]!.id;
  }

  if (input.prescriptionId) {
    await deps.prisma.prescription.updateMany({
      where: { id: input.prescriptionId, userId },
      data: { status: 'ACCEPTED' },
    });
  }

  // Any logged meal breaks a miss streak and resets the escalation tier.
  await deps.prisma.escalationState.upsert({
    where: { userId },
    create: { userId, consecutiveMisses: 0, currentTier: 1 },
    update: { consecutiveMisses: 0, currentTier: 1, backedOffUntil: null },
  });

  return {
    meal: {
      id: meal.id,
      loggedAt: meal.loggedAt,
      source: meal.source,
      kcal: meal.kcal,
      proteinG: meal.proteinG,
      carbsG: meal.carbsG,
      fatG: meal.fatG,
    },
    parsed,
    resolvedCheckInId,
  };
}
