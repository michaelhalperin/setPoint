# SetPoint — iOS app

Native Swift / SwiftUI. iOS 17+. The project file is generated from
[`project.yml`](./project.yml) with [XcodeGen](https://github.com/yonyz/XcodeGen).

## Getting started

```bash
brew install xcodegen        # once
cd ios && xcodegen generate  # regenerates SetPoint.xcodeproj after project.yml or file changes
open SetPoint.xcodeproj
```

`SetPoint.xcodeproj` is committed so you can open it directly, but `project.yml`
is the source of truth — re-run `xcodegen generate` after adding files or
changing settings.

### Command line

```bash
xcodebuild build -project SetPoint.xcodeproj -scheme SetPoint \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test  -project SetPoint.xcodeproj -scheme SetPoint \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

### Pointing at the backend

Defaults to `http://localhost:3000` on the simulator. Override with a
`SETPOINT_API_BASE_URL` environment variable (Scheme → Run → Arguments) to hit a
deployed instance. In DEBUG builds the sign-in screen shows a **Developer
sign-in** button that calls `POST /api/auth/dev`.

Screenshot a specific screen with sample data:

```bash
xcrun simctl launch <device> com.setpoint.app -uiStub home        # under-target home
xcrun simctl launch <device> com.setpoint.app -uiStub home-over   # over-target home
```

## Structure

```
SetPoint/
├── App/            SetPointApp, RootView (auth-gated), AppEnvironment (DI)
├── DesignSystem/   Palette (§6 terracotta), Typography (voice vs data), Motion (§5a springs), Components
├── Networking/     APIClient (async/await, bearer auth), APIConfig, DTOs
├── Auth/           AuthStore (Sign in with Apple + dev), KeychainTokenStore
└── Features/
    └── Home/       HomeScreen / HomeViewModel / HomeViews (§5.2 framing, §5a numeric transitions)
```

## Motion system (plan §5a)

`Motion.swift` holds the spring presets (`standard`, `snappy` for "manager's
voice" moments, `gentle`, `sheet`) and `Motion.adaptive(_:reduceMotion:)` which
falls back to a plain crossfade under Reduce Motion. `firstAppearPulse()` is the
**single** soft pulse for the urgency accent — never looping. The hero stat and
protein row use `.contentTransition(.numericText(value:))`; sheets use
`.presentationDetents`.

## Next

- Onboarding flow (goal, stats, meal times, SCOFF screen) → `POST /api/onboarding`
- Check-in → prescription shared-element morph (`matchedGeometryEffect`)
- Settlement view (7-day trend, staggered entrance)
- HealthKit → biosignal deviation upload; Live Activity + push registration
- Photo meal logging + `.redacted` skeleton while parsing runs
