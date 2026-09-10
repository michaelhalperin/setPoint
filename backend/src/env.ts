import 'dotenv/config';
import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  // Only used by the local server. Vercel sets PORT to "" for functions, so be
  // forgiving: any non-positive / unparseable value falls back to 3000.
  PORT: z.coerce.number().int().positive().catch(3000),

  // Optional at boot so the server still starts for local scaffolding / review.
  // Anything that actually touches the DB throws a clear error if it's missing.
  // An empty string in .env is treated as "unset".
  DATABASE_URL: z.preprocess((v) => (v === '' ? undefined : v), z.string().min(1).optional()),

  CRON_SECRET: z.string().min(1),
  JWT_SECRET: z.string().min(1),

  // Guards GET /api/admin/* (beta metrics). Falls back to CRON_SECRET if unset.
  ADMIN_SECRET: z.string().default(''),

  // Shown in the privacy policy / terms footer and the app's support link.
  SUPPORT_EMAIL: z.string().default('support@setpoint.app'),

  // Meal-photo object storage — any S3-compatible bucket (Cloudflare R2
  // recommended). When unset, photos are still parsed by the AI but not kept.
  PHOTO_BUCKET: z.string().default(''),
  PHOTO_S3_ENDPOINT: z.string().default(''),
  PHOTO_S3_REGION: z.string().default('auto'),
  PHOTO_S3_ACCESS_KEY_ID: z.string().default(''),
  PHOTO_S3_SECRET_ACCESS_KEY: z.string().default(''),

  // Error reporting (Sentry). No-op when SENTRY_DSN is unset.
  SENTRY_DSN: z.string().default(''),
  SENTRY_ENVIRONMENT: z.string().default(''),

  // Set to "true" to keep POST /api/auth/dev available on a production deploy
  // (staging only — never on the real production environment).
  ENABLE_DEV_LOGIN: z.string().default(''),

  // Sign in with Apple — the app's client id (bundle id or services id).
  APPLE_CLIENT_ID: z.string().default(''),
  // Sign in with Apple key material (for the client secret used by /auth/revoke).
  APPLE_TEAM_ID: z.string().default(''),
  APPLE_KEY_ID: z.string().default(''),
  APPLE_PRIVATE_KEY: z.string().default(''),

  // Stubbed integrations — blank until their milestone.
  ANTHROPIC_API_KEY: z.string().default(''),
  APNS_KEY_ID: z.string().default(''),
  APNS_TEAM_ID: z.string().default(''),
  APNS_BUNDLE_ID: z.string().default('com.setpoint.app'),
  APNS_PRIVATE_KEY: z.string().default(''),
});

const parsed = schema.safeParse(process.env);

if (!parsed.success) {
  const lines = parsed.error.issues.map((i) => `  • ${i.path.join('.') || '(root)'}: ${i.message}`);
  const message =
    'Invalid environment variables:\n' +
    lines.join('\n') +
    '\n(Set these in Vercel → Project → Settings → Environment Variables, or backend/.env locally.)';
  console.error(message);
  // Throw rather than process.exit so the reason surfaces in serverless logs.
  throw new Error(message);
}

export const env = parsed.data;
export const isProd = env.NODE_ENV === 'production';
export const isDev = env.NODE_ENV === 'development';
