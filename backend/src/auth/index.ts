import type { FastifyInstance, FastifyRequest } from 'fastify';
import { SessionTokenError, verifySessionToken } from './session.js';

export * from './session.js';
export * from './appleSignIn.js';

export type AuthedRequest = FastifyRequest & { userId: string };

/**
 * Route-level guard: reads `Authorization: Bearer <session jwt>`, verifies it,
 * and stashes the user id on the request. Register as a `preHandler`.
 */
export function requireAuth(app: FastifyInstance) {
  return async (req: FastifyRequest): Promise<void> => {
    const header = req.headers.authorization;
    const token = header?.startsWith('Bearer ') ? header.slice(7) : undefined;
    if (!token) throw app.httpErrors.unauthorized('missing bearer token');

    try {
      (req as AuthedRequest).userId = verifySessionToken(token).userId;
    } catch (err) {
      if (err instanceof SessionTokenError) throw app.httpErrors.unauthorized('invalid session token');
      throw err;
    }
  };
}
