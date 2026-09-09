import 'dotenv/config';
import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),

  // Optional at boot so the server still starts for local scaffolding / review.
  // Anything that actually touches the DB throws a clear error if it's missing.
  // An empty string in .env is treated as "unset".
  DATABASE_URL: z.preprocess((v) => (v === '' ? undefined : v), z.string().min(1).optional()),

  CRON_SECRET: z.string().min(1),
  JWT_SECRET: z.string().min(1),

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
  console.error('Invalid environment variables:\n' + lines.join('\n'));
  console.error('\nCopy backend/.env.example to backend/.env and fill it in.');
  process.exit(1);
}

export const env = parsed.data;
export const isProd = env.NODE_ENV === 'production';
export const isDev = env.NODE_ENV === 'development';
