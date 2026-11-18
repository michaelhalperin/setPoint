import type { FastifyInstance } from 'fastify';
import { getSwitches, readMaintenance, readVersionGate } from '../admin2/store.js';
import { getPrisma } from '../db/client.js';

/**
 * What the app reads at launch, with no sign-in: the version gate, the maintenance notice and
 * the two switches it should explain (AI, experts). Set from the admin's Control screen.
 */
export async function appConfigRoutes(app: FastifyInstance): Promise<void> {
  app.get('/', async (_req, reply) => {
    const prisma = getPrisma();
    const [version, maintenance, switches] = await Promise.all([
      readVersionGate(prisma),
      readMaintenance(prisma),
      getSwitches(prisma),
    ]);
    reply.header('cache-control', 'public, max-age=30');
    return {
      minVersion: version.min,
      latestVersion: version.latest,
      maintenance: maintenance.active ? { en: maintenance.en, he: maintenance.he } : null,
      ai: switches.ai,
      experts: switches.experts,
    };
  });
}
