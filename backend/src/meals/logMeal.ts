import type { PrismaClient } from '@prisma/client';
import type { MealImage, MealParser, ParsedMeal } from '../ai/parseMeal.js';
import type { AiUsageKind } from '../ai/quota.js';
import { lookupBarcode, macrosForServings, type BarcodeLookupDeps } from '../foods/barcode.js';
import { mealItemsSchema, type MealItemInput } from './items.js';
import { captureError } from '../observability/sentry.js';
import { queuePhotoDeletion } from '../photos/cleanup.js';
import type { PhotoStore } from '../photos/store.js';

export class MealParsingUnavailableError extends Error {}
export class EmptyMealError extends Error {}

export type LogMealInput = {
  text?: string;
  image?: MealImage;
  loggedAt?: Date;
  /** Provide when the client already has macros (e.g. accepting a prescription). */
  macros?: { kcal: number; proteinG?: number; carbsG?: number; fatG?: number };
  prescriptionId?: string;
  /** Log a named plate as-is — never AI-parsed. */
  savedMealId?: string;
  /** Open Food Facts / cached barcode. Pair with `servings`. Never AI-parsed. */
  barcode?: string;
  /** Multiplier of the product's serving size. Defaults to 1. */
  servings?: number;
  /** The app's id for this log attempt. A repeat returns the stored meal, unchanged. */
  clientId?: string;
};

