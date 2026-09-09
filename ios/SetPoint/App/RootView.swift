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
    }

    @ViewBuilder
    private var authedContent: some View {
        switch env.auth.status {
        case .loading:
            ProgressView()
                .task { env.auth.bootstrap() }
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

    var view: some View {
        switch self {
        case let .home(response):
            return HomeContent(model: .previewed(.loaded(response)))
        }
    }

    static func fromLaunchArguments() -> DebugPreviewStub? {
        guard let index = CommandLine.arguments.firstIndex(of: "-uiStub"),
              CommandLine.arguments.indices.contains(index + 1)
        else { return nil }
        switch CommandLine.arguments[index + 1] {
        case "home": return .home(.sampleUnder)
        case "home-over": return .home(.sampleOver)
        default: return nil
        }
    }
}
#endif

#Preview("Signed out") {
    RootView().environment(AppEnvironment.preview())
}
