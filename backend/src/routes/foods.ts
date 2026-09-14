import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { fetchOpenFoodFacts, lookupBarcode, normalizeBarcode } from '../foods/barcode.js';

const params = z.object({
  code: z.string().min(1).max(32),
});

export async function foodRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  // Proxies Open Food Facts and caches the result. 404 when the barcode is unknown
  // so the app can fall back to typing.
  app.get('/barcode/:code', async (req) => {
    const { code: raw } = params.parse(req.params);
    if (!normalizeBarcode(raw)) throw app.httpErrors.badRequest('barcode must be 8–14 digits');
    let food;
    try {
      food = await lookupBarcode({ prisma: getPrisma(), fetchProduct: fetchOpenFoodFacts }, raw);
    } catch (err) {
      req.log.warn({ err }, 'barcode lookup failed');
      throw app.httpErrors.serviceUnavailable('barcode lookup is unavailable right now');
    }
    if (!food) throw app.httpErrors.notFound('unknown barcode');
    return { food };
  });
}