export type LogMealDeps = {
  prisma: PrismaClient;
  /** null when no AI key is configured — text/photo logging then requires explicit macros. */
  parseMeal: MealParser | null;
  /** Where meal photos are kept. Null/absent: the photo is parsed but not stored. */
  photos?: PhotoStore | null;
  /** Charges one AI call to the user; throws AiQuotaExceededError when over the limit. */
  quota?: (kind: AiUsageKind) => Promise<void>;
  /** Open Food Facts + cache. Required when logging `barcode`. */
  barcode?: Pick<BarcodeLookupDeps, 'fetchProduct' | 'now'>;
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
  if (loggedAt.getTime() > Date.now() + 5 * 60_000) {
    throw new EmptyMealError('loggedAt cannot be in the future');
  }

  // A retry of a log that already landed (offline queue, dropped response):
  // return it before parsing again, so it's neither duplicated nor re-charged.
  if (input.clientId) {
    const existing = await findByClientId(deps.prisma, userId, input.clientId);
    if (existing) return existing;
  }

  let parsed: ParsedMeal | null = null;
  let source: string;
  let rawInput: string | null = null;
  let parsedByAI = false;
  let parseConfidence: number | null = null;
  let macros: { kcal: number; proteinG: number; carbsG: number; fatG: number };
  let items: MealItemInput[] = [];
  let notes: string | null = null;
  let savedMealId: string | null = null;

  if (input.savedMealId) {
    const saved = await deps.prisma.savedMeal.findFirst({ where: { id: input.savedMealId, userId } });
    if (!saved) throw new EmptyMealError('saved meal not found');
    macros = { kcal: saved.kcal, proteinG: saved.proteinG, carbsG: saved.carbsG, fatG: saved.fatG };
    items = mealItemsSchema.catch([]).parse(saved.items);
    source = 'SAVED';
    rawInput = saved.name;
    savedMealId = saved.id;
  } else if (input.barcode) {
    const food = await lookupBarcode(
      { prisma: deps.prisma, fetchProduct: deps.barcode?.fetchProduct ?? (async () => null), now: deps.barcode?.now },
      input.barcode,
    );
    if (!food) throw new EmptyMealError('unknown barcode');
    const servings = input.servings && input.servings > 0 ? input.servings : 1;
    const portion = macrosForServings(food, servings);
    macros = { kcal: portion.kcal, proteinG: portion.proteinG, carbsG: portion.carbsG, fatG: portion.fatG };
    // No serving size on the label → the portion is per 100 g, so say grams rather than "servings".
    const qty = food.servingG && food.servingG > 0
      ? servings === 1 ? '1 serving' : `${servings} servings`
      : `${Math.round(portion.grams)} g`;
    items = [
      {
        name: food.name,
        quantity: qty,
        kcal: portion.kcal,
        proteinG: portion.proteinG,
        carbsG: portion.carbsG,
        fatG: portion.fatG,
      },
    ];
    source = 'BARCODE';
    rawInput = food.name;
    notes = food.brand ? `${food.brand} · ${food.code}` : food.code;
  } else if (input.macros) {
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
    await deps.quota?.('meal_parse');
    parsed = await deps.parseMeal({ text: input.text, image: input.image });
    macros = { kcal: parsed.kcal, proteinG: parsed.proteinG, carbsG: parsed.carbsG, fatG: parsed.fatG };
    source = input.image ? 'PHOTO' : 'TEXT';
    rawInput = input.text ?? parsed.summary;
    parsedByAI = true;
    parseConfidence = parsed.confidence;
    items = parsed.items ?? [];
    notes = parsed.notes ?? null;
  } else {
    throw new EmptyMealError('provide text, an image, macros, a saved meal, or a barcode');
  }

  // The photo goes to object storage — never inline in Postgres.
  const photoKey = input.image ? await storePhoto(deps.photos ?? null, userId, input.image) : null;

  let meal;
  try {
    meal = await deps.prisma.meal.create({
      data: {
        userId,
        clientId: input.clientId ?? null,
        loggedAt,
        source: source as never,
        rawInput,
        parsedByAI,
        parseConfidence,
        kcal: macros.kcal,
        proteinG: macros.proteinG,
        carbsG: macros.carbsG,
        fatG: macros.fatG,
        photoKey,
        notes: notes ?? parsed?.notes ?? null,
        items: items.length > 0 ? items : (parsed?.items ?? []),
        parseQuality: parsed?.quality ?? null,
        prescriptionId: input.prescriptionId ?? null,
      },
    });
  } catch (err) {
    // The meal wasn't stored here, so neither should its photo be.
    if (photoKey) await queuePhotoDeletion(deps.prisma, { kind: 'object', key: photoKey }, err);
    // Two copies of the same attempt raced; the other one won.
    const existing =
      input.clientId && isUniqueViolation(err) ? await findByClientId(deps.prisma, userId, input.clientId) : null;
    if (existing) return existing;
    throw err;
  }

  // Resolve open check-ins except an active tier-3 conversation — logging a
  // meal must not silently close that talk.
  const open = await deps.prisma.checkIn.findMany({
    where: { userId, status: { in: ['PENDING', 'DEFERRED'] }, tier: { lt: 3 } },
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

  if (savedMealId) {
    const saved = await deps.prisma.savedMeal.findFirst({ where: { id: savedMealId, userId } });
    if (saved) {
      await deps.prisma.savedMeal.update({
        where: { id: savedMealId },
        data: { useCount: saved.useCount + 1, lastUsedAt: loggedAt },
      });
    }
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

async function findByClientId(prisma: PrismaClient, userId: string, clientId: string): Promise<LogMealResult | null> {
  const meal = await prisma.meal.findUnique({ where: { userId_clientId: { userId, clientId } } });
  if (!meal) return null;
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
    parsed: null,
    resolvedCheckInId: meal.checkInId,
  };
}

function isUniqueViolation(err: unknown): boolean {
  return typeof err === 'object' && err !== null && (err as { code?: unknown }).code === 'P2002';
}

async function storePhoto(photos: PhotoStore | null, userId: string, image: MealImage): Promise<string | null> {
  if (!photos) return null;
  try {
    return await photos.put(userId, Buffer.from(image.data, 'base64'), image.mediaType);
  } catch (err) {
    // A storage hiccup must not lose the meal itself — keep it without the photo.
    console.error('[photos] upload failed; logging the meal without its photo', err);
    captureError(err, { userId, tags: { area: 'photos' } });
    return null;
  }
}
