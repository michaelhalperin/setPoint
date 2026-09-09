# SetPoint — iOS app

Native Swift / SwiftUI. iOS 17+. The project file is generated from
[`project.yml`](./project.yml) with [XcodeGen](https://github.com/yonyz/XcodeGen).

## Getting started (Xcode)

```bash
brew install xcodegen
cd ios && xcodegen generate
open SetPoint.xcodeproj
```

`SetPoint.xcodeproj` is committed so you can open it directly, but `project.yml`
is the source of truth — re-run `xcodegen generate` after adding files.

## Working in Cursor / VS Code (no Xcode window)

Xcode.app must be installed (SDK + simulator + toolchain), but you don't open it.
You lose only the live SwiftUI Preview canvas.

```bash
brew install xcodegen xcode-build-server   # once
./ios/scripts/gen.sh                        # generate project + LSP build server
```

Install the **Swift** extension (`swiftlang.swift-vscode`) — it's in
`.vscode/extensions.json`, so Cursor will offer it. Reload the window; you get
cross-file completion, jump-to-definition, and inline diagnostics via
SourceKit-LSP + `buildServer.json`.

Helper scripts (also wired as VS Code tasks — ⇧⌘P → "Tasks: Run Task"):

| Script | What it does |
| --- | --- |
| `./ios/scripts/gen.sh` | regenerate the project + `buildServer.json` — **run after adding/removing files** |
| `./ios/scripts/build.sh` | build for the simulator, prints only warnings/errors |
| `./ios/scripts/run.sh` | build → boot simulator → install → launch |
| `./ios/scripts/run.sh -uiStub home` | launch straight into Home with sample data |
| `./ios/scripts/test.sh` | run the XCTest suite |
| `./ios/scripts/shot.sh out.png` | screenshot the running simulator |

Set `SETPOINT_SIM="iPhone 16"` to target a different simulator.

### Pointing at the backend

Defaults to `http://localhost:3000` on the simulator. Override with a
`SETPOINT_API_BASE_URL` environment variable (Scheme → Run → Arguments) to hit a
deployed instance. In DEBUG builds the sign-in screen shows a **Developer
sign-in** button that calls `POST /api/auth/dev`.

Screenshot a specific screen with sample data:

```bash
./ios/scripts/run.sh -uiStub home              # under-target home
./ios/scripts/run.sh -uiStub home-over         # over-target home
./ios/scripts/run.sh -uiStub onboarding        # onboarding flow, step 1
./ios/scripts/run.sh -uiStub onboarding-health # SCOFF / safety step
./ios/scripts/run.sh -uiStub onboarding-review # review + submit step
./ios/scripts/run.sh -uiStub prescription      # the full-screen check-in
```

## Structure

```
SetPoint/
├── App/            SetPointApp, RootView (auth-gated), AppEnvironment (DI)
├── DesignSystem/   Palette (§6 terracotta), Typography (voice vs data), Motion (§5a springs), Components
├── Networking/     APIClient (async/await, bearer auth), APIConfig, DTOs
├── Auth/           AuthStore (Sign in with Apple + dev), KeychainTokenStore
└── Features/
    ├── Home/         HomeScreen / HomeViewModel / HomeViews (§5.2 framing, §5a numeric transitions)
    ├── Onboarding/   stepped flow → POST /api/onboarding (§3, §5.1)
    └── CheckIn/      PrescriptionView — the card ↔ full-screen matchedGeometryEffect morph (§5a)
```

The check-in morph: `CheckInContent` is the shared component rendered both as
the Home card and as the hero of `PrescriptionView`; a single
`matchedGeometryEffect` id in `HomeContent`'s `@Namespace` interpolates one into
the other. Actions hit `/api/meals` (`prescriptionId`), `/api/checkins/:id/defer`,
`/api/checkins/:id/feedback`. Drag-down dismisses.

## Motion system (plan §5a)

`Motion.swift` holds the spring presets (`standard`, `snappy` for "manager's
voice" moments, `gentle`, `sheet`) and `Motion.adaptive(_:reduceMotion:)` which
falls back to a plain crossfade under Reduce Motion. `firstAppearPulse()` is the
**single** soft pulse for the urgency accent — never looping. The hero stat and
protein row use `.contentTransition(.numericText(value:))`; sheets use
`.presentationDetents`.

## Next

- Check-in → prescription shared-element morph (`matchedGeometryEffect`)
- Settlement view (7-day trend, staggered entrance)
- HealthKit → biosignal deviation upload; Live Activity + push registration
- Photo meal logging + `.redacted` skeleton while parsing runs
