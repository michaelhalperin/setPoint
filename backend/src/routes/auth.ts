import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { InviteRejectedError, redeemInvite } from '../access/invites.js';
import {
  AppleAuthError,
  inviteOnly,
  issueSessionToken,
  requireAuth,
  verifyAppleIdentityToken,
  type AuthedRequest,
} from '../auth/index.js';
import { exchangeAppleAuthorizationCode } from '../auth/appleToken.js';
import { getPrisma } from '../db/client.js';
import { env, isProd } from '../env.js';
import { track } from '../analytics/events.js';

/** The dev sign-in shortcut is on outside production, or when explicitly enabled
 *  (e.g. a staging deploy) via ENABLE_DEV_LOGIN=true. */
const devLoginEnabled = !isProd || env.ENABLE_DEV_LOGIN === 'true';

const appleBody = z.object({
  identityToken: z.string().min(1),
  authorizationCode: z.string().min(1).max(4000).optional(),
  displayName: z.string().trim().min(1).max(80).optional(),
});
const inviteBody = z.object({ code: z.string().min(1).max(64) });
const devBody = z.object({
  userId: z.string().optional(),
  email: z.string().email().optional(),
  displayName: z.string().trim().min(1).max(80).optional(),
});

/** A new account is let in at once unless sign-up is invite-only. */
const newAccountAccess = (): Date | null => (inviteOnly() ? null : new Date());

/** The session for a signed-in user, and whether they still need an invite code. */
function sessionFor(user: { id: string; accessGrantedAt: Date | null }) {
  const needsInvite = inviteOnly() && !user.accessGrantedAt;
  return { token: issueSessionToken(user.id, { pendingInvite: needsInvite }), userId: user.id, needsInvite };
}

export async function authRoutes(app: FastifyInstance): Promise<void> {
  // Sign in with Apple → SetPoint session token.
  app.post('/apple', async (req) => {
    const { identityToken, authorizationCode, displayName } = appleBody.parse(req.body);
    if (!env.APPLE_CLIENT_ID) throw app.httpErrors.notImplemented('Sign in with Apple is not configured');

    let identity;
    try {
      identity = await verifyAppleIdentityToken(identityToken, env.APPLE_CLIENT_ID);
    } catch (err) {
      if (err instanceof AppleAuthError) {
        req.log.warn({ reason: err.message }, 'apple identity token rejected');
        throw app.httpErrors.unauthorized(err.message);
      }
      throw err;
    }

    let appleRefreshToken: string | undefined;
    if (authorizationCode) {
      try {
        const tokens = await exchangeAppleAuthorizationCode(authorizationCode);
        appleRefreshToken = tokens.refreshToken ?? undefined;
      } catch (err) {
        req.log.warn({ err }, 'apple authorization-code exchange failed');
      }
    }

    const user = await getPrisma().user.upsert({
      where: { appleSub: identity.sub },
      create: {
        appleSub: identity.sub,
        email: identity.email ?? null,
        displayName: displayName ?? null,
        appleRefreshToken,
        accessGrantedAt: newAccountAccess(),
      },
      update: {
        ...(identity.email ? { email: identity.email } : {}),
        ...(displayName ? { displayName } : {}),
        ...(appleRefreshToken ? { appleRefreshToken } : {}),
      },
    });

    await track(getPrisma(), user.id, 'signed_up', undefined, { dedupeKey: `signed_up:${user.id}` });
    return sessionFor(user);
  });

  // Redeem an invite code: lets a pending account in (or moves a member into the
  // code's group) and returns a full session. Under /api/auth so the sign-in
  // rate limit also slows code guessing.
  app.post('/invite', { preHandler: requireAuth(app, { allowPendingInvite: true }) }, async (req) => {
    const { code } = inviteBody.parse(req.body);
    const userId = (req as AuthedRequest).userId;
    try {
      const { group, role } = await redeemInvite(getPrisma(), userId, code);
      await track(getPrisma(), userId, 'invite_redeemed', group ? { group } : undefined);
      return { token: issueSessionToken(userId), userId, group, role };
    } catch (err) {
      if (err instanceof InviteRejectedError) throw app.httpErrors.badRequest('invite_invalid');
      throw err;
    }
  });

  // Mint a session token without Apple. Off in production unless ENABLE_DEV_LOGIN=true.
  if (devLoginEnabled) {
    app.post('/dev', async (req) => {
      const { userId, email, displayName } = devBody.parse(req.body ?? {});
      const prisma = getPrisma();
      const user = userId
        ? await prisma.user.findUniqueOrThrow({ where: { id: userId } })
        : await prisma.user.create({
            data: {
              email: email ?? `dev+${Date.now()}@setpoint.local`,
              displayName: displayName ?? null,
              accessGrantedAt: newAccountAccess(),
            },
          });
      await track(prisma, user.id, 'signed_up', undefined, { dedupeKey: `signed_up:${user.id}` });
      return sessionFor(user);
    });
  }
}
