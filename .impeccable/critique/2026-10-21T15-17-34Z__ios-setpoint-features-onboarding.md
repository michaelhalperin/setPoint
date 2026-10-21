---
target: onboarding
total_score: 24
max_score: 40
na_heuristics: 
p0_count: 1
p1_count: 3
target_identity: "file:/Users/michael/Desktop/clients/setPoint/ios/SetPoint/Features/Onboarding"
timestamp: 2026-10-21T15-17-34Z
slug: ios-setpoint-features-onboarding
---
# SetPoint iOS onboarding critique

Target: `ios/SetPoint/Features/Onboarding`
Mode: Operate (first-run wizard). Native SwiftUI; no live overlay.

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | 5 unlabeled step bars + `n/n`; Reach/Covered drop the chrome; disabled Continue rarely explains why |
| 2 | Match System / Real World | 2 | Welcome is fueling-gap; Goal is Gain/Cut/Maintain. “It sets your numbers.” |
| 3 | User Control and Freedom | 2 | No skip of the wizard; no back on About/Reach/Covered; last SCOFF tap auto-submits |
| 4 | Consistency and Standards | 3 | Coherent StepTitle/GlassList/bone CTA; “Skip” means three different exits; custom ± vs unused RulerPicker |
| 5 | Error Prevention | 3 | BMI 18.5 floor, pace caps, 16+ clamp; silent 170cm/70kg/age-28 defaults |
| 6 | Recognition Rather Than Recall | 2 | Disabled Continue does not name the missing field; step bars unlabeled |
| 7 | Flexibility and Efficiency | 2 | Health fill + draft resume exist; MealRhythmPreset is in the model and not on the Rhythm UI; wizard cannot be skipped |
| 8 | Aesthetic and Minimalist Design | 2 | High visual craft, low editorial restraint. About, Goal+target, and 13 chips dump one-decision-per-screen |
| 9 | Error Recovery | 3 | Draft kept on save fail; target/pace copy is specific; submit errors not distinguished |
| 10 | Help and Documentation | 2 | Tails help; “60-second setup” is false; SCOFF unexplained as a screen |
| **Total** | | **24/40** | **Acceptable** |

Product score asked by the user: **6 / 10**.

## Design Specificity Verdict

**LLM assessment:** Authored pockets on a calorie-app skeleton. Dark ground, ember wash, lock-screen aha, and quiet-mode copy are SetPoint. The *job* of the wizard is interchangeable with MyFitnessPal / Whoop intake: body stats → Gain/Cut/Maintain → activity → allergen wall → kcal target. Welcome promises “people who train and can’t eat enough”; step 2 offers **Cut / Lose fat, keep energy**. That split is the specificity failure.

**Deterministic scan:** `impeccable detect --json` on the Onboarding folder, `OnboardingComponents.swift`, and `OnboardingEnums.swift` all exited 0 with `[]`. The detector is a web HTML/CSS engine; empty JSON is “no eligible markup,” not a SwiftUI quality pass. Control scan of `.impeccable/mocks/decision/canon.html` produced 4 findings, so the tool works on HTML.

**Visual overlays:** none. Native SwiftUI; no onboarding HTML mock. Fallback signal: `native SwiftUI target; no HTML mock; detector/browser overlay not applicable`. Mechanical source signals: 6 `accessibilityLabel`, 2 `accessibilityHidden`, 6 Reduce Motion, 0 `.dynamicTypeSize`, 0 `minimumScaleFactor`.

## Overall Impression

The voice, quiet-mode ethics, and lock-screen demonstration are better than typical fitness onboarding. The *path* is still a long calorie-app intake that offers Cut, lies about SCOFF privacy, and sells Pro at the moment of understanding. Biggest opportunity: make the lock-screen the onboarding, and collect the form after the first check-in.

## What's Working

1. **Reach lock-screen** (`OnboardingFinish.swift`) — show-don’t-tell. “Lunch slipped” / “Here’s 680 kcal you can get down in 5 minutes.” Reduce Motion holds a still frame. This is the aha, and it is late.
2. **Safety framing + quiet landing** — “Pushing someone to eat isn’t always safe.” Quiet mode: no targets, no reminders, no paywall. Clinical weight is a gate, not a conversion event.
3. **Resume + safety math** — draft persists; restore will not skip missing answers; diet target cannot go below BMI 18.5.

## Cognitive load

5 / 8 checklist failures (high): single focus, chunking, one thing at a time, minimal choices, working memory. Overloaded points: Foods (13 chips), About (6 fields), Goal when Gain/Cut (goals + target + pace + weeks).

## Emotional journey

Start high (Welcome) → valley (weight + Cut) → deeper valley (SCOFF after a weigh-in, false privacy line) → peak (lock-screen / “Three plates”) → end on a paywall, not a first logged plate.

## Priority Issues

