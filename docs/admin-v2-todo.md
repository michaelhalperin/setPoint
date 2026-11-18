# Admin dashboard v2 — shared todo

Legend: 🤖 = Claude, 🧑 = Michael. `[ ]` open · `[x]` done.
Rule: nothing under "Build" starts until the artboard (phase 0) is approved.

## Phase 0 — Design (before any code)
- [x] 🤖 Audit what /admin has today (routes, models)
- [x] 🤖 Gap list: test / control / check / manage
- [x] 🤖 Artboard artifact of the new UI (6 screens: Overview, Test lab, Control, People + view-as, Health + alerts, Food catalog) — https://claude.ai/artifact/RJAz3UDSdk97PXbfTSygcE
- [x] 🧑 Review the artboard: pick/kill screens, give notes
- [x] 🤖 Revise artboard from notes
- [x] 🧑 Sign off: "build it"

## Phase 1 — Test lab (highest value)
- [x] 🤖 Backend: run-now endpoints for score / settle / check-in send / weigh-in reminder
- [x] 🤖 Backend: simulate day/time for one user (sandboxed, reversible)
- [x] 🤖 Backend: solver dry-run (profile in → meals out)
- [x] 🤖 Backend: broadcast push to a segment (preview count, then send)
- [x] 🤖 UI: Test lab screen
- [ ] 🧑 Try it on your own account, report what feels wrong

## Phase 2 — Control
- [x] 🤖 AppConfig editor + kill switches (AI, pushes, signups, maintenance message)
- [x] 🤖 Minimum app version: backend + public GET /api/app-config
- [ ] 🤖 iOS: read /api/app-config at launch (update screen, maintenance banner, AI/experts-off messages)
- [x] 🤖 Subscription grant / revoke / extend
- [ ] 🤖 Rate-limit + AI cap view and per-user reset (not built: needs a design for caps)
- [ ] 🧑 Decide the default kill-switch behaviour (what the app shows when AI is off)

## Phase 3 — Check
- [x] 🤖 Error + failed-delivery feed across all users
- [x] 🤖 Retention / onboarding funnel / "stopped logging" view
- [x] 🤖 Alerts: cron missed, push failure rate, AI spend spike
- [ ] 🧑 Choose where alerts go (email? push to you?) and thresholds

## Phase 4 — Manage
- [x] 🤖 Food catalog + barcode food editor
- [x] 🤖 View-as-user (read-only)
- [x] 🤖 Data export + delete-request tracking
- [x] 🤖 Photo cleanup queue view
- [x] 🤖 Admin audit log (who changed what)

## Phase 5 — New UI shell + ship
- [x] 🤖 New design system for the page (tokens, nav, components) per approved artboard
- [x] 🤖 Migrated People, Flags, Invites, Ops into the new shell
- [ ] 🤖 Move Usage + Guided tour into the new shell (still at /admin/classic)
- [x] 🤖 Tests (store, page, routes), typecheck, admin-secret login kept
- [ ] 🤖 Test the new routes against a throwaway database (never the live Neon)
- [ ] 🧑 Set any new env vars in Vercel (I'll list them)
- [ ] 🧑 Review + push to main (pushes auto-apply migrations to live Neon — I'll flag any migration first)
- [ ] 🤖 Smoke-test the live /admin after deploy

## Decisions I made (change if you disagree)
- Kept the single admin secret; the audit log records "admin", not a name.
- Simulation only works on accounts you mark as test accounts (no migration: stored in AppConfig).
- Everything new is stored in AppConfig rows, so there is NO migration to apply on push.

## Open questions for 🧑
- Keep the single admin secret, or add per-admin logins (needed for a real audit log)?
- Should simulate-day run against real users or only a test account?
