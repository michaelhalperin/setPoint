import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { getPrisma } from '../db/client.js';
import { env } from '../env.js';
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

/** The 403 message the app reads to show the invite-code screen. */
export const INVITE_REQUIRED = 'invite_required';

export const inviteOnly = (): boolean => env.INVITE_ONLY === 'true';

/**
 * Route-level guard: reads `Authorization: Bearer <session jwt>`, verifies it,
 * and stashes the user id on the request. Register as a `preHandler`.
 *
 * Also renews sessions: a token older than RENEW_AFTER_SECONDS gets a fresh one
 * back in the `x-session-token` response header, which the app stores.
 *
 * While sign-up is invite-only, a token marked pending gets a 403
 * `invite_required` — unless the account was let in since (an admin granted it),
 * in which case it's swapped for a full session here. Only pending tokens cost a
 * database read. `allowPendingInvite` opens a route to them (redeeming a code,
 * deleting the account).
 */
export function requireAuth(app: FastifyInstance, opts: { allowPendingInvite?: boolean } = {}) {
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

    if (session.pendingInvite && inviteOnly()) {
      const user = await getPrisma().user.findUnique({
        where: { id: session.userId },
        select: { accessGrantedAt: true },
      });
      if (user?.accessGrantedAt) {
        reply.header(SESSION_RENEWAL_HEADER, issueSessionToken(session.userId));
        return;
      }
      if (opts.allowPendingInvite) return;
      throw app.httpErrors.forbidden(INVITE_REQUIRED);
    }

    if (shouldRenewSession(session.issuedAt) || session.pendingInvite) {
      reply.header(SESSION_RENEWAL_HEADER, issueSessionToken(session.userId));
    }
  };
}