### [P0] Safety copy lies: “Answers stay on your phone”
- **What:** `OnboardingSafety.swift` line 46. Answers are encoded in `OnboardingDraft.toRequest()` and `POST /api/onboarding`; backend writes `scoffMakeSelfSick` etc. (`onboard.ts` 211–215).
- **Why it matters:** Health-adjacent ED screen. A privacy falsehood here is a trust failure, not a UX nit.
- **Fix:** Tell the truth in one line: stored with the account, used only to turn check-ins off. Do not auto-submit the last card; add an explicit save so the send is consented.
- **Suggested command:** `$impeccable clarify`

### [P1] First-run is a calorie-app form; aha is beat 12+ then a paywall
- **What:** About → Gain/Cut/Maintain + target → meals → 13 chips → 6 safety cards → notifications → “Three plates” → `PaywallView`. Welcome still says “Start · 60-second setup”. “Start my day” opens Pro, not Today.
- **Why it matters:** Activation job fails. User learns they filled a form, not that missed meals get a check-in. Cut as option 2 trains the wrong mental model on day zero.
- **Fix:** Lead with meal times + the lock-screen. Defer Cut, target weight, pace, and the allergen wall. Land on Today with log open; paywall after first log. Kill “60-second setup.” Reposition or drop Cut from first-run.
- **Suggested command:** `$impeccable onboard` then `$impeccable distill`

### [P1] About + Goal dump many decisions on screens that claim “one decision”
- **What:** About: Health, Height, Weight, Age, Activity, Sex. Height/weight start as “—” then first ± writes 170 / 70. Goal for Gain/Cut unfolds TargetCard on the same screen. `RulerPicker` exists and is unused.
- **Why it matters:** Jordan cannot tell the one required action. Silent 170/70/28 ships a wrong TDEE.
- **Fix:** One value per screen (or Health-fill then confirm). Empty until the user sets a number. Split target/pace off Goal. Put `MealRhythmPreset` on Rhythm.
- **Suggested command:** `$impeccable distill`

### [P1] Foods: 13 equal chips, no “none of these” as the default
- **What:** 13 options in one wrap. Vegetarian + Vegan + Pork + Beef sit beside allergens with the same chrome. Backend defaults structured chips to `ALLERGY`.
- **Why it matters:** Highest-choice screen is the lowest-stakes one. Allergen vs preference is flattened.
- **Fix:** Default Continue as “Nothing to skip.” Collapse to 4–5 common + “More.”
- **Suggested command:** `$impeccable distill`

### [P2] Safety interaction: “Not sure” highlight, fixed 300pt card, small hit targets
- **What:** Medical “Not sure” writes `true` like Yes, but selected highlight never applies to “Not sure” (`title != "Not sure"`), so tapping it lights **Yes**. Card is `frame(height: 300)`. Back is 40pt; Health “Fill in” is 34pt.
- **Why it matters:** Highest-stakes control lies visually. Dynamic Type will clip. Below 44pt.
- **Fix:** Third, visibly selected value. Drop fixed height. 44pt all around. One line: “Yes or not sure means I won’t send check-ins.”
- **Suggested command:** `$impeccable harden`

## Persona Red Flags

**Jordan (First-Timer):** First screen after Welcome is “A bit about you. It sets your numbers.” Sex pill labeled “Skip” looks like skip-the-step. Continue grey with no missing-field copy. “What are we building?” + Cut after Welcome said they can’t eat enough. “Start my day” opens Pro.

**Casey (Distracted Mobile):** Resume works (the Casey win). Cannot dismiss the cover. ± at 36pt, Health 34pt, back 40pt. Reach/Covered have no back. Killed mid-SCOFF auto-advance may POST.

**Sam (Accessibility):** Reduce Motion is actually wired — keep it. Safety 300pt will clip at xxxLarge. `Typography.sectionLabel` is unscaled 11pt mono. Covered meal list `.combine`s and drops plate kcal from the VoiceOver label. 0 `.dynamicTypeSize` constraints in onboarding sources.

**Athlete who under-eats (project-specific):** Asked for weight, then offered Cut / Lose fat, then SCOFF “Do you believe yourself to be fat when others say you are too thin?” The wizard creates the shame it is screening for. Covered still shows “A day · N kcal” after a comment that admits a big kcal total reads as a wall.

## Minor Observations

- Progress counts 5 steps; user still faces Reach, Covered, Paywall.
- `MealRhythmPreset` and `RulerPicker` are designed for this wizard and unused by it.
- `hasWearable` is set silently from Health heart data; Smart vs Basic never explained.
- Date picker blocks <16, so the underage message is mostly a Health-fill path.
- Tests encode the “one decision per screen” myth while About/Goal violate it.
- Ember radial blob on every default step is brand, not information.

## Questions to Consider

- If the product is “I check in when you under-eat,” why is the first required field height?
- What if Cut disappeared from first-run and only appeared later, under a supervision gate?
- Why show SCOFF *after* a weigh-in and a fat-loss target?
- Is the lock-screen mock the onboarding, and everything before it a settings dump you could collect after the first check-in?
- Can you justify posting SCOFF item-level answers when the engine only needs `enforcementEnabled`?
