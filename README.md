# SetPoint

An iOS app that actively helps people eat enough — for both mass-gain and diet
goals. It intervenes when someone is falling behind instead of passively logging.
Tone: a manager, not a punisher.

See [`app-plan-animation.md`](./app-plan-animation.md) for the full product plan.

## Repo layout

```
setPoint/
├── app-plan-animation.md   Product plan (source of truth)
├── backend/                Node + Fastify + Prisma API and confidence engine
└── ios/                    Swift/SwiftUI app (not started yet)
```

This is a pnpm workspace. Node 22+, pnpm 11+.

```bash
pnpm install
pnpm dev          # runs the backend
```

## Backend

Deployed as Vercel serverless functions + Vercel Cron, with Neon Postgres.
Details and environment setup: [`backend/README.md`](./backend/README.md).

## Build order

1. **Backend scaffold** ← done (milestone 1)
2. **Data model + staple-food seed** ← done (milestone 2)
3. Confidence engine (server-driven, quiet hours, deterministic formula)
4. Check-in delivery (Live Activity + Time Sensitive) + defer/escalation loop
5. AI logging (photo/text → macros) + manager's voice
6. Home dashboard + settlement view
7. Privacy policy, account deletion, App Store compliance
8. Closed TestFlight beta → tune weights → public launch
