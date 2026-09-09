# SetPoint backend

Node + TypeScript + Fastify. Prisma over Neon Postgres. Runs as Vercel
serverless functions; the confidence-scoring job runs on Vercel Cron.

## Stack

| Concern        | Choice                                                        |
| -------------- | ------------------------------------------------------------- |
| HTTP framework | Fastify 5 (ESM)                                               |
| DB             | Postgres on Neon, Prisma with `@prisma/adapter-neon`          |
| Runtime host   | Vercel serverless (`api/index.ts` wraps the Fastify instance) |
| Scheduler      | Vercel Cron → `POST /api/cron/score`                          |
| Validation     | zod                                                           |
| Auth           | Sign in with Apple → session JWT (milestone 2)                |

TimescaleDB is deliberately deferred: per the plan (§4) raw HRV/RHR never leaves
the device — only the derived confidence score reaches the backend — so there is
no time-series volume to justify the extension in v1.

## Local setup

```bash
pnpm install
cp .env.example .env      # already created for you with generated secrets
```

Fill in `DATABASE_URL` in `.env`:

1. Create a free project at <https://neon.tech>.
2. Connection Details → **Pooled connection** (host contains `-pooler`).
3. Paste it as `DATABASE_URL`.

Then:

```bash
pnpm --filter @setpoint/backend prisma:generate
pnpm --filter @setpoint/backend db:push     # creates tables from schema.prisma
pnpm --filter @setpoint/backend db:seed     # loads the curated staple-food list
pnpm dev
```

## Data model

`prisma/schema.prisma` (milestone 2). Grouped to match the plan:

- **Identity** — `User`, `PushToken`
- **Onboarding** (§3, §5.1) — `OnboardingProfile` (goal, mode, stats, meal times,
  quiet hours, kcal target)
- **Safety screening** (§3) — `SafetyScreening` (medical flag, SCOFF answers +
  `enforcementEnabled` gate), `DietaryRestriction` (normalized allergen tokens)
- **Ledger** (§5.5) — `Meal`
- **Biosignals** (§2, §4) — `BiosignalState` / `BiosignalReading` hold only a
  derived deviation the app pushes; raw HRV/RHR never reach the backend
- **Confidence** (§2) — `ConfidenceScore` keeps every component input for audit
  and beta tuning
- **Check-ins** (§2) — `CheckIn`, `EscalationState`, `EscalationConversation`
- **Prescription** (§2, §5.4) — `Prescription`, `PrescriptionItem` (macro
  snapshot), `FoodItem` (curated list, `tags` + `allergens` arrays)
- **Settlement** (§5.7) — `DayOutcome`

Every `userId` FK is `onDelete: Cascade` for the account-deletion requirement (§4).
The staple-food seed is `prisma/seed.ts` (~40 items).

Without `DATABASE_URL` the server still boots; `/api/health` just reports
`db: down`.

## Endpoints

| Method | Path              | Notes                                                     |
| ------ | ----------------- | -------------------------------------------------------- |
| GET    | `/`               | Service banner                                           |
| GET    | `/api/health`     | Liveness + `SELECT 1` database check                     |
| POST   | `/api/cron/score` | Runs the confidence engine. Requires the cron secret.    |

## Confidence engine (`src/engine/`)

Pure, deterministic, no model calls (plan §2, §7). `src/jobs/scoreConfidence.ts`
is the only stateful layer — it maps DB rows onto the engine types and applies
the results.

| Module           | Responsibility                                                              |
| ---------------- | -------------------------------------------------------------------------- |
| `config.ts`      | The permanent formula's tunable weights + constants                        |
| `confidence.ts`  | `computeConfidence()` — the weighted score, Smart falls back to Basic      |
| `expectedGap.ts` | per-user expected inter-meal gap from their onboarding meal times          |
| `quietHours.ts`  | timezone-aware quiet-hours window (Intl, no dependency)                    |
| `eligibility.ts` | the pre-scoring gate (enforcement, pause, back-off, quiet hours, ...)      |
| `escalation.ts`  | the defer → snooze → re-check → tier 1/2/3 → back-off state machine        |
| `inputs.ts`      | deriving `hoursSinceMeal` / `loggingSilence` / biosignal freshness        |

Weights are v1 starting values, tuned only against beta data (§8) — the formula
shape never changes. 47 unit tests: `pnpm --filter @setpoint/backend test`.

Push delivery and the check-in copy are behind interfaces (`src/push/`,
`src/managerVoice/`) with stub implementations until the APNs key (push) and
`ANTHROPIC_API_KEY` (manager's voice, milestone 5) exist.

Call the cron endpoint locally:

```bash
curl -X POST localhost:3000/api/cron/score -H "x-cron-secret: $CRON_SECRET"
```

## Deploying to Vercel

1. Import the GitHub repo in Vercel.
2. Set **Root Directory** to `backend`.
3. Add env vars (Settings → Environment Variables): `DATABASE_URL`,
   `CRON_SECRET`, `JWT_SECRET`. Leave the stubbed integration keys for later.
   When `CRON_SECRET` is set, Vercel Cron automatically sends it as
   `Authorization: Bearer <CRON_SECRET>`.
4. Deploy.

### Cron cadence

`vercel.json` currently schedules `/api/cron/score` once daily (`0 9 * * *`) —
safe on the Vercel Hobby plan. The product wants a ~15-minute cadence; when we
get there (milestone 3) we either move to a paid plan or add a GitHub Actions
scheduled workflow that hits the endpoint with the `x-cron-secret` header.

## Environment variables

| Key                                  | Needed when   | Source                                    |
| ------------------------------------ | ------------- | ----------------------------------------- |
| `DATABASE_URL`                       | now           | Neon pooled connection string             |
| `CRON_SECRET`                        | now           | generated (`openssl rand -hex 32`)        |
| `JWT_SECRET`                         | now           | generated                                 |
| `ANTHROPIC_API_KEY`                  | milestone 5   | <https://console.anthropic.com>           |
| `APNS_KEY_ID` / `APNS_TEAM_ID` / `APNS_PRIVATE_KEY` / `APNS_BUNDLE_ID` | push delivery | Apple Developer → Keys → APNs Auth Key    |
