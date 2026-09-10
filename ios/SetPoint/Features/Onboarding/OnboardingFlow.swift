import SwiftUI

struct OnboardingFlow: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if let index = model.threadIndex {
                VStack(spacing: Space.xs) {
                    HStack {
                        Text(model.stepTitle ?? "")
                            .sectionLabelStyle()
                    }
                    ProgressThread(step: index, total: OnboardingViewModel.threadedSteps.count)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.sm)
                .transition(.opacity)
            }

            ScrollView {
                stepView
                    .padding(.horizontal, Space.gutter)
                    .padding(.top, topPadding)
                    .padding(.bottom, 148) // clear the floating nav
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                    .id(model.step)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Palette.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { navBar }
        .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion), value: model.step)
    }

    private var topPadding: CGFloat {
        switch model.step {
        case .welcome, .outcome: return 0
        default: return Space.lg
        }
    }

    @ViewBuilder
    private var stepView: some View {
        switch model.step {
        case .welcome: WelcomeStep()
        case .you: YouStep(model: model)
        case .goal: GoalStep(model: model)
        case .checkins: CheckinsStep(model: model)
        case .safety: SafetyStep(model: model)
        case .review: ReviewStep(model: model)
        case .outcome: OutcomeStep(model: model)
        }
    }

    private var navBar: some View {
        HStack(spacing: Space.sm) {
            if model.canGoBack {
                Button {
                    model.goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .font(Typography.data(15, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 6)
                }
                .transition(.opacity)
            }

            ActionButton(
                title: model.primaryTitle,
                kind: .primary
            ) {
                guard model.canAdvance else { return }
                model.advance()
            }
            .opacity(model.canAdvance ? 1 : 0.4)
            .allowsHitTesting(model.canAdvance)
            .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: model.canAdvance)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.md)
        .padding(.bottom, Space.xs)
        .background(alignment: .top) {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Palette.background.opacity(0), Palette.background],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 20)
                Palette.background
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            if let error = model.error {
                Text(error)
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.accent)
                    .padding(.bottom, 4)
                    .offset(y: -22)
                    .transition(.opacity)
            }
        }
        .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion), value: model.canGoBack)
    }
}

#if DEBUG
#Preview {
    OnboardingFlow(model: OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {}))
}
#endif
