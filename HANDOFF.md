# SetPoint — handoff (updated 2026-10-26, after build 19)

Read this first; you don't need the old conversation. It covers what to do next, the rules
that bite, how to test and ship, and what changed recently. `README.md`, `ios/README.md`, `backend/README.md` and
`backend/COMPLIANCE.md` have the longer background.

## 0. Start here: next up, and how the owner works

**Next up, from the owner's list (not started):**
1. **My meals rework** (You → My meals, `Features/Settings/SavedMealsSettingsView.swift`). The
   owner saw a design and hasn't said yes or asked for changes yet. Ask first. Design board:
   https://claude.ai/artifact/W53ibrDXyLfVtU4NV24BHo — big "My meals" title + count;
   All / Breakfast / Lunch / Dinner filter chips; a "BREAKFAST · RIGHT NOW" card for the plate
   that fits now, with a big "Log it · 420 kcal" button; then a compact list (name, slot,
   "used 12×", kcal, "+ Log" button; tap the row to edit). It replaces the big kcal rings.
2. **Edit plan screen** (`Features/Settings/SettingsScreens.swift`, `ScreenHeader(label: "Edit plan")`).
   The owner only said "Edit plan screen"; ask what's wrong before changing it.

**How the owner works:**
- Sends bug/feature lists; each batch ends in a TestFlight build (bump the build number, §2).
- For UI reworks they want to **see a simple design first** (a static mockup on a design board),
  then you build it in the app. Keep mockups simple.
- They reply in short messages; when something is ambiguous, ask with 2–4 concrete options.
- **Others edit this repo at the same time** (the owner, Cursor). Before committing, check
  `git status` for files you didn't touch. Don't commit them unless asked, and archive from a
  clean worktree if they'd end up in the build:
  ```bash
  W=$(mktemp -d)/ship && git worktree add --detach $W HEAD && cp ios/Config/Signing.xcconfig $W/ios/Config/ && (cd $W && UPLOAD=1 ./ios/scripts/archive.sh); git worktree remove --force $W
  ```
  (`Signing.xcconfig` is untracked, so copy it in.)

## 1. Rules you must not break

