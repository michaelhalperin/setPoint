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
| POST   | `/api/meals`      | Log a meal (bearer auth). `{text}`/`{image}` → AI-parsed; `{macros}` → as-is; `{prescriptionId}` alone → the Rx's totals. Resolves any open check-in. Returns `{ meal, parsed, resolvedCheckInId }` |
| DELETE | `/api/meals/:id`  | Undo a just-logged meal (e.g. a wrong photo parse) — `{ deleted: true }` |
| GET    | `/api/checkins/:id` | Fetch one check-in + prescription (bearer auth)          |
| POST   | `/api/checkins/:id/defer` | Snooze it — `status DEFERRED`, `deferUntil = now + 2h` (§2) |
| POST   | `/api/checkins/:id/feedback` | `{ positive }` thumbs — labeled beta signal (§8) |
| GET    | `/api/checkins/:id/conversation` | Tier-3 "let's talk" transcript — seeds the opener on first read (§2) |
| POST   | `/api/checkins/:id/conversation` | `{ message }` → the manager's reply; lands on an `outcome` (`ADJUST_PLAN` / `PAUSE_CHECKINS` / `SUGGEST_PROFESSIONAL`) then `resolved`. `PAUSE_CHECKINS` sets `escalationState.checkInsPaused` |
| POST   | `/api/push-tokens` / `DELETE /api/push-tokens/:token` | register/unregister an APNs token (`kind: alert \| live_activity_start`) |
| POST   | `/api/biosignals` | `{ hrvDeviation, rhrDeviation? }` — the app's on-device z-scores (§4) → `BiosignalState` |
| POST   | `/api/weight`     | `{ weightKg, measuredAt?, source? }` — a weigh-in. Reaching the goal flips it to `MAINTAIN` and returns fresh targets (`goalReached`) |
| GET    | `/api/weight`     | Recent `WeightEntry` rows (`?limit`, default 60) for a weight history view |
| POST   | `/api/onboarding` | Goal, stats, meal times, quiet hours, safety screening → profile + `SafetyScreening` + restrictions (bearer auth, §3, §5.1) |
| GET    | `/api/settings`   | Current profile / quiet hours / restrictions / pause / enforcement (bearer auth) |
| PATCH  | `/api/settings`   | Update quiet hours, meal times, targets, goal, `checkInsPaused`, or replace restrictions |
| DELETE | `/api/account`    | `{ "confirmation": "delete my account" }` → cascading delete + Apple token revoke (bearer auth, §4) |
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
  "today" row, a deterministic week summary, and (M16) the `weightGoal` block —
  progress toward `targetWeightKg` from the latest `WeightEntry`, pace status,
  ETA, and a `needsWeighIn` flag when the last weigh-in is over a week old

## Weight goals (`src/weight/`, `src/onboarding/`) — M16

- Onboarding captures `targetWeightKg` + `paceKgPerWeek` (unsigned; direction is
  the goal). `targets.ts` turns the pace into the daily surplus/deficit
  (`paceToKcalDelta`, ~7700 kcal/kg) and `clampPaceKgPerWeek` caps it — a diet at
  0.75 %/wk of bodyweight, a bulk at 0.5 kg/wk. `MAINTAIN` is a third goal with a
  neutral target.
- `weight/progress.ts` — pure: kg changed / remaining, fraction, `ahead`/
  `on_pace`/`behind`/`reached` vs the planned pace, ETA in weeks.
- `weight/logWeight.ts` — a weigh-in upserts a `WeightEntry`; if it reaches the
  target the goal auto-switches to `MAINTAIN` and the daily targets are recomputed
  with no deficit.
- `onboarding/recompute.ts` — `deriveTargets()`, shared by onboarding, settings
  (goal/target/pace edits re-anchor and recompute), and the auto-maintenance flip.
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
- `ai/tierThree.ts` — the bounded tier-3 "let's talk" conversation (§2). Forced
  `reply_to_user` tool call on `claude-sonnet-5`; the only outcomes are adjust
  the plan, pause check-ins, or point to professional support. A deterministic
  keyword fallback (`fallbackTierThree`) covers a missing key or any model error
