# Closed beta — evidence gates

Wearable Smart stays **off** until it proves incremental value.

- Default: `WEARABLE_MODIFIER_ENABLED` is unset. Scoring is behavior-only
  (overdue meals, last confirmed meal, logging reliability, dismiss/defer
  history, target coverage).
- Experiment: set `WEARABLE_MODIFIER_ENABLED=true` and
  `WEARABLE_MODIFIER_COHORT_PERCENT` (0–100). Fresh HRV/RHR may adjust an
  already-due check-in by at most +0.15 / −0.10. Stale or missing data matches
  Basic mode. The modifier cannot independently fire a check-in.
- No paid SMART mode until the wearable cohort reduces false positives or
  improves timely meals without raising opt-outs.

## Metrics to watch (`GET /api/admin/metrics`)

Notification send success, opened/answered rate, explicit wrong-time rate,
“already ate” rate, meal-correction rate, suggestion swap/rejection rate,
escalation rate, opt-out rate, week-2 retention, target-progress stability.

## Stop conditions

Any of these immediately disables the affected feature (kill the wearable
switch, pause scoring, or halt release):

- Elevated negative feedback or opt-outs
- Unsafe copy
- Allergy miss
- Delivery-correlated false misses (`scheduler.stale` or high miss rate)
- Materially worse week-2 retention

Admin metrics include `stopConditions.evaluation` so a stale scheduler or
failing delivery is visible without waiting for a human dashboard.

## First release gate

Passes only when: every restriction is enforced; no undelivered check-in can
become a miss; every UI-confirmed action has a persisted effect; scoring
inputs are auditable; duplicate intervention tests pass; production scheduling
and APNs are monitored; and onboarding → meal → check-in → response → Week
works against a real database.
