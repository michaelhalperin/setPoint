# Product plan — eating enforcement app (name TBD)

## 1. Concept

An assistant that actively helps people eat enough — for both **mass gain** and **diet** goals, not just calorie tracking. It intervenes when someone's falling behind, instead of passively logging and letting the user ignore the numbers.

Positioning: a "manager," not a punisher. Assertive, but never shaming.

---

## 2. Core enforcement mechanism

### Detection
- **Smart mode** (wearable connected): biosignal deviation (HRV, resting heart rate) via HealthKit, sourced from Apple Watch or any other HRV-capable device (ring, mattress sensor, etc.)
- **Basic mode** (no wearable): self-report + time-since-last-meal heuristics only. Same downstream mechanic, less honest input.
- Mode is set at onboarding based on whether a compatible device is connected.

### Confidence scoring (deterministic — never AI)
```
Smart mode:  confidence = 0.5×biosignal_deviation + 0.3×(hours_since_meal / expected_gap) + 0.2×logging_silence
Basic mode:  confidence = 0.6×(hours_since_meal / expected_gap) + 0.4×logging_silence
```
- Check-in fires when `confidence > 0.7`.
- `expected_gap` is derived per-user from their own onboarding-set meal times, not a global constant.
- These are v1 starting weights, not final — tune against beta false-positive rate (see §8).
- The formula itself is permanent. It's the mechanism the whole product depends on, so it stays auditable — only the weights get refined later using real usage data.

### Quiet hours
- `quiet_hours_start` / `quiet_hours_end` stored per user (default 23:00–07:00) with timezone.
- The engine skips scoring entirely inside this window — checked before evaluation runs, not suppressed after.

### Trigger delivery
- Server-driven: backend cron/job scores confidence and pushes via APNs. Never dependent on the app being open — this is what makes the check-in real for a user who force-quit or never opened the app that day.
- Delivered as an **iOS Live Activity** + `interruptionLevel: .timeSensitive` notification.
- Deliberately **not** using Apple's critical alerts entitlement — that's gated to genuine health/safety cases, explicitly excludes engagement/nagging use cases, and risks App Store rejection. Time Sensitive is the legitimate version of "hard to ignore."

### The check-in
- Content = a **directive prescription**: a specific, low-friction instruction ("eat 2 eggs + toast, right now"), not an open-ended suggestion.
- Sourced from a constraint solver over a curated list of ~30–50 staple foods with hardcoded macros (swap to USDA FoodData Central or Open Food Facts later for breadth).
- Hard-excludes anything in the user's allergy/restriction list — never a soft preference.
- User responds with **log** (updates ledger) or **defer** (snooze).

### Defer / escalation loop
1. Defer → snooze timer (e.g. 2h) → re-check confidence at snooze end.
2. Still low → escalate. Three tiers total:
   - Tier 1: gentle nudge
   - Tier 2: firm check-in (default behavior above)
   - Tier 3 (after ~3 consecutive full misses): a short AI-assisted conversation — "this isn't working right now, want to adjust the plan or pause check-ins?" — not another notification.
3. After tier 3: back off. The miss shows up honestly in the settlement view instead of escalating indefinitely. Infinite escalation is how people uninstall.

---

## 3. Safety & compliance screening (onboarding)

Non-negotiable before the forcing mechanism is allowed to activate:

- **Allergies/restrictions** — multi-select + free text. Hard constraint on the prescription solver.
- **Medical conditions requiring supervised nutrition** (diabetes, kidney disease, etc.) — single question. If yes: forcing mechanism disabled, app becomes passive tracking only, with a note that it isn't a substitute for their care team's plan.
- **Eating-disorder screening** — SCOFF questionnaire (5 validated yes/no questions). If flagged: forcing mechanism disabled, plain non-judgmental note pointing to professional support. No explanation of what tripped it.
- **Preferred meal times** — breakfast/lunch/dinner time pickers, defaults 8am / 1pm / 7pm. Feeds `expected_gap` in the confidence formula and naturally handles unusual schedules (shift work, etc.) without special-casing.

---

## 4. Privacy & App Store compliance

