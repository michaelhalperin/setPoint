import SwiftUI

/// Setup after sign-in. Each step is one screen; the round Next button carries
/// progress in its ring. The last two steps (notifications, the payoff) bring
/// their own actions.
struct OnboardingFlow: View {
    @Bindable var model: OnboardingViewModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var terracotta: Bool { model.step == .covered && model.enforcementEnabled }

    var body: some View {
        ZStack {
            (terracotta ? Palette.accent : Palette.background)
                .ignoresSafeArea()

            content
                .id(model.step)
                .transition(.opacity)
        }
        .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion), value: model.step)
        .task {
            await env.push.syncAuthorizationStatus()
            model.asksForNotifications = env.push.authorizationStatus == .notDetermined
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .reach:
            ReachStep(model: model)
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.lg)
                .padding(.bottom, Space.xs)
        case .covered:
            CoveredStep(model: model)
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.lg)
                .padding(.bottom, Space.xs)
        default:
            ScrollView {
                stepView
                    .padding(.horizontal, Space.gutter)
                    .padding(.top, Space.lg)
                    .padding(.bottom, Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) { navBar }
        }
    }

    @ViewBuilder
    private var stepView: some View {
        switch model.step {
        case .goal: GoalStep(model: model)
        case .about: AboutStep(model: model)
        case .target: TargetStep(model: model)
        case .rhythm: RhythmStep(model: model)
        case .restrictions: RestrictionsStep(model: model)
        case .safety: SafetyStep(model: model)
        case .reach, .covered: EmptyView()
        }
    }

    private var navBar: some View {
        VStack(spacing: Space.xs) {
            if let error = model.error {
                Text(error)
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.accentDeep)
                    .transition(.opacity)
            }
            HStack {
                if model.canGoBack {
                    CircleBackButton { model.goBack() }
                        .transition(.opacity)
                }
                Spacer()
                RingNextButton(
                    progress: model.progress,
                    enabled: model.canAdvance,
                    busy: model.submitting
                ) { model.advance() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, Space.sm)
        .padding(.bottom, Space.xxs)
        .background(alignment: .top) {
            VStack(spacing: 0) {
                LinearGradient(colors: [Palette.background.opacity(0), Palette.background], startPoint: .top, endPoint: .bottom)
                    .frame(height: 24)
                Palette.background
            }
            .ignoresSafeArea()
        }
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: model.canGoBack)
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: model.error)
    }
}

#if DEBUG
#Preview {
    OnboardingFlow(model: .previewed(at: .goal))
        .environment(AppEnvironment.preview())
}
#endif
