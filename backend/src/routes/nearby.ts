import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { NEARBY_VENUES, sampleVenues } from '../data/nearbyVenues.js';
import { getPrisma } from '../db/client.js';
import { env } from '../env.js';
import { isFlagOnForUser } from '../flags/index.js';
import { rankNearby } from '../nearby/index.js';
import { track } from '../analytics/events.js';

const query = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
  kcal: z.coerce.number().int().min(100).max(3000),
});

export async function nearbyRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  // Places near the user with dishes sized to what they still need, minus what
  // they avoid. The app opens Wolt on a dish; nothing is ordered from here.
  app.get('/', async (req) => {
    const { lat, lng, kcal } = query.parse(req.query);
    if (!(await isFlagOnForUser(getPrisma(), (req as AuthedRequest).userId, 'order_nearby'))) {
      throw app.httpErrors.notFound('order nearby is off');
    }
    const restrictions = await getPrisma().dietaryRestriction.findMany({
      where: { userId: (req as AuthedRequest).userId, isHardExclusion: true },
      select: { token: true },
    });
    await track(getPrisma(), (req as AuthedRequest).userId, 'order_nearby_opened');
    const venues = env.NEARBY_SAMPLE_VENUES === 'true' ? [...NEARBY_VENUES, ...sampleVenues(lat, lng)] : NEARBY_VENUES;
    return {
      gapKcal: kcal,
      sample: env.NEARBY_SAMPLE_VENUES === 'true',
      venues: rankNearby(venues, { lat, lng, gapKcal: kcal, avoid: new Set(restrictions.map((r) => r.token)) }),
    };
  });
}
