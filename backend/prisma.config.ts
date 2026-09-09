import 'dotenv/config';
import { defineConfig } from 'prisma/config';

// When a Prisma config file is present, Prisma no longer auto-loads `.env` —
// hence the `dotenv/config` import above so `DATABASE_URL` is available to
// `prisma db push` / `migrate` / `generate`.
export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    seed: 'tsx prisma/seed.ts',
  },
});
