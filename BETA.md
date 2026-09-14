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

Measured from real data over the last 7 days (`GET /api/admin/metrics` →
`stopConditions`), with minimum sample sizes so a handful of check-ins can't
trip anything:

| Signal | Measured as | Action |
| --- | --- | --- |
| Wearable hurts | Wearable-shaped check-ins get "already ate"/"wrong time" ≥ 10 pts more than control, or the wearable cohort pauses check-ins ≥ 10 pts more | **Automatic:** the scoring job turns the wearable modifier off (every user scores as Basic) and reports to Sentry |
| Delivery failing | ≥ 15% of check-ins FAILED or never sent | Alert — fix APNs before trusting any miss data |
| Scheduler stopped | No successful score run in 45 min (GitHub's 15-min cron often runs late) | Alert |

Reported by people, not detectable in code — each one halts release until fixed:

- Allergy or restriction miss in a suggestion
- Unsafe or shaming copy
- Materially worse week-2 retention in a cohort

## First release gate

Passes only when: every restriction is enforced; no undelivered check-in can
become a miss; every UI-confirmed action has a persisted effect; scoring
inputs are auditable; duplicate intervention tests pass; production scheduling
and APNs are monitored; and onboarding → meal → check-in → response → Week
works against a real database.