- Public privacy policy required before submission (HealthKit access requires this) — use a generator (Termly, iubenda) or a freelancer, don't hand-write it.
- `NSHealthShareUsageDescription` and related Info.plist strings, specific and honest about what's read and why.
- Score on-device where possible; send only the derived confidence score to the backend, not raw HRV/RHR time series — reduces privacy surface and review scrutiny.
- Never use health data for advertising — flatly against Apple's rules.
- **Account deletion**: in-app, Settings → Delete account, one confirmation, cascading delete across every `userId`-keyed table (Prisma `onDelete: Cascade`, including TimescaleDB rows), revokes stored APNs token. Apple checks for this at review — build before first submission.

---

## 5. Screens & flow

1. **Onboarding** — goal (bulk/diet), stats, wearable connect (branches Basic/Smart), safety screening (§3), meal-time preferences.
2. **Home dashboard** — running ledger as the hero stat, framed by goal direction:
   - Bulk: deficit framing ("-620 kcal" style gap)
   - Diet: "under/over target," with **urgency reserved for under-eating specifically**, not for going over — over-target gets a quiet, neutral treatment (no accent color, no primary CTA); under-eating gets the full accent treatment regardless of bulk or diet.
   - Manager's note box below the stat, AI-generated (see §7).
3. **Check-in** — Live Activity, fires from the confidence engine.
4. **Directive prescription** — the specific "eat this now" suggestion, actions: log / defer.
5. **Log meal** — natural language or photo entry, AI-parsed into macros (see §7). Also reachable anytime from home, not just from a check-in.
6. **Defer → snooze → re-check → resolved or escalate** — loops per §2.
7. **Settlement** (daily/weekly) — 7-day trend, each day colored by outcome (on track / missed / over), one short manager-voice summary line. No badges, no confetti — consistent with the restrained tone.

---

## 5a. Animation & motion system

Airbnb-grade flow, translated to SwiftUI (not React Native — see note at end of this section):