- `getAnthropic()` returns null when `ANTHROPIC_API_KEY` is unset — meal logging
  then needs explicit `macros`, and the manager's voice + tier-3 use the fallback

## Auth (`src/auth/`)

Sign in with Apple (`appleSignIn.ts` — RS256 verification against Apple's JWKS,
issuer + audience checks) → a SetPoint HS256 session JWT (`session.ts`, 60-day).
`requireAuth(app)` is the route `preHandler`. `appleRevoke.ts` calls Apple's
`/auth/revoke` on account deletion (dormant until the auth-code exchange ships
and `User.appleRefreshToken` is populated).

## Onboarding & account (`src/onboarding/`, `src/account/`)

- `scoff.ts` (pure) — SCOFF scoring (≥2 → flagged) and `deriveEnforcement()`, the
  single gate the engine reads
- `targets.ts` (pure) — Mifflin–St Jeor RMR → calorie target (goal-adjusted),
  protein target per kg
- `onboard.ts` — one transactional write of `OnboardingProfile` +
  `SafetyScreening` + `DietaryRestriction`s + `EscalationState`
- `settings.ts` — read/patch the same, restrictions replaced as a set
- `account/deleteAccount.ts` — Apple revoke (best-effort) then `user.delete`
  (cascades everywhere)

See [`COMPLIANCE.md`](./COMPLIANCE.md) for the App Store / privacy checklist.

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

1. **[vercel.com/new](https://vercel.com/new)** → import `michaelhalperin/setPoint`.
2. **Root Directory** → `backend`. Framework preset: **Other**. Leave Build /
   Install / Output commands on their defaults — `vercel-build` runs
   `prisma generate` and `postinstall` covers it too.
3. **Environment Variables** (Production): copy from `backend/.env` —
   `DATABASE_URL`, `CRON_SECRET`, `JWT_SECRET`, `ANTHROPIC_API_KEY`. Add the
   `APNS_*` / `APPLE_*` keys when you have them. Optionally `ENABLE_DEV_LOGIN=true`
   on a Preview environment so `POST /api/auth/dev` works there.
4. **Deploy.** Every push to `main` redeploys.
5. Point the app at it: set `SETPOINT_API_BASE_URL` in the iOS Run scheme, and
   change the non-simulator default in `ios/SetPoint/Networking/APIConfig.swift`.

Vercel Cron invokes the endpoints with a **GET** and
`Authorization: Bearer <CRON_SECRET>` (both cron routes accept GET and POST).

### Cron cadence

`vercel.json` schedules `/api/cron/score` and `/api/cron/settle` once daily —
the Hobby-plan limit (2 jobs). For the ~15-minute scoring cadence the product
wants, add a GitHub Actions scheduled workflow that hits
`POST /api/cron/score` with the `x-cron-secret` header (Actions cron minimum is
5 min, free for the repo), or move to Vercel Pro.

## Environment variables

| Key                                  | Needed when   | Source                                    |
| ------------------------------------ | ------------- | ----------------------------------------- |
| `DATABASE_URL`                       | now           | Neon pooled connection string             |
| `CRON_SECRET`                        | now           | generated (`openssl rand -hex 32`)        |
| `JWT_SECRET`                         | now           | generated                                 |
| `ANTHROPIC_API_KEY`                  | now           | <https://console.anthropic.com>           |
| `ENABLE_DEV_LOGIN`                   | staging only  | `"true"` keeps `/api/auth/dev` on a deploy |
| `APNS_KEY_ID` / `APNS_TEAM_ID` / `APNS_PRIVATE_KEY` / `APNS_BUNDLE_ID` | push delivery | Apple Developer → Keys → APNs Auth Key    |
| `APPLE_CLIENT_ID` (+ `APPLE_TEAM_ID` / `APPLE_KEY_ID` / `APPLE_PRIVATE_KEY`) | real auth | Apple Developer → Identifiers / Keys       |
