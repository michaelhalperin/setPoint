import SwiftUI
import UIKit

/// The safety screen (§3) as a stack of cards, one yes/no question in front:
/// the medical question, then SCOFF. Answering the last card builds the plan.
struct SafetyStep: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var total: Int { SafetyQuestion.allCases.count }
    private var question: SafetyQuestion { SafetyQuestion(rawValue: model.safetyIndex) ?? .medical }
    private var remainingBehind: Int { min(2, total - 1 - model.safetyIndex) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            StepHeadline(text: "Quick and private.", detail: "Six yes-or-no questions.")

            ZStack {
                if remainingBehind >= 2 {
                    backCard(color: Palette.stackedCardFar, rotation: -4, y: 22, scale: 0.9)
                }
                if remainingBehind >= 1 {
                    backCard(color: Palette.stackedCardNear, rotation: 3, y: 11, scale: 0.95)
                }
                frontCard
                    .id(model.safetyIndex)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.94).combined(with: .opacity),
                        removal: .offset(x: -80).combined(with: .opacity)
                    ))
            }
            .frame(height: 330)
            .animation(Motion.adaptive(Motion.morph, reduceMotion: reduceMotion), value: model.safetyIndex)
            .appearIn(2)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(Palette.dayOnTrack)
                Text("Keeps check-ins safe for you")
                    .foregroundStyle(Palette.inkSoft)
            }
            .font(Typography.data(15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .appearIn(3)
        }
    }

    private var frontCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
                Spacer()
                Text("\(model.safetyIndex + 1) / \(total)")
                    .font(Typography.data(13, weight: .bold))
                    .foregroundStyle(Palette.inkFaint)
                    .monospacedDigit()
            }
            Spacer(minLength: Space.sm)
            Text(question.text)
                .font(Typography.voice(26))
                .foregroundStyle(Palette.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.sm)

            if model.submitting {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Building your plan…")
                        .font(Typography.data(15, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                }
                .frame(maxWidth: .infinity, minHeight: 58)
            } else if question == .medical {
                HStack(spacing: 8) {
                    answerButton("No", value: false)
                    answerButton("Not sure", value: true)
                    answerButton("Yes", value: true)
                }
            } else {
                HStack(spacing: 10) {
                    answerButton("No", value: false)
                    answerButton("Yes", value: true)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Palette.surface)
                .elevation(.lifted)
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Palette.hairline))
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
    }

    private func backCard(color: Color, rotation: Double, y: CGFloat, scale: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(color)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .offset(y: y)
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    private func answerButton(_ title: String, value: Bool) -> some View {
        let chosen = model.safetyAnswer(question) == value
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            model.answerSafety(value)
        } label: {
            Text(title)
                .font(Typography.data(title == "Not sure" ? 14 : 18, weight: .bold))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    if chosen && title != "Not sure" {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Palette.accent, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(PressableCard())
        .disabled(model.submitting)
    }
}