- **Springs, not durations.** Use `.spring(response:dampingFraction:)` or iOS 17's `.smooth` / `.snappy` / `.bouncy` presets everywhere instead of `.easeInOut(duration:)`. Reserve tighter, faster springs for the "manager's voice" moments so the app feels responsive without feeling urgent.
- **Gesture-driven, not tap-then-animate.** The defer/snooze and log/dismiss actions (§2, §5.4) should track the user's finger via `DragGesture().updating()` so state visually follows touch in real time, then settle with a spring on release — not a fixed animation that plays after the tap registers.
- **Skeletons, not spinners.** Use `.redacted(reason: .placeholder)` on the macro fields while AI parsing runs (§7's meal-logging step), then fade real values in — never a blank/loading state.
- **Shared-element continuity.** Wrap the tappable card in the check-in → prescription flow (§5.3 → §5.4) in `matchedGeometryEffect` with a shared `@Namespace`, so tapping a check-in visually morphs into the full prescription screen instead of a hard push. This is the single biggest "wow" lever, and it maps directly to Airbnb's listing → detail transition.
- **Numeric transitions for the ledger.** The home dashboard's hero stat (§5.2) should never hard-cut when it updates — use `.contentTransition(.numericText(value:))` (iOS 16+) so the number visibly counts to its new value.
- **Native bottom sheets.** `.sheet` with `.presentationDetents([.medium, .large])` + `.presentationDragIndicator(.visible)` gets Airbnb-grade sheet behavior natively on iOS 16+ — no third-party dependency needed (this is a gap RN has that SwiftUI doesn't).
- **Staggered entrances.** The settlement view's 7-day trend (§5.7) should animate each day in with a small per-index delay (~40ms) rather than all at once — cheap with Swift Charts + `.animation(value:)` per mark.
- **Restraint on the urgency accent.** Per §6's "manager, not punisher" tone: the under-eating accent color should animate in with a single soft pulse on first appearance, not a looping one — a repeating alert reads as nagging and works against the tone you've already defined.
- **Live Activity constraint.** Live Activities/Dynamic Island only support Apple's limited built-in transition set — no custom spring or gesture code there. The animation payoff has to live in the full-screen prescription view it deep-links into, not the Live Activity itself. Budget your effort accordingly.
- **Respect Reduce Motion.** Check `@Environment(\.accessibilityReduceMotion)` and fall back to plain crossfades when it's on. Apple reviewers do check for this, and it's a one-line guard.

*Note: earlier in this conversation the animation stack discussed (Reanimated, react-native-gesture-handler, shared-element libraries) assumed React Native. This plan's tech stack (§10) specifies native Swift/SwiftUI instead, so everything above is the SwiftUI-native equivalent — not a port of the RN advice.*

---

## 6. Visual style

- **Mood**: warm, grounded, quietly confident — a coach, not an alarm system. No dark-glass fitness-app tropes, no clinical sterility, no gamification.
- **Color**: one accent color reserved specifically for the manager's voice / urgency moments, so color itself signals "the app is talking to you." Recommend warm terracotta/coral over clinical blue or alarm red — food-adjacent and calm, not urgent-by-default.
- **Typography**: a distinct, slightly editorial voice treatment for anything the manager "says" (check-ins, prescriptions, notes), visually separated from the cold data (ledger numbers, macros).
- **No gamification** — no badges, streak-loss animations, or confetti. Given the safety screening in §3, nothing in the visual language should ever read as shaming.

---

## 7. AI integration

**Where AI is used (from day one):**
- **Meal logging** — parses free-text or photo input into structured macros. Highest-value touchpoint; removes the friction that kills Basic-mode retention. Use a cheap/fast model — this runs constantly.
- **Manager's voice generation** — writes what the check-in *says* (varied phrasing, references actual numbers/patterns), not whether it fires. Tight prompt with tone guardrails against anything shame-adjacent, given the ED screening in §3. Fine to use a stronger model — runs rarely.
- **Tier-3 conversation** — the "let's talk" moment when escalation caps out (§2). Bounded routing: adjust plan / pause / suggest professional help — not open-ended chat.

**Where AI is explicitly kept out:**
- **Confidence scoring** — permanent deterministic formula (§2). Auditable, predictable, not something an LLM should ever decide. Weights get tuned over time using real data, not model judgment.
- **The prescription solver** — constraint solver over the curated food list, not an LLM freestyling suggestions that might ignore a hard-excluded allergy.

---

## 8. Beta & tuning plan

- Closed TestFlight beta, ~10–20 people to start (own student/network pool is a realistic first cohort).
- Add a thumbs up/down on every check-in as labeled feedback ("was this right?").
- Run 2–3 weeks. Watch **false-positive rate** specifically — a check-in firing when the person already ate kills trust fastest. Tune to minimize false positives even at the cost of missing some true positives.
- Freeze weights for public launch. Defer per-user bandit-style learning until there's real scale to justify it.

---

## 9. Monetization

- **Free tier**: Basic mode (scheduled check-ins, self-report).
- **Paid tier**: Smart mode (biosignal-triggered detection).
- Mirrors the real cost/value split — wearable integration is both the harder engineering lift and the genuinely differentiated experience, so it's the natural paywall.

---

## 10. Tech stack (iOS-only v1)

| Layer | Choice |
|---|---|
| Mobile | Swift/SwiftUI (native — Live Activities and HealthKit are more reliable here than via Expo/React Native) |
| Wearable data | Native HealthKit — no third-party aggregator needed for iOS-only |
| Backend | Node.js + TypeScript + Fastify |
| Database | Postgres + Prisma, with TimescaleDB extension for biosignal time-series data |
| Notifications | APNs directly (Live Activities + Time Sensitive) |
| Hosting | Vercel (web-facing), Railway or Fly.io (backend/workers) |
| Confidence scoring | On-device where possible; weighted formula, not a model call |
| Animation | SwiftUI native (`matchedGeometryEffect`, `.spring()`/`.smooth`/`.snappy`, Swift Charts) — no third-party animation library needed on iOS 16+ |

---

## Build order (suggested)

1. Onboarding + safety screening + meal-time preferences
2. Data model (Postgres/Prisma/TimescaleDB) + HealthKit integration
3. Confidence engine (server-driven, quiet hours, deterministic formula)
4. Check-in delivery (Live Activity + Time Sensitive) + defer/escalation loop
5. AI logging (photo/text → macros) + manager's voice generation
6. Home dashboard + settlement view, styled per §6
7. Privacy policy, account deletion, App Store compliance pass
8. Closed TestFlight beta → tune weights → public launch
