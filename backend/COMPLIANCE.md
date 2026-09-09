# App Store & privacy compliance checklist

Tracks what App Review checks for and where each item is handled. Plan §4 is the
source; this file is the working checklist.

## Account deletion — DONE (backend)

Apple requires in-app account deletion for any app with account creation.

- [x] `DELETE /api/account` — one confirmation (`{ "confirmation": "delete my account" }`),
      cascading delete across every `userId`-keyed table (Prisma `onDelete: Cascade`
      on all FKs — verified in `schema.prisma`), best-effort Sign in with Apple
      token revocation first.
- [ ] iOS: Settings → Delete account → one confirmation dialog → call the endpoint,
      then sign the user out and clear the keychain.
- [ ] Sign in with Apple token revocation needs the auth-code exchange to ship so
      `User.appleRefreshToken` is populated (column exists; `revokeAppleToken`
      is wired and dormant until then). Set `APPLE_TEAM_ID` / `APPLE_KEY_ID` /
      `APPLE_PRIVATE_KEY` (a "Sign in with Apple" .p8, distinct from the APNs key).

## HealthKit

- [ ] `NSHealthShareUsageDescription` in Info.plist — specific and honest, e.g.
      "SetPoint reads your heart-rate variability and resting heart rate to notice
      when you may be under-fuelled and prompt you to eat."
- [ ] Do **not** request HealthKit write access — the app only reads.
- [x] Backend never receives raw HRV/RHR — only a derived deviation the app
      computes on-device (`BiosignalState` / `BiosignalReading`, plan §4).
- [ ] Never use health data for advertising or share it with third parties
      (against Apple's rules) — no analytics SDK gets health-derived fields.

## Notifications

- [x] Check-ins are delivered as `interruption-level: time-sensitive`, **not**
      critical alerts (`src/push/apns.ts` — `buildCheckInAlertPayload`). Critical
      alerts need a special entitlement gated to health/safety and would risk
      rejection for an engagement use case.
- [ ] Request notification permission with a clear pre-prompt explaining the
      check-in mechanic.

## Privacy policy

- [ ] Public URL live **before** submission (HealthKit access requires it).
      Generate with Termly or iubenda, or a freelancer — do not hand-write.
- [ ] App privacy "nutrition labels" in App Store Connect: Health & Fitness data
      (not linked to identity, not used for tracking), Identifiers (user id),
      Contact Info (email, if collected via Apple).

## Safety screening

- [x] SCOFF screen (`src/onboarding/scoff.ts`) and the medical-supervision
      question gate `SafetyScreening.enforcementEnabled` — a positive result
      disables the forcing mechanism and the app becomes passive tracking.
- [ ] iOS: on a positive screen, show a plain non-judgemental note pointing to
      professional support. Do not explain what tripped it.
- [ ] Onboarding copy avoids anything shame-adjacent (also enforced in the
      manager's-voice prompt, `src/managerVoice/ai.ts`).

## Data handling

- [x] Score on-device where possible; send only the derived confidence score /
      deviation to the backend.
- [ ] Data retention: define how long `ConfidenceScore` / `BiosignalReading` /
      `Meal` rows are kept; document in the privacy policy.
- [ ] TLS everywhere (Vercel + Neon default); no personal data in URLs / query
      strings.
