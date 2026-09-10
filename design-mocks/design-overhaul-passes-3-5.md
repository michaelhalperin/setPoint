# Design overhaul — Passes 3–5

**Status: all three shipped (2026-09-10).** Commits `2606c23` (Pass 3),
`d1a2af6` (Pass 4), `b917059` (Pass 5). 38 iOS tests green. What actually
landed is noted per-pass below.

Continuation of the "Airbnb-grade beautiful + flow" overhaul (plan §5a / §6).
Passes 0–2 are done and committed:

- **Pass 0** — design-system foundation (Fraunces voice type, `Spacing`, `Elevation`,
  role springs in `Motion`, `.appearIn`).
- **Pass 1** — onboarding as a journey (ProgressThread, staggered steps, floating nav,
  ChoiceCard lift, OutcomeStep count-up).
- **Pass 2** — home + check-in morph (scrim, card lift, `Motion.morph`, PressableCard,
  PrescriptionView post-settle reveal).

Rhythm: each pass is its own build (`iPhone 16 Pro` simulator) + its own commit
(`feat(ios): <screen> — Pass N`). Everything respects `@Environment(\.accessibilityReduceMotion)`
via the existing `Motion.adaptive` guard.

---

## Pass 3 — Log-meal parse reveal

**Files:** `ios/SetPoint/Features/Home/LogMealSheet.swift`, `LogMealViewModel.swift`

The sheet's whole point (§5a: "skeletons, not spinners") is the moment the AI's guess
lands. Today `.compose → .parsing → .logged` just swaps views with `Motion.standard`.
Make the parse feel like the app doing work *for* you.

- **Compose → parsing:** the text/photo the user entered doesn't vanish — it lifts to
  the top as a compact "you said…" chip, and the redacted `ParsedBreakdown` skeleton
  slides up underneath it. One continuous motion, not a view swap.
- **Skeleton:** give the redacted card a slow shimmer (moving highlight gradient,
  ~1.4s, single sweep loop while `.parsing`) instead of flat grey. Stop it the instant
  real data arrives.
- **Parsing → logged (the payoff):** the skeleton stays in place and the real values
  **cross-fade + count up** into the same slots — `.contentTransition(.numericText())`
  on the kcal and protein numbers, line items fade in staggered (`Motion.stagger`).
  The card should not move; only its contents resolve. This is the "wow."
- **Photo path:** when `fromPhoto`, the thumbnail animates from the compose position
  into the card header so the source stays visually attached to the result.
