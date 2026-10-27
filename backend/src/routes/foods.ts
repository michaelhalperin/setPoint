import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { getAnthropic } from '../ai/client.js';
import { createMealParser, MealParseError } from '../ai/parseMeal.js';
import { consumeAiQuota } from '../ai/quota.js';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { fetchOpenFoodFacts, lookupBarcode, normalizeBarcode, saveBarcodeFood, toBarcodeFoodView } from '../foods/barcode.js';
import { searchCatalog } from '../foods/catalog.js';
import { createLabelReader } from '../foods/label.js';
import { fetchUsdaBranded } from '../foods/usdaBranded.js';
import { userLang } from '../i18n/user.js';
import { PHOTO_BODY_LIMIT } from '../http/limits.js';

const params = z.object({
  code: z.string().min(1).max(32),
});

const labelBody = z.object({
  image: z.object({
    data: z.string().min(1),
    mediaType: z.enum(['image/jpeg', 'image/png', 'image/webp', 'image/gif']),
  }),
});

const searchQuery = z.object({
  q: z.string().min(1).max(80),
});

/** Most foods one typed line can come back as ("rice and chicken"). */
const ESTIMATE_MAX_ITEMS = 6;

const estimateBody = z.object({
  text: z.string().trim().min(1).max(200),
});

export async function foodRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  // "bread", "2 eggs": the foods with a portion and macros, so nobody guesses numbers.
  // Nothing is logged; the app adds the items to the plate being edited.
  app.post('/estimate', async (req) => {
    const userId = (req as AuthedRequest).userId;
    const { text } = estimateBody.parse(req.body);
    const client = getAnthropic();
    if (!client) throw app.httpErrors.serviceUnavailable('food estimates are unavailable right now');
    const prisma = getPrisma();
    await consumeAiQuota(prisma, userId, 'meal_parse');
    try {
      const parsed = await createMealParser(client)({ text, lang: await userLang(prisma, userId) });
      const items = (parsed.items ?? []).slice(0, ESTIMATE_MAX_ITEMS);
      if (items.length === 0) throw app.httpErrors.unprocessableEntity('could not read a food from that');
      return { items };
    } catch (err) {
      if (err instanceof MealParseError) throw app.httpErrors.unprocessableEntity('could not read a food from that');
      throw err;
    }
  });

  // USDA catalog (Foundation + SR Legacy), imported into CatalogFood.
  app.get('/search', async (req) => {
    const { q } = searchQuery.parse(req.query);
    const foods = await searchCatalog({ prisma: getPrisma() }, q);
    return { foods };
  });

  // Open Food Facts, then USDA branded foods, cached. 404 when no source knows the
  // barcode, so the app can offer a label photo or typing.
  app.get('/barcode/:code', async (req) => {
    const { code: raw } = params.parse(req.params);
    if (!normalizeBarcode(raw)) throw app.httpErrors.badRequest('barcode must be 8–14 digits');
    let food;
    try {
      food = await lookupBarcode(
        { prisma: getPrisma(), fetchProduct: fetchOpenFoodFacts, fetchFallback: fetchUsdaBranded },
        raw,
      );
    } catch (err) {
      req.log.warn({ err }, 'barcode lookup failed');
      throw app.httpErrors.serviceUnavailable('barcode lookup is unavailable right now');
    }
    if (!food) throw app.httpErrors.notFound('unknown barcode');
    return { food };
  });

  // A barcode no database knows: read the photographed label and keep it under
  // that code, so the next scan — anyone's — finds it.
  app.post('/barcode/:code/label', { bodyLimit: PHOTO_BODY_LIMIT }, async (req, reply) => {
    const userId = (req as AuthedRequest).userId;
    const { code: raw } = params.parse(req.params);
    const code = normalizeBarcode(raw);
    if (!code) throw app.httpErrors.badRequest('barcode must be 8–14 digits');
    const { image } = labelBody.parse(req.body);
    const client = getAnthropic();
    if (!client) throw app.httpErrors.serviceUnavailable('label reading is unavailable right now');

    const prisma = getPrisma();
    // Fill gaps only: a known product isn't rewritten from one user's photo.
    const existing = await prisma.barcodeFood.findUnique({ where: { code } });
    if (existing) return { food: toBarcodeFoodView(existing) };
    await consumeAiQuota(prisma, userId, 'label_read');
    let facts;
    try {
      facts = await createLabelReader(client)(image);
    } catch (err) {
      req.log.warn({ err }, 'label read failed');
      throw app.httpErrors.serviceUnavailable('label reading is unavailable right now');
    }
    if (!facts) return reply.code(422).send({ error: 'label_unreadable', message: 'Couldn’t read that label.' });
    req.log.info({ code, userId }, 'barcode added from label');
    return { food: toBarcodeFoodView(await saveBarcodeFood(prisma, code, facts, new Date())) };
  });
}
