import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            #if DEBUG
            if let stub = DebugPreviewStub.fromLaunchArguments() {
                stub.view
            } else {
                authedContent
            }
            #else
            authedContent
            #endif
        }
        .animation(Motion.adaptive(Motion.gentle, reduceMotion: reduceMotion), value: env.auth.status)
        .task {
            env.auth.bootstrap()
            #if DEBUG
            if CommandLine.arguments.contains("-autoDevSignIn"), !env.auth.hasToken {
                await env.auth.developerSignIn()
            }
            #endif
        }
    }

    @ViewBuilder
    private var authedContent: some View {
        switch env.auth.status {
        case .loading:
            if env.auth.hasToken {
                HomeSkeletonView()
            } else {
                SignInSkeletonView()
            }
        case .signedOut:
            WelcomeView()
        case .signedIn:
            MainTabView()
        }
    }
}

#if DEBUG
/// Renders a specific screen with sample data via a launch argument, for
/// screenshots and manual review: `-uiStub home` / `-uiStub home-over`.
@MainActor
enum DebugPreviewStub {
    case home(HomeResponse)
    case welcome(page: Int)
    case onboarding(OnboardingViewModel.Step)
    case prescription
    case conversation(resolved: Bool)
    case logMeal(LogMealStubState)
    case savedMeal
    case settings
    case settingsGoal
    case settingsMealTimes
    case settingsMealTimesWeekends
    case settingsFoods
    case settingsHealth
    case settingsHealthWrite
    case calendarSettings
    case calendarConnect
    case training
    case refuel
    case settingsAccount
    case settingsDelete

    enum LogMealStubState { case compose, parsing, result, quick, scan }
    case settlement(SettlementResponse)

    @ViewBuilder
    var view: some View {
        switch self {
        case let .home(response):
            HomeContent(model: .previewed(.loaded(response)))
        case let .welcome(page):
            WelcomeView(initialPage: page)
        case let .onboarding(step):
            OnboardingFlow(model: .previewed(at: step))
                .background(Palette.background)
        case .prescription:
            PrescriptionStubHost()
        case let .conversation(resolved):
            ConversationView(
                checkInID: "ci_stub",
                onDismiss: {},
                onResolved: {},
                previewModel: .previewed(resolved: resolved)
            )
        case let .logMeal(state):
            LogMealStubHost(state: state)
        case .savedMeal:
            SavedMealEditorView(
                draft: SavedMealDraft(from: SavedMeal.samples[0]),
                onSave: { _ in true }
            )
        case .settings:
            NavigationStack { SettingsView(previewModel: .previewed()) }
        case .settingsGoal:
            NavigationStack { GoalSettingsView(model: Self.goalStubModel) }
        case .settingsMealTimes:
            NavigationStack { RhythmSettingsView(model: .previewed()) }
        case .settingsMealTimesWeekends:
            NavigationStack { RhythmSettingsView(model: .previewedWeekends()) }
        case .settingsFoods:
            NavigationStack { FoodsSettingsView(model: .previewed()) }
        case .settingsHealth, .settingsHealthWrite:
            NavigationStack { HealthSettingsView() }
        case .calendarSettings:
            NavigationStack { CalendarSettingsView() }
        case .calendarConnect:
            NavigationStack { CalendarConnectView() }
        case .training:
            NavigationStack { TrainingScreen(preview: .sample) }
        case .refuel:
            RefuelSheet(
                checkIn: .init(
                    id: "ci_refuel",
                    tier: 1,
                    status: "PENDING",
                    message: "You trained. Eat something now.",
                    deferUntil: nil,
                    prescription: HomeResponse.sampleUnder.activeCheckIn?.prescription,
                    slot: "refuel",
                    kind: "REFUEL"
                ),
                dinnerMin: 1170,
                remainingSeconds: 18 * 60,
                onHadThis: {},
                onCoveredByDinner: {},
                onDismiss: {}
            )
        case .settingsAccount:
            NavigationStack { AccountSettingsView(model: .previewed()) }
        case .settingsDelete:
            NavigationStack { AccountSettingsView(model: .previewed(), startDeleting: true) }
        case let .settlement(response):
            SettlementView(previewModel: .previewed(response))
        }
    }

    private static var goalStubModel: SettingsViewModel {
        let model = SettingsViewModel.previewed()
        model.pace = .gentle
        return model
    }

