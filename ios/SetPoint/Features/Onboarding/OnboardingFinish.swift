import SwiftUI

// After the plan is saved: ask for notifications (check-ins are the product),
// then the payoff — the day dial as the user's plan.

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
                    colors: [Color(hex: 0xB5532F), Color(hex: 0x5A3A2C), Palette.lockScreenInk],
                    center: UnitPoint(x: 0.2, y: 0), startRadius: 0, endRadius: 440
                ))
                .elevation(.lifted)

            VStack(spacing: 0) {
                Text(dateLine)
                    .font(Typography.data(15, weight: .semibold))
                    .foregroundStyle(Palette.lockScreenText.opacity(0.75))
                    .padding(.top, 40)
                Text(String(format: "%d:%02d", minute / 60, minute % 60))
                    .font(Typography.data(80, weight: .bold))
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
            Image(systemName: "fork.knife")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.background)
                .frame(width: 38, height: 38)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
        .background(Palette.background.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Covered

struct CoveredStep: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var ring: Double = 0
    @State private var markers = false
    @State private var shownKcal = 0
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
        return VStack(alignment: .leading, spacing: Space.xs) {
            Text("Here’s tomorrow.")
                .font(Typography.display(44))
                .foregroundStyle(Palette.background)
                .appearIn(0)
            Text("Three plates. I only speak up if one slips or runs light.")
                .font(Typography.data(17))
                .foregroundStyle(Palette.background.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .appearIn(1)

            Spacer(minLength: Space.sm)

            DayDial(
                breakfastMin: d.breakfastMin, lunchMin: d.lunchMin, dinnerMin: d.dinnerMin,
                quietStartMin: d.quietStartMin, quietEndMin: d.quietEndMin,
                theme: .terra, showsHourLabels: false, ringProgress: ring, markersShown: markers
            ) {
                VStack(spacing: 2) {
                    Text(shownKcal.formatted())
                        .font(Typography.data(40, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(shownKcal)))
                        .foregroundStyle(Palette.background)
                    Text("kcal a plate")
                        .font(Typography.data(13, weight: .semibold))
                        .foregroundStyle(Palette.background.opacity(0.7))
                }
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: 300)
            .frame(maxWidth: .infinity)

            Spacer(minLength: Space.sm)

            VStack(spacing: 0) {
                ForEach(Array(meals.enumerated()), id: \.offset) { index, meal in
                    if index > 0 {
                        Rectangle().fill(Palette.background.opacity(0.18)).frame(height: 1)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(formatMinutes(meal.1))
                            .font(Typography.data(15, weight: .bold))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .leading)
                        Text(meal.0)
                            .font(Typography.data(15, weight: .bold))
                        Spacer(minLength: Space.xs)
                        Label(formatMinutes(CheckInSchedule.minute(afterMeal: meal.1)), systemImage: "bell.fill")
                            .font(Typography.data(13, weight: .semibold))
                            .opacity(0.75)
                    }
                    .foregroundStyle(Palette.background)
                    .padding(.vertical, 10)
                }
            }
            .opacity(markers ? 1 : 0)
            .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion).delay(0.5), value: markers)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(planAccessibilityLabel(meals))

            if let total = model.result?.dailyKcalTarget {
                Text(totalLine(total))
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.background.opacity(0.7))
                    .opacity(markers ? 1 : 0)
            }

            Spacer(minLength: Space.md)

            Button { showingPaywall = true } label: {
                Text("Start")
                    .font(Typography.data(17, weight: .bold))
                    .foregroundStyle(Palette.accentDeep)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressableCard())
        }
        .onAppear(perform: reveal)
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
            Text("Quiet mode is on.")
                .font(Typography.display(40))
                .foregroundStyle(Palette.ink)
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
        guard let total = model.result?.dailyKcalTarget else { return }
        let target = plateKcal(total)
        guard !reduceMotion else {
            ring = 1
            markers = true
            shownKcal = target
            return
        }
        withAnimation(.easeInOut(duration: 1.6).delay(0.3)) { ring = 1 }
        withAnimation(Motion.nudge.delay(0.9)) { markers = true }
        withAnimation(.easeOut(duration: 1.0).delay(1.1)) { shownKcal = target }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { Haptics.landed() }
    }
}