- **"Looks right" / "remove it":** `staggerReveal` the two actions in after the numbers
  settle (same pattern as PrescriptionView's post-settle actions).
- **Failure:** gentle, no red — the "you said" chip stays so nothing's lost,
  `Motion.exit` the skeleton, `Motion.enter` the retry.
- **Reduce Motion:** shimmer off, count-up becomes a plain crossfade.
- **Stubs:** `log-meal-result` exists; add `log-meal-parsing` frozen mid-parse for
  screenshots.

**Test delta:** ~2–3 cases (phase transition ordering, skeleton clears on data,
Reduce-Motion fallback). Target ~33 iOS tests.

---

## Pass 4 — Week tab

**File:** `ios/SetPoint/Features/Settlement/SettlementView.swift`

"The honest truth" tab — motion here stays calm and never celebratory (§6, weight-goals
memo). Polish, not spectacle.

- **`WeekStrip` bars:** already stagger-grow. Add: on pull-to-refresh, bars animate from
  their old height to the new one (`.animation(value:)` keyed on ratio) rather than
  resetting to 3pt and regrowing. Today's bar gets a soft `firstAppearPulse` on first
  load only.
- **`WeightGoalCard`:**
  - `.numericText` count-up on the current-weight number and the "X kg to go" figure so
    a new weigh-in visibly moves them.
  - After a weigh-in that advances progress, the `ProgressBar` fill springs to the new
    fraction with `Motion.settle` (value-driven, so it re-animates on data change, not
    just `onAppear`).
  - Status pill ("On pace" / "Behind pace") cross-fades if the status changed since last
    load — a quiet acknowledgment, no bounce.
- **`WeighInSheet`:** on save, the "Save" button morphs to a check and the sheet
  dismisses on `Motion.exit` after ~250ms so the user sees it registered. The
  reached-target `.alert` stays a plain alert — deliberately not a moment.
- **`DayRow` list:** `staggeredAppear` already there; leave it.
- **Empty state:** `.appearIn` the "days fill in here…" copy.
- **Reduce Motion:** bar height changes instant, count-ups become crossfades.

**Test delta:** ~2 cases (progress fraction re-animates on data change; weigh-in success
dismiss path). Target ~35.

---

## Pass 5 — Cross-screen polish

No single owner file — the pass that makes the app feel like one object. Each item is
small; the pass is the sum.

- **Tab switches:** Today/Week/Settings currently hard-cut. Add a subtle content
  cross-fade + 4pt rise on the incoming tab's root (respecting Reduce Motion). Tab bar
  icons get `.symbolEffect(.bounce)` on select.
- **Tier-3 `ConversationView`** (`ios/SetPoint/Features/CheckIn/ConversationView.swift`):
  bring it up to the rest — message bubbles `.appearIn` as they arrive, the composer →
  status-card swap on `resolved` uses `Motion.morph`, manager messages use the Fraunces
  voice treatment consistently.
- **`PrescriptionView` ↔ Home morph:** audit the `matchedGeometryEffect` namespace for
  the check-in card — confirm it still reads as one continuous element after Passes 2–4
  touched Home. Fix any snap.
- **Scrim consistency:** Home dims behind check-in (Pass 2). Apply the same
  `Palette.scrim` treatment behind the log-meal sheet and the weigh-in sheet so every
  modal has the same "the app steps back" feel.
- **Settings screen:** never got a pass — `.appearIn` stagger on the Form sections,
  dirty-diff Save button animates enabled/disabled with `Motion.settle`, destructive
  "Delete account" confirmation unchanged.
- **Onboarding → Home handoff:** when the `fullScreenCover` dismisses after onboarding,
  the first Home render should `.appearIn`-cascade rather than appear fully formed — the
  reward for finishing.
- **Haptics:** one light impact on check-in open, one soft success on meal logged /
  weigh-in saved. Nothing on dismiss or scroll.
- **Global audit:** grep for any remaining `.easeInOut(duration:)` / `.animation(.default)`
  and replace with a role spring; confirm every `withAnimation` has a Reduce-Motion path.

**Test delta:** mostly manual + screenshot review across all `-uiStub` states. ~1–2
regression cases for the tab transition guard.

---

## Sequencing

Pass 3 and Pass 4 are independent — either order. Pass 5 must come last; it depends on
3 and 4 being settled.

---

## What shipped vs. plan

- **Pass 3** — as planned. New reusable `Shimmer` (`shimmering()`) modifier + `Haptics`
  helper (`nudge` / `landed`). `ParsedBreakdown` gained a `redacted` flag so skeleton
  and result are one view at a stable position. `-uiStub log-meal` now takes
  `compose | parsing | result`.
- **Pass 4** — as planned. `WeighInSheet` now owns a `save` phase and self-dismisses
  after a "✓ Saved" beat (its callback became `(Double) async -> Bool`).
- **Pass 5** — ConversationView bubbles + composer↔outcome morph, check-in-open
  haptic, Settings/Week entrance consistency, animation audit (already clean).
  **Cut:** custom TabView switch transition and tab-icon bounce — SwiftUI fights
  it and the payoff is small. Onboarding→Home cascade already worked (Home's
  `.appearIn` fires when `phase` flips to `.loaded`).
- **Pass 6** (`7f8ebc1`) — onboarding **rethink**, added after the fact. Not a
  motion pass: the flow was a settings form split into 7 pages, now it's an
  intake the manager walks you through. New `WelcomeStep` sets the deal before
  any form; 7 steps → 4 beats (You / Goal / Check-ins / Safety); `StepHeader` →
  `ManagerLine` (first-person Fraunces, check-in accent rule, `context:` line
  that echoes your last answer); goal pick draws a manager reaction;
  `OutcomeStep` rewritten first-person. Backend contract untouched. 40 tests.
