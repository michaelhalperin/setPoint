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
        VStack(alignment: .leading, spacing: Space.md) {
            StepTitle(
                label: "Safety · private",
                text: "Six yes-or-no questions.",
                tail: "Quick, and only for you.",
                detail: "Pushing someone to eat isn’t always safe. If it isn’t for you, I stay quiet.",
                size: 32
            )

            ZStack {
                if remainingBehind >= 2 {
                    backCard(fill: 0.025, stroke: 0.05, inset: 22, drop: 26)
                }
                if remainingBehind >= 1 {
                    backCard(fill: 0.035, stroke: 0.07, inset: 11, drop: 13)
                }
                frontCard
                    .id(model.safetyIndex)
                    .transition(.asymmetric(
                        insertion: .offset(y: 16).combined(with: .opacity),
                        removal: .offset(x: -80).combined(with: .opacity)
                    ))
            }
            .frame(height: 300)
            .padding(.bottom, 26)
            .animation(Motion.adaptive(Motion.morph, reduceMotion: reduceMotion), value: model.safetyIndex)
            .appearIn(1, rise: 14)

            HStack(spacing: 8) {
                Image(systemName: "lock")
                    .font(.system(size: 12, weight: .medium))
                Text("Answers stay on your phone")
            }
            .font(Typography.data(13, weight: .regular))
            .foregroundStyle(Palette.inkSoft)
            .frame(maxWidth: .infinity)
            .appearIn(2)
        }
    }

    private var frontCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lock")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.inkFaint)
                Spacer()
                Text("\(model.safetyIndex + 1) / \(total)")
                    .font(Typography.mono(12))
                    .foregroundStyle(Palette.inkFaint)
            }
            Text(question.text)
                .font(Typography.data(question == .medical ? 20 : 24, weight: .light))
                .tracking(-0.4)
                .lineSpacing(3)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            if model.submitting {
                HStack(spacing: 10) {
                    BusyDots(tint: Palette.amber)
                    Text("Building your plan…")
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                }
                .frame(maxWidth: .infinity, minHeight: 54)
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
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(hex: 0x18181C))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.10)))
        }
        .accessibilityElement(children: .contain)
    }

    private func backCard(fill: Double, stroke: Double, inset: CGFloat, drop: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color.white.opacity(fill))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(stroke)))
            .padding(.horizontal, inset)
            .offset(y: drop)
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    private func answerButton(_ title: String, value: Bool) -> some View {
        let chosen = model.safetyAnswer(question) == value && title != "Not sure"
        return Button {
            Haptics.select()
            model.answerSafety(value)
        } label: {
            Text(LocalizedStringKey(title))
                .font(Typography.data(title == "Not sure" ? 14 : 16, weight: .regular))
                .foregroundStyle(chosen ? Palette.onBone : Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(chosen ? Palette.ink : Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(chosen ? 0 : 0.10)))
                }
        }
        .buttonStyle(PressableCard())
        .disabled(model.submitting)
    }
}
