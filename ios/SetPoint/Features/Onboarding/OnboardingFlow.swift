import SwiftUI

struct OnboardingFlow: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if model.step != .outcome {
                OnboardingProgressBar(progress: model.progress)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            ScrollView {
                stepView
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            )
                    )
                    .id(model.step)
            }
            .scrollDismissesKeyboard(.interactively)

            navBar
        }
        .background(Palette.background.ignoresSafeArea())
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: model.step)
    }

    @ViewBuilder
    private var stepView: some View {
        switch model.step {
        case .goal: GoalStep(model: model)
        case .aboutYou: AboutYouStep(model: model)
        case .rhythm: RhythmStep(model: model)
        case .wearable: WearableStep(model: model)
        case .restrictions: RestrictionsStep(model: model)
        case .health: HealthStep(model: model)
        case .review: ReviewStep(model: model)
        case .outcome: OutcomeStep(model: model)
        }
    }

    private var navBar: some View {
        HStack(spacing: 12) {
            if model.canGoBack {
                Button("Back") { model.goBack() }
                    .font(Typography.data(15, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.horizontal, 8)
            }
            ActionButton(
                title: model.primaryTitle,
                kind: model.canAdvance ? .primary : .secondary
            ) {
                guard model.canAdvance else { return }
                model.advance()
            }
            .opacity(model.canAdvance ? 1 : 0.5)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            if let error = model.error {
                Text(error)
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.accent)
                    .padding(.bottom, 4)
                    .offset(y: -18)
            }
        }
    }
}

#if DEBUG
#Preview {
    OnboardingFlow(model: OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {}))
}
#endif
