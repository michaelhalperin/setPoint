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
            ProgressView()
        case .signedOut:
            SignInView()
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
    case onboarding(OnboardingViewModel.Step)
    case prescription
    case conversation(resolved: Bool)
    case logMeal(LogMealStubState)
    case settings

    enum LogMealStubState { case compose, parsing, result }
    case settlement

    @ViewBuilder
    var view: some View {
        switch self {
        case let .home(response):
            HomeContent(model: .previewed(.loaded(response)))
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
        case .settings:
            NavigationStack { SettingsView(previewModel: .previewed()) }
        case .settlement:
            NavigationStack { SettlementView(previewModel: .previewed(.sample)) }
        }
    }

    static func fromLaunchArguments() -> DebugPreviewStub? {
        guard let index = CommandLine.arguments.firstIndex(of: "-uiStub"),
              CommandLine.arguments.indices.contains(index + 1)
        else { return nil }
        switch CommandLine.arguments[index + 1] {
        case "home": return .home(.sampleUnder)
        case "home-over": return .home(.sampleOver)
        case "onboarding": return .onboarding(.welcome)
        case "onboarding-you": return .onboarding(.you)
        case "onboarding-goal": return .onboarding(.goal)
        case "onboarding-checkins": return .onboarding(.checkins)
        case "onboarding-safety": return .onboarding(.safety)
        case "onboarding-review": return .onboarding(.review)
        case "onboarding-outcome": return .onboarding(.outcome)
        case "prescription": return .prescription
        case "conversation": return .conversation(resolved: false)
        case "conversation-resolved": return .conversation(resolved: true)
        case "log-meal": return .logMeal(.compose)
        case "log-meal-parsing": return .logMeal(.parsing)
        case "log-meal-result": return .logMeal(.result)
        case "settings": return .settings
        case "settlement": return .settlement
        default: return nil
        }
    }
}

private struct LogMealStubHost: View {
    let state: DebugPreviewStub.LogMealStubState
    @State private var showing = true

    private var previewModel: LogMealViewModel? {
        switch state {
        case .compose: return nil
        case .parsing: return .sampleParsing
        case .result: return .previewed(LogMealViewModel.sampleLogged, text: "chicken burrito bowl, large")
        }
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            HomeContent(model: .previewed(.loaded(.sampleUnder)))
        }
        .sheet(isPresented: $showing) {
            LogMealSheet(onFinished: { showing = false }, previewModel: previewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct PrescriptionStubHost: View {
    @Namespace private var ns
    var body: some View {
        ZStack {
            // A dimmed Home behind, so the morph's depth reads in review.
            HomeContent(model: .previewed(.loaded(.sampleUnder)))
                .disabled(true)
                .overlay { Palette.scrim.ignoresSafeArea().allowsHitTesting(false) }

            if let checkIn = HomeResponse.sampleUnder.activeCheckIn {
                PrescriptionView(
                    checkIn: checkIn,
                    namespace: ns,
                    geometryID: "stub",
                    onDismiss: {},
                    onResolved: {},
                    onLogSomethingElse: {}
                )
            }
        }
    }
}
#endif

#Preview("Signed out") {
    RootView().environment(AppEnvironment.preview())
}
