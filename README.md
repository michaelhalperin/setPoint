# SetPoint

An iOS app that helps people who unintentionally under-eat keep a minimum
fueling rhythm. Meal behavior decides whether a check-in is due. Fresh HRV/RHR,
when enabled, may adjust confidence on an already-due check-in — it never
independently diagnoses under-fueling.

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
