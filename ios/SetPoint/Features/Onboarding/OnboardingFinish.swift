import SwiftUI

// After the plan is saved: ask for notifications (check-ins are the product),
// then the payoff — tomorrow as a list of plates.

// MARK: - Notifications

struct ReachStep: View {
    @Bindable var model: OnboardingViewModel
    @Environment(AppEnvironment.self) private var env
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            StepHeadline(text: "Let me reach you.")

            LockScreenPreview(minute: CheckInSchedule.minute(afterMeal: model.draft.lunchMin))
                .frame(maxWidth: 300, maxHeight: 400)
                .frame(maxWidth: .infinity)
                .appearIn(1)

            Spacer(minLength: 0)

            VStack(spacing: Space.xxs) {
                ActionButton(title: "Turn on check-ins", busy: asking, busyTitle: "One moment") {
                    guard !asking else { return }
                    asking = true
                    Task {
                        await env.push.requestAuthorization()
                        asking = false
                        model.advance()
                    }
                }
                Button("Not now") { model.advance() }
                    .font(Typography.data(15, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.vertical, 12)
                    .disabled(asking)
            }
            .appearIn(2)
        }
    }
}

/// A lock screen with a check-in dropping in, on loop.
private struct LockScreenPreview: View {
    let minute: Int

    private var dateLine: String {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        return tomorrow.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(RadialGradient(
                    colors: [Color(hex: 0x6E2A12), Color(hex: 0x24141A), Palette.lockScreenInk],
                    center: UnitPoint(x: 0.2, y: 0), startRadius: 0, endRadius: 440
                ))
                .elevation(.lifted)

            VStack(spacing: 0) {
                Text(dateLine)
                    .font(Typography.data(15, weight: .semibold))
                    .foregroundStyle(Palette.lockScreenText.opacity(0.75))
                    .padding(.top, 40)
                Text(String(format: "%d:%02d", minute / 60, minute % 60))
                    .font(Typography.data(80, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(Palette.lockScreenText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                LoopingPhase(period: 6, still: 0.75) { t in
                    let shown = Phase.window(t, 0.45, 0.55, 0.9, 0.97)
                    notification
                        .opacity(shown)
                        .offset(y: -26 * (1 - Phase.ramp(t, 0.45, 0.55)))
                }
                .padding(.horizontal, 14)
                .padding(.top, 28)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A check-in notification on your lock screen: lunch slipped, nothing logged since breakfast.")
    }

    private var notification: some View {
        HStack(spacing: 10) {
            FuelOrb(size: 38, breathing: false, glow: 0.2)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text("Lunch slipped")
                        .font(Typography.data(14, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("now")
                        .font(Typography.data(11))
                        .foregroundStyle(Palette.inkSoft)
                }
                Text("Nothing logged since breakfast.")
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.hairline))
    }
}

// MARK: - Covered

struct CoveredStep: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var markers = false
    @State private var showingPaywall = false

    var body: some View {
        Group {
            if model.enforcementEnabled {
                covered
            } else {
                quiet
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(onFinished: { model.advance() }, onSkip: { model.advance() })
        }
    }

    /// Tomorrow as plates, not a daily number: a big kcal total reads as a
    /// wall to someone who struggles to eat. The total stays, small.
    private var covered: some View {
        let d = model.draft
        let meals = [("Breakfast", d.breakfastMin), ("Lunch", d.lunchMin), ("Dinner", d.dinnerMin)]
        let plate = model.result.map { plateKcal($0.dailyKcalTarget) }
        return VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your plan is ready")
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
                Headline("Three plates.", tail: "That’s the whole job.", size: 36)
                Text("I only speak up if one slips or runs light.")
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }
            .appearIn(0, rise: 16)

            VStack(spacing: 0) {
                ForEach(Array(meals.enumerated()), id: \.offset) { index, meal in
                    HStack(spacing: 14) {
                        Text(formatMinutes(meal.1))
                            .font(Typography.mono(13))
                            .foregroundStyle(Palette.inkSoft)
                            .frame(width: 48, alignment: .leading)
                        Circle()
                            .fill(Palette.amber)
                            .frame(width: 8, height: 8)
                            .shadow(color: Palette.amber.opacity(0.6), radius: 5)
                        (Text(meal.0).foregroundColor(Palette.ink)
                            + Text("  check-in \(formatMinutes(CheckInSchedule.minute(afterMeal: meal.1)))").font(Typography.data(13, weight: .regular)).foregroundColor(Palette.inkFaint))
                            .font(Typography.data(16, weight: .regular))
                        Spacer(minLength: 8)
                        if let plate {
                            Text("~\(plate.formatted())")
                                .font(Typography.mono(14))
                                .foregroundStyle(Palette.ink)
                        }
                    }
                    .padding(.vertical, 13)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                    }
                    .staggerReveal(markers, index: index + 1, rise: 14)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(planAccessibilityLabel(meals))

            if let result = model.result {
                HStack(spacing: 10) {
                    stat("A day", value: result.dailyKcalTarget.formatted(), unit: "kcal", note: "Short at night? I’ll help close it.")
                    if let protein = result.dailyProteinTargetG {
                        stat("Protein", value: "\(protein)", unit: "g", note: "Spread over the plates")
                    }
                }
                .staggerReveal(markers, index: 5, rise: 14)
            }

            Spacer(minLength: Space.md)

            ActionButton(title: "Start my day") { showingPaywall = true }
                .staggerReveal(markers, index: 6, rise: 14)
        }
        .background(alignment: .topLeading) {
            RadialGradient(colors: [Palette.ember.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 210)
                .frame(width: 420, height: 420)
                .blur(radius: 30)
                .offset(x: -120, y: 100)
                .allowsHitTesting(false)
        }
        .onAppear(perform: reveal)
    }

    private func stat(_ label: String, value: String, unit: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(Typography.mono(10)).tracking(1.2).textCase(.uppercase).foregroundStyle(Palette.inkFaint)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(Typography.data(21, weight: .light)).foregroundStyle(Palette.ink)
                Text(unit).font(Typography.data(12, weight: .regular)).foregroundStyle(Palette.inkSoft)
            }
            Text(note)
                .font(Typography.data(12, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 18)
    }

    private func plateKcal(_ total: Int) -> Int {
        Int((Double(total) / 3 / 10).rounded()) * 10
    }

    private func totalLine(_ total: Int) -> String {
        let protein = model.result?.dailyProteinTargetG.map { " · \($0) g protein" } ?? ""
        return "\(total.formatted()) kcal a day\(protein). Short in the evening? I’ll help close it."
    }

    private func planAccessibilityLabel(_ meals: [(String, Int)]) -> String {
        let list = meals.map { "\($0.0) at \(formatMinutes($0.1))" }.joined(separator: ", ")
        return "\(list). A check-in comes 45 minutes after each if it doesn’t show."
    }

    private var quiet: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            FuelOrb(size: 64, dimmed: true)
                .appearIn(0)
            Headline("Quiet mode is on.", tail: "No check-ins.", size: 40)
                .appearIn(0)
            Text(quietCopy)
                .font(Typography.data(17))
                .foregroundStyle(Palette.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .appearIn(1)
            Spacer()
            // No upsell here: someone in quiet mode was flagged by the safety screen.
            ActionButton(title: "Start") { model.advance() }
        }
    }

    private var quietCopy: String {
        switch model.result?.enforcementDisabledReason {
        case "EATING_DISORDER_SCREEN":
            return "I won’t push you to eat. If eating feels hard right now, a qualified healthcare professional or local eating-disorder service can offer support that an app can’t."
        default:
            return "I won’t push you to eat — that’s your care team’s call, not an app’s. This isn’t a substitute for their plan."
        }
    }

    private func reveal() {
        guard !reduceMotion else {
            markers = true
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { markers = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { Haptics.landed() }
    }
}
