# SetPoint

An iOS app for people who train and can't eat enough. It closes the daily gap:
a check-in when a meal is skipped or too light for where the day should be, a
one-tap calorie-dense top-up after a small meal, and one evening check-in when
the day is still short. Meal behavior decides when a check-in is due
(`backend/src/engine/mealSchedule.ts` + `gap.ts`). Fresh HRV/RHR, when enabled,
may adjust confidence on an already-due check-in — it never independently
diagnoses under-fueling.

Meal check-ins, top-ups and the evening close are free. A subscription
(`SUBSCRIPTION_GATE=true`) adds training check-ins and calendar-aware timing.

See [`BETA.md`](./BETA.md) for release gates and [`backend/COMPLIANCE.md`](./backend/COMPLIANCE.md)
for privacy and App Store notes.

## Repo layout

```
setPoint/
├── BETA.md                 Closed-beta gates and stop conditions
├── backend/                Node + Fastify + Prisma API and scoring engine
└── ios/                    Swift/SwiftUI app (XcodeGen project)
```

This is a pnpm workspace. Node 22+, pnpm 11+.

```bash
pnpm install
pnpm dev          # runs the backend
```

## Backend

Deployed as Vercel serverless functions + a production scheduler hitting
`POST /api/cron/score`, with GitHub Actions as a monitored fallback.
Postgres schema changes go through `prisma migrate deploy` (not `db push`).
Details: [`backend/README.md`](./backend/README.md).

## iOS

XcodeGen project. See [`ios/README.md`](./ios/README.md).
