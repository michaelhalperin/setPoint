# App Store & privacy compliance checklist

Tracks what App Review checks for and where each item is handled.

## Account deletion — DONE

Apple requires in-app account deletion for any app with account creation.

- [x] `DELETE /api/account` — one confirmation (`{ "confirmation": "delete my account" }`),
      cascading delete, Sign in with Apple token revocation when a refresh token exists.
- [x] iOS: Settings → Delete account → confirmation → endpoint, then sign out.
- [x] Sign in with Apple authorization-code exchange stores `User.appleRefreshToken`
      when `APPLE_TEAM_ID` / `APPLE_KEY_ID` / `APPLE_PRIVATE_KEY` are set.

## HealthKit

- [x] `NSHealthShareUsageDescription` — reads height/weight/age/sex for targets;
      HRV/RHR may adjust an already-due check-in and never independently diagnose
      under-fueling.
- [x] Do **not** request HealthKit write access — the app only reads.
- [x] Backend never receives raw HRV/RHR — only a derived deviation.
- [x] Health data is not used for advertising.

## Notifications

- [x] Check-ins are `interruption-level: time-sensitive`, not critical alerts.
- [x] Live Activity start tokens are stored; Time Sensitive notifications remain
      the fallback.
- [x] Push tokens are pruned on APNs 410 and removed on sign-out.

## Privacy policy and terms

- [x] `/privacy` and `/terms` describe observed meal behavior, not physiological
      certainty. Minimum age is 16. Medical eligibility includes uncertain
      answers (passive tracking, no check-ins). Barcode lookups go to Open Food
      Facts (barcode only); saved meals stay on the account.
- [ ] App Store Connect privacy labels still need to be filed at submission.

## Safety screening

- [x] SCOFF + expanded medical question (`medicalConditionAffectsEating`) gate
      `enforcementEnabled`. Uncertain answers keep check-ins off.
- [x] Custom restriction free text is normalized into solver exclusions.
- [x] Tier-3 plan changes are bounded proposals the user must confirm.

## Data handling

- [x] Production schema changes use versioned Prisma migrations
      (`prisma migrate deploy`). `db push` is local-only.
- [x] Payload size cap (1 MB), future `loggedAt` rejected, auth rate limit.
- [x] Developer login is off in production unless `ENABLE_DEV_LOGIN=true`.