    static func fromLaunchArguments() -> DebugPreviewStub? {
        guard let index = CommandLine.arguments.firstIndex(of: "-uiStub"),
              CommandLine.arguments.indices.contains(index + 1)
        else { return nil }
        switch CommandLine.arguments[index + 1] {
        case "home": return .home(.sampleUnder)
        case "home-over": return .home(.sampleOver)
        case "home-empty": return .home(.sampleEmpty)
        case "home-snoozed": return .home(.sampleSnoozed)
        case "home-talk": return .home(.sampleTalk)
        case "home-onpace": return .home(.sampleOnPace)
        case "home-missed": return .home(.sampleMissed)
        case "home-quiet": return .home(.sampleQuiet)
        case "welcome": return .welcome(page: 0)
        case "welcome-notice": return .welcome(page: 1)
        case "welcome-plan": return .welcome(page: 2)
        case "welcome-quiet": return .welcome(page: 3)
        case "onboarding", "onboarding-goal": return .onboarding(.goal)
        case "onboarding-about": return .onboarding(.about)
        case "onboarding-target": return .onboarding(.target)
        case "onboarding-rhythm": return .onboarding(.rhythm)
        case "onboarding-restrictions": return .onboarding(.restrictions)
        case "onboarding-safety": return .onboarding(.safety)
        case "onboarding-reach": return .onboarding(.reach)
        case "onboarding-covered", "onboarding-outcome": return .onboarding(.covered)
        case "prescription": return .prescription
        case "conversation": return .conversation(resolved: false)
        case "conversation-resolved": return .conversation(resolved: true)
        case "log-meal": return .logMeal(.compose)
        case "log-meal-parsing": return .logMeal(.parsing)
        case "log-meal-result": return .logMeal(.result)
        case "log-quick": return .logMeal(.quick)
        case "log-scan": return .logMeal(.scan)
        case "saved-meal": return .savedMeal
        case "settings": return .settings
        case "you": return .settings
        case "calendar-settings": return .calendarSettings
        case "calendar-connect": return .calendarConnect
        case "home-busy": return .home(.sampleBusy)
        case "home-training": return .home(.sampleTraining)
        case "training": return .training
        case "refuel": return .refuel
        case "settings-goal": return .settingsGoal
        case "settings-meal-times": return .settingsMealTimes
        case "settings-meal-times-weekends": return .settingsMealTimesWeekends
        case "settings-foods": return .settingsFoods
        case "settings-health", "settings-health-write": return .settingsHealthWrite
        case "settings-account": return .settingsAccount
        case "settings-delete": return .settingsDelete
        case "settlement": return .settlement(.sample)
        case "settlement-weigh-in": return .settlement(.sampleNeedsWeighIn)
        case "settlement-empty": return .settlement(.sampleEmpty)
        default: return nil
        }
    }
}

private struct LogMealStubHost: View {
    let state: DebugPreviewStub.LogMealStubState

    var body: some View {
        switch state {
        case .compose:
            HomeContent(
                model: .previewed(.loaded(.sampleEmpty)),
                startComposerExpanded: true
            )
        case .quick:
            HomeContent(
                model: .previewed(.loaded(.sampleEmpty)),
                previewLogger: .sampleQuickLog,
                startComposerExpanded: true
            )
        case .scan:
            LogScanStubHost()
        case .parsing:
            HomeContent(
                model: .previewed(.loaded(.sampleEmpty)),
                previewLogger: .samplePhotoParsing
            )
        case .result:
            HomeContent(
                model: .previewed(.loaded(.sampleEmpty)),
                previewLogger: .samplePhotoConfirm
            )
        }
    }
}

private struct LogScanStubHost: View {
    @State private var product = LogMealViewModel.BarcodeProduct(food: .sampleYogurt, servings: 1)

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.ink.ignoresSafeArea()
            VStack(spacing: Space.sm) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Palette.lockScreenText)
                Text("Point the camera at a barcode")
                    .font(Typography.voice(22))
                    .foregroundStyle(Palette.lockScreenText)
            }
            BarcodeProductSheet(
                product: $product,
                slotTitle: "Lunch",
                onLog: {},
                onSave: {},
                onClose: {}
            )
        }
    }
}

private struct PrescriptionStubHost: View {
    var body: some View {
        ZStack {
            // A dimmed Home behind, so the morph's depth reads in review.
            HomeContent(model: .previewed(.loaded(.sampleUnder)))
                .disabled(true)
                .overlay { Palette.scrim.ignoresSafeArea().allowsHitTesting(false) }

            if let checkIn = HomeResponse.sampleUnder.activeCheckIn {
                PrescriptionView(
                    checkIn: checkIn,
                    headline: TodayCopy.headline(TodayMoment.resolve(.sampleUnder)),
                    whyNow: TodayCopy.whyNow(.sampleUnder),
                    onDismiss: {},
                    onResolved: {},
                    onAlreadyAte: {}
                )
            }
        }
    }
}
#endif

#Preview("Signed out") {
    RootView().environment(AppEnvironment.preview())
}
