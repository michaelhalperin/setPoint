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
| POST   | `/api/auth/apple` | Apple identity token → session JWT (501 until `APPLE_CLIENT_ID` is set) |
| POST   | `/api/auth/dev`   | Non-production only — mint a session JWT for testing      |
| POST   | `/api/meals`      | Log a meal (bearer auth). `{text}`/`{image}` → AI-parsed; `{macros}` → stored as-is. Resolves any open check-in |
| GET    | `/api/home`       | Home dashboard — running ledger, goal framing, manager's note, active check-in (bearer auth, §5.2) |
| GET    | `/api/settlement` | Last 7 settled days + today's live projection + week summary (bearer auth, §5.7) |
| POST   | `/api/cron/score` | Runs the confidence engine. Requires the cron secret.    |
| POST   | `/api/cron/settle`| Writes yesterday's `DayOutcome` for every user. Requires the cron secret. |

## Dashboard (`src/dashboard/`)

- `classify.ts` — pure: `classifyDay()` (settled day → ON_TRACK/UNDER/OVER/MISSED),
  `homeFraming()` (§5.2 — the accent and CTA are reserved for under-eating and
  apply regardless of goal; going over is quiet and neutral)
- `home.ts` — `buildHome()`: today's ledger vs. target, framing, the manager's
  note, and any open check-in with its prescription
- `settlement.ts` — `buildSettlement()`: the `DayOutcome` window plus a live
  "today" row and a deterministic week summary
- `jobs/settleDay.ts` — the daily job (`POST /api/cron/settle`): idempotent
  upsert of the previous local day's `DayOutcome`, summary line via the manager's
  voice

## AI (`src/ai/`, `src/managerVoice/`)

Model choice per plan §7: meal parsing runs constantly → `claude-haiku-4-5`;
manager's-voice copy runs rarely → `claude-sonnet-5`.

- `ai/parseMeal.ts` — free text or a photo → macros via a forced `record_meal`
  tool call, then a zod pass that coerces/clamps the model's numbers
- `managerVoice/ai.ts` — one-sentence check-in copy with tone guardrails (§6, and
  §3: nothing may read as shaming); **any** failure falls back to deterministic copy
- `getAnthropic()` returns null when `ANTHROPIC_API_KEY` is unset — meal logging
  then needs explicit `macros`, and the manager's voice uses the fallback

## Auth (`src/auth/`)

Sign in with Apple (`appleSignIn.ts` — RS256 verification against Apple's JWKS,
issuer + audience checks) → a SetPoint HS256 session JWT (`session.ts`, 60-day).
`requireAuth(app)` is the route `preHandler`. The full token-exchange /
account-linking flow is a later milestone.

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

The check-in copy is behind an interface (`src/managerVoice/`) with a
deterministic stub until `ANTHROPIC_API_KEY` exists (milestone 5).

## Prescription solver (`src/solver/`)

A constraint solver over the curated staple foods — never an LLM (plan §2, §7).

| Module          | Responsibility                                                          |
| --------------- | --------------------------------------------------------------------- |
| `exclusions.ts` | hard filter: allergens, lifestyle diets, name matches ("beef", ...)    |
| `targets.ts`    | day's remaining gap → one meal-sized `targetKcal` / `targetProteinG`   |
| `prescribe.ts`  | bounded search over 1–3 foods × 1–3 servings; scores calorie fit, protein, fewer items, no-cook; deterministic tie-break |

The job attaches a `Prescription` + `PrescriptionItem`s to every fired check-in
and the directive line ("2× Hard-boiled eggs + Banana") goes into the push body.
Staple data lives in `src/data/stapleFoods.ts` (seed and solver share it).

## Push delivery (`src/push/`)

`createPushSender()` returns a real APNs sender when `APNS_KEY_ID`,
`APNS_TEAM_ID`, `APNS_PRIVATE_KEY` and `APNS_BUNDLE_ID` are all set, otherwise
the stub. `apns.ts` is a minimal token-auth HTTP/2 client (no dependency) — it
sends the check-in as a **Time Sensitive** alert (not a critical alert, per §2)
that deep-links to `setpoint://check-in/<id>`.

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
