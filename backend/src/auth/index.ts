import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import {
  SESSION_RENEWAL_HEADER,
  SessionTokenError,
  issueSessionToken,
  shouldRenewSession,
  verifySessionToken,
} from './session.js';

export * from './session.js';
export * from './appleSignIn.js';

export type AuthedRequest = FastifyRequest & { userId: string };

/**
 * Route-level guard: reads `Authorization: Bearer <session jwt>`, verifies it,
 * and stashes the user id on the request. Register as a `preHandler`.
 *
 * Also renews sessions: a token older than RENEW_AFTER_SECONDS gets a fresh one
 * back in the `x-session-token` response header, which the app stores.
 */
export function requireAuth(app: FastifyInstance) {
  return async (req: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const header = req.headers.authorization;
    const token = header?.startsWith('Bearer ') ? header.slice(7) : undefined;
    if (!token) throw app.httpErrors.unauthorized('missing bearer token');

    let session: ReturnType<typeof verifySessionToken>;
    try {
      session = verifySessionToken(token);
    } catch (err) {
      if (err instanceof SessionTokenError) throw app.httpErrors.unauthorized('invalid session token');
      throw err;
    }

    (req as AuthedRequest).userId = session.userId;
    if (shouldRenewSession(session.issuedAt)) {
      reply.header(SESSION_RENEWAL_HEADER, issueSessionToken(session.userId));
    }
  };
}
