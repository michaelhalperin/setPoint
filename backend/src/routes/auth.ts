import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { AppleAuthError, issueSessionToken, verifyAppleIdentityToken } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { env, isProd } from '../env.js';

/** The dev sign-in shortcut is on outside production, or when explicitly enabled
 *  (e.g. a staging deploy) via ENABLE_DEV_LOGIN=true. */
const devLoginEnabled = !isProd || env.ENABLE_DEV_LOGIN === 'true';

const appleBody = z.object({ identityToken: z.string().min(1) });
const devBody = z.object({ userId: z.string().optional(), email: z.string().email().optional() });

export async function authRoutes(app: FastifyInstance): Promise<void> {
  // Sign in with Apple → SetPoint session token.
  app.post('/apple', async (req) => {
    const { identityToken } = appleBody.parse(req.body);
    if (!env.APPLE_CLIENT_ID) throw app.httpErrors.notImplemented('Sign in with Apple is not configured');

    let identity;
    try {
      identity = await verifyAppleIdentityToken(identityToken, env.APPLE_CLIENT_ID);
    } catch (err) {
      if (err instanceof AppleAuthError) throw app.httpErrors.unauthorized(err.message);
      throw err;
    }

    const user = await getPrisma().user.upsert({
      where: { appleSub: identity.sub },
      create: { appleSub: identity.sub, email: identity.email ?? null },
      update: identity.email ? { email: identity.email } : {},
    });

    return { token: issueSessionToken(user.id), userId: user.id };
  });

  // Mint a session token without Apple. Off in production unless ENABLE_DEV_LOGIN=true.
  if (devLoginEnabled) {
    app.post('/dev', async (req) => {
      const { userId, email } = devBody.parse(req.body ?? {});
      const prisma = getPrisma();
      const user = userId
        ? await prisma.user.findUniqueOrThrow({ where: { id: userId } })
        : await prisma.user.create({ data: { email: email ?? `dev+${Date.now()}@setpoint.local` } });
      return { token: issueSessionToken(user.id), userId: user.id };
    });
  }
}
