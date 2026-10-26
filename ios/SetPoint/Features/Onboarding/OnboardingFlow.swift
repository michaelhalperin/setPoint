import SwiftUI

/// Setup after sign-in. Each step is one screen under a header of step bars;
/// one bone Continue button at the bottom. The last two steps (notifications,
/// the payoff) bring their own actions.
struct OnboardingFlow: View {
    @Bindable var model: OnboardingViewModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        screenBody.trackScreen("onboarding")
    }

    @ViewBuilder
    private var screenBody: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

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
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) { navBar }
            .background(alignment: .topTrailing) {
                RadialGradient(colors: [Palette.ember.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: 170)
                    .frame(width: 340, height: 340)
                    .blur(radius: 20)
                    .offset(x: 120, y: -80)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var stepView: some View {
        switch model.step {
        case .goal: GoalStep(model: model)
        case .about: AboutStep(model: model)
        case .rhythm: RhythmStep(model: model)
        case .restrictions: RestrictionsStep(model: model)
        case .safety: SafetyStep(model: model)
        case .reach, .covered: EmptyView()
        }
    }

    private var stepNumber: Int {
        (model.progressSteps.firstIndex(of: model.step) ?? 0) + 1
    }

    private var header: some View {
        HStack {
            Group {
                if model.canGoBack {
                    RoundIconButton("chevron.backward", label: "Back") { model.goBack() }
                        .transition(.opacity)
                } else {
                    Color.clear
                }
            }
            .frame(width: 40, height: 40)
            Spacer()
            StepBars(step: stepNumber, total: model.progressSteps.count)
            Spacer()
            Text("\(stepNumber)/\(model.progressSteps.count)")
                .font(Typography.mono(12))
                .foregroundStyle(Palette.inkFaint)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, 8)
        .background {
            LinearGradient(colors: [Palette.background.opacity(0.9), Palette.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        }
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: model.canGoBack)
    }

    private var navBar: some View {
        VStack(spacing: Space.xs) {
            if let error = model.error {
                Text(LocalizedStringKey(error))
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.danger)
                    .transition(.opacity)
            }
            // Safety builds the plan from its last answer — no button.
            if model.step != .safety {
                ActionButton(title: "Continue") { model.advance() }
                    .disabled(!model.canAdvance)
            }
        }
        .padding(.horizontal, Space.gutter)
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
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: model.error)
    }
}

#if DEBUG
#Preview {
    OnboardingFlow(model: .previewed(at: .goal))
        .environment(AppEnvironment.preview())
}
#endif
