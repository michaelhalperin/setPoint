# SetPoint — handoff for Cursor (2026-10-25)

Read this first. It covers the rules that bite, how to test and ship, what changed today,
and what's still open. `README.md`, `ios/README.md`, `backend/README.md` and
`backend/COMPLIANCE.md` have the longer background.

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
  206 tests passed at commit `2bc181a`.
- **Backend:** see the command in §1. `src/ai/experts/kernel.test.ts` ("returns paused…") fails
  on `main` before any of today's changes. It depends on a local env flag; ignore it.
- **Debug screens without signing in:** launch with `-uiStub <name>` (the list is in
  `ios/SetPoint/App/RootView.swift` → `fromLaunchArguments`). Useful ones: `log-quick`,
  `log-meal-result`, `log-meal-parsing`, `fix-meal`, `meal-detail`, `scanner`, `scanner-found`,
  `scanner-miss`, `scanner-label`, `scanner-looking`, `training`, `home`.
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

## 6. What changed today (commits on `main`, oldest → newest)

- **Release setup:**
  - Bundle ID moved to `com.michaelhalperin.setpointapp`; iPhone-only build.
  - Privacy manifests, Release entitlements (production push), `ios/scripts/archive.sh` (`UPLOAD=1`).
- **Barcode:**
  - The scanner has an aiming frame and stays up during lookup. Not-found offers **Photograph
    the label / Scan again / Type it instead**.
  - Results show as an in-scanner card (`ScannedProductCard`) instead of a sheet on top of the
    log sheet. "Save as my meal" opens over the scanner.
  - Lookup tries UPC-E / UPC-A / EAN-13 forms, keeps Hebrew-only names, works out kcal from
    macros, retries Open Food Facts once, then falls back to **USDA branded foods** (`FDC_API_KEY`).
  - Label photo → AI → saved in the shared `BarcodeFood` cache (new route
    `POST /api/foods/barcode/:code/label`, own quota `label_read`; never overwrites a known
    product).
- **Camera:** every add-photo entry offers Take photo / Choose from library (`CameraCapture`).
  A taken photo is submitted immediately (`LogMealViewModel.logPhoto`).
- **Photo recognition:** the Sonnet 5.5 path above. The app uploads at 1536px / 80% JPEG; the
  meal-log and label routes accept 4 MB (`backend/src/http/limits.ts`).
- **Photo result:** X button (cancels while reading, even if the meal lands later; asks before
  discarding a result). Today reloads on `env.changes.mealRevision`; deleted meals used to
  linger there.
- **Logged-meal sheet** (`MealDetailSheet` in `MealViews.swift`): rebuilt. Pinned actions
  (Log again / Fix / Save), delete confirmation, % of today, macro split.
- **Titles never truncate:** `FittingHeadline` in `DesignSystem/Atmosphere.swift`.
- **Sideways bounce fix:** `pullToReload` now bounces vertically only (`Components.swift`).
- **Train:** the snack shows as logged only when it's on today's log (`TrainingStore.isSnackLogged`).
- **Cursor, builds 11–15:** snack-before meal context, photo chip nudge, settings and clock
  fixes, pantry orbit.

## 7. Open items

1. **Done 2026-10-26 (build 15):** Cursor's ruler momentum and `alreadySaved` are committed;
   photo Fix tags are measured (`chipDx(spotX:chipWidth:containerWidth:)`) and long names
   truncate; the Meal times day label uses `WeekendDays.span` (weekend days are user-set);
   pantry suggestions go through `L10nKey`; Hebrew added for all of it.
   **Build 16:** the meal editor has Undo / "Back to what I saw" (no more "Clear it" dead end);
   Delete meal closes the sheet first and deletes in the background; scroll bars hidden app-wide
   (`.scrollIndicators(.hidden)` in `SetPointApp`). Still to do from the owner's list: new
   "How I check in" switch design, Edit plan screen, My meals rework.
   **Build 17:** log sheet opens on a live camera (`LiveMealCamera.swift`, AVFoundation) and a
   sideways Recent list (`GET /api/meals/recent`, last 14 days). Archive from a clean worktree
   when someone else has uncommitted edits: `archive.sh` builds whatever is in the folder.
   **Build 18:** the log sheet's rough-size Log button is pinned under the scroll area; the You
   screen's "How I check in" card is gone (a paused account sees one "Turn on" row).
   **Build 19:** planned sessions get "Did you train?" Done / Skipped once started
   (`POST /api/workouts/:ref/outcome`, `Workout.outcome`; skipped adds no calories and needs no
   refuel). Check-in delay per user (`OnboardingProfile.checkInGraceMin`, 30/45/60/90 under
   You → Meal times), threaded through every `checkInSlotAt` / `upcomingCheckIn` caller.
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