- **Never touch the live database.** `backend/.env` → `DATABASE_URL` is the **production Neon**
  database. A shadow-DB diff once wiped it (2026-09-15).
  - Never run `prisma migrate dev`, `prisma db push`, `prisma migrate reset` or any script that
    connects with `.env` loaded.
  - Run backend tests with a dead DB URL (dotenv doesn't override variables already set):
    ```bash
    cd backend && DATABASE_URL="postgresql://nobody@127.0.0.1:1/none" DIRECT_URL="postgresql://nobody@127.0.0.1:1/none" npx vitest run
    ```
  - Schema changes: hand-write an **additive** SQL migration under `backend/prisma/migrations/`.
    Pushing to `main` auto-deploys to Vercel **and runs `prisma migrate deploy` on live Neon**.
- **Pushing to `main` deploys the backend** (Vercel, about 1 minute). If the app starts sending
  something the old backend rejects, push and confirm the backend before the app build goes out.
- **Only one archive at a time.** Every build uses `ios/DerivedData/SetPoint.xcarchive`.

## 2. Ship a TestFlight build

1. Bump `CURRENT_PROJECT_VERSION` in `ios/project.yml` (build **19** is the latest upload).
2. Archive and upload; it regenerates the Xcode project itself:
   ```bash
   UPLOAD=1 ./ios/scripts/archive.sh
   ```
3. The build shows in App Store Connect → TestFlight after 10–30 minutes. The internal group
   "Me" has automatic distribution on.

| Item | Value |
|---|---|
| Bundle ID | `com.michaelhalperin.setpointapp` (widget `.widgets`, app group `group.com.michaelhalperin.setpointapp`) |
| Team | `7KRVJV784T` |
| App Store Connect app | `6826865782` — https://appstoreconnect.apple.com/apps/6826865782 |
| Backend | https://set-point-backend.vercel.app (`/api/health`) |

- `app.setpoint.ios` belongs to another developer, so don't switch back to it.
- Automatic signing archives with a development profile first, so the team needs a registered
  device (the owner's iPhone UDID is registered). Setting `CODE_SIGN_IDENTITY: Apple Distribution`
  with automatic signing fails; don't retry it.
- The "Upload Symbols Failed … Sentry.framework dSYM" warning is harmless (Sentry DSN is empty).

## 3. Test and look at things

- **iOS unit tests** (the default `iPhone 16 Pro` simulator isn't installed in this Xcode):
  ```bash
  SETPOINT_SIM="iPhone 18 Pro" ./ios/scripts/test.sh
  ```
  206 tests passed at commit `e713e02` (build 19).
- **Backend:** see the command in §1. `src/ai/experts/kernel.test.ts` ("returns paused…") fails
  on `main` before any of today's changes. It depends on a local env flag; ignore it.
- **Debug screens without signing in:** launch with `-uiStub <name>` (the list is in
  `ios/SetPoint/App/RootView.swift` → `fromLaunchArguments`). Useful ones: `log-quick`,
  `log-meal-result`, `log-meal-parsing`, `fix-meal`, `meal-detail`, `scanner`, `scanner-found`,
  `scanner-miss`, `scanner-label`, `scanner-looking`, `training` (yesterday has an unanswered
  planned lift), `home`, `settings`, `settings-meal-times`, `settings-saved-meals`.
- `./ios/scripts/run.sh` builds, then dies at `open -a Simulator` **before installing**, so you
  launch the old build. Install by hand instead:
  ```bash
  cd ios && U=137887BA-AC66-4B2F-87AF-095D3F1680D2 && xcodebuild build -project SetPoint.xcodeproj -scheme SetPoint -sdk iphonesimulator -destination "id=$U" -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO -quiet && xcrun simctl install $U "$(find DerivedData/Build/Products/Debug-iphonesimulator -maxdepth 1 -name '*.app' | head -1)" && xcrun simctl launch --terminate-running-process $U com.michaelhalperin.setpointapp -uiStub meal-detail
  ```
  `U` is the iPhone 18 Pro simulator's UDID. When driving the simulator, the first tap after a
  launch is often swallowed.

## 4. Hebrew (the app ships in he)

Every new user-facing string needs Hebrew in `ios/scripts/apply_he.py`:
1. Add `"English": "עברית"` to the `HE` dict.
2. Add the key to the `extras` tuple in `apply()`.
3. Build once (that refreshes the catalog), then run `python3 ios/scripts/apply_he.py`.

"missing 10" is expected (sample times and numbers used only in previews). Copy uses the app's
first-person voice ("לא מצאתי", "I'll work it out").

## 5. Claude API (backend)

| Use | Model | How |
|---|---|---|
| Meal **photo** parse | `claude-sonnet-5-5` | **Structured outputs** (`output_config.format` json_schema), adaptive thinking at effort `medium`, `fallbacks: "default"` (beta `server-side-fallback-2026-07-01`). See `backend/src/ai/parseMeal.ts` → `mealPhotoRequest`. |
| Meal **text** parse | `claude-haiku-4-5` | Forced `record_meal` tool call (`mealTextRequest`). |
| Nutrition **label** read | `claude-haiku-5-5` | Forced tool (`backend/src/foods/label.ts`). |

- **Sonnet 5.5, Opus 5.5 and Fable 5.1 reject forced `tool_choice`** (`tool` / `any` → 400). Use
  structured outputs or `auto` + `strict`.
- Since 2026-10-21, `temperature`, `top_p` and `top_k` → 400 on every model. Don't add them.
- Photo items carry `grams` + per-100g values; item macros are computed server-side
  (`itemFromRecord`), and totals are the sum of the items.
- To A/B a prompt on real photos, fetch the image into memory and send it as base64. Anthropic's
  URL image fetcher gets blocked by Wikimedia. Keep scratch scripts out of `src/` and delete them
  afterwards.

## 6. What changed recently (newest first)

- **Build 19:**
  - **Train:** once a planned session starts, "Did you train?" with Done / Skipped and Undo
    (`SessionOutcomeRow` in `TrainWeekViews.swift`, `TrainingStore.setOutcome`).
    `POST /api/workouts/:ref/outcome`, nullable `Workout.outcome`, 14-day window. Skipped adds no
    calories and needs no refuel (`isSkipped` in `engine/training.ts` and `TrainPlan.swift`).
    Done counts as proof of training for the refuel nudge (`jobs/scoreConfidence.ts`).
  - **Check-in delay per user:** `OnboardingProfile.checkInGraceMin` (default 45), set to
    30/45/60/90 under You → Meal times (`checkInWait` in `RhythmSettingsView`). It's passed to
    every `checkInSlotAt` / `upcomingCheckIn` / `movedSlotsToday` / `buildWeekRecord` /
    `buildCalendarWeek` caller.
  - Migration `20261026120000_workout_outcome_checkin_grace` (additive), already live.
- **Build 18:**
  - Log sheet: the rough-size "Pick a size · + Log ~1,050" row is pinned under the scroll area.
  - You screen: "How I check in" removed. Notifications live in Settings. An account that paused
    check-ins sees a "Check-ins are paused · Turn on" row; safety-off accounts still see why.
- **Build 17:**
  - Log sheet opens on a live camera (`LiveMealCamera.swift`, AVFoundation; library button;
    fallback with no camera or no permission).
  - Sideways "Recent" cards (last 10, one per name) from `GET /api/meals/recent` (14 days).
  - Usual tiles are saved plates only.
- **Build 16:**
  - Meal editor: Undo after removing a food, an empty-plate state, and "Back to what I saw".
    "Clear it" is gone.
  - Delete meal closes the sheet first, then deletes in the background.
  - Scroll bars hidden app-wide (`.scrollIndicators(.hidden)` in `SetPointApp`).
- **Build 15:**
  - Photo Fix tags are measured and truncate instead of leaving the screen.
  - The Meal times day label follows the user's weekend days (`WeekendDays.span`).
  - Pantry suggestions are localized; Hebrew filled in.
- **Builds 10–14 (2026-10-25):**
  - Barcode scanner rebuild + USDA fallback + label photo → AI.
  - Sonnet 5.5 photo parsing.
  - Camera capture.
  - Logged-meal sheet rebuild.
  - `FittingHeadline`.
  - Vertical-only pull bounce.
  - Train snack fix.
  - Cursor's settings/clock/pantry work.

## 7. Open items

1. See §0 for the next features.
2. **Vercel env:** add `FDC_API_KEY` (free at api.data.gov; the demo key allows about 10
   lookups an hour) and `APPLE_APP_APPLE_ID=6826865782`. `APPLE_CLIENT_ID`, `APNS_BUNDLE_ID` and
   `APP_BUNDLE_ID` must all equal the bundle ID.
3. **Before App Store review:**
   - App Privacy labels (health data, email, meal logs).
   - `NSPrivacyCollectedDataTypes` in both `PrivacyInfo.xcprivacy` files is empty; it should match
     the labels.
   - 6.9" screenshots and a description.
   - Review notes with an invite code if `INVITE_ONLY` is on.
4. **Label contributions are shared without moderation.** Anyone can fill an unknown barcode.
   Consider a `source` / `contributedById` column (an additive migration) and a way to report a
   wrong product.
5. **Watch for:** Cursor's tap-anywhere keyboard dismissal (`.onTapGesture` on
   `InnerScreen` / `SettingsScreen` scroll views) can swallow taps on some controls.
   If a settings control stops responding, look there first. New user-facing text always
   needs Hebrew (§4).
6. **SwiftUI gotcha that caused several of today's bugs:** a sheet requested while another
   sheet or full-screen cover is still on screen (or dismissing) shows late or not at all.
   Present it from inside the current presentation, or hand off in `onDismiss`.
