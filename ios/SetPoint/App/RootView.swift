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
            HomeScreen()
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
        }
    }

    static func fromLaunchArguments() -> DebugPreviewStub? {
        guard let index = CommandLine.arguments.firstIndex(of: "-uiStub"),
              CommandLine.arguments.indices.contains(index + 1)
        else { return nil }
        switch CommandLine.arguments[index + 1] {
        case "home": return .home(.sampleUnder)
        case "home-over": return .home(.sampleOver)
        case "onboarding": return .onboarding(.goal)
        case "onboarding-rhythm": return .onboarding(.rhythm)
        case "onboarding-health": return .onboarding(.health)
        case "onboarding-review": return .onboarding(.review)
        case "prescription": return .prescription
        default: return nil
        }
    }
}

private struct PrescriptionStubHost: View {
    @Namespace private var ns
    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
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
