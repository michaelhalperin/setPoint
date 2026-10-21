import SwiftUI

// After the plan is saved: ask for notifications (check-ins are the product),
// then the payoff — tomorrow as a list of plates.

// MARK: - Notifications

struct ReachStep: View {
    @Bindable var model: OnboardingViewModel
    @Environment(AppEnvironment.self) private var env
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LockScreenPreview(minute: CheckInSchedule.minute(afterMeal: model.draft.lunchMin))
                .frame(height: 290)
                .padding(.top, 6)
                .appearIn(0, rise: 0)

            Headline("Let me reach you.", tail: "Only when a meal slips.", size: 36)
                .appearIn(1, rise: 16)

            DotLines(lines: [
                "At most 4 a day, and only if a plate slips",
                "Never between \(formatMinutes(model.draft.quietStartMin)) and \(formatMinutes(model.draft.quietEndMin))",
                "Answer from the lock screen in one tap",
            ])
            .appearIn(2, rise: 16)

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                ActionButton(title: "Allow notifications", busy: asking, busyTitle: "One moment") {
                    guard !asking else { return }
                    asking = true
                    Task {
                        await env.push.requestAuthorization()
                        asking = false
                        model.advance()
                    }
                }
                Button("Not now · check-ins won’t reach you") { model.advance() }
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(asking)
            }
            .appearIn(3, rise: 16)
        }
        .background(alignment: .top) {
            ZStack {
                RadialGradient(colors: [Palette.ember.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: 220)
                RadialGradient(colors: [Palette.haze.opacity(0.2), .clear], center: UnitPoint(x: 0.8, y: 0.3), startRadius: 0, endRadius: 200)
            }
            .frame(width: 510, height: 420)
            .blur(radius: 30)
            .offset(y: 20)
            .allowsHitTesting(false)
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
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1A1420), Color(hex: 0x0E0E12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.08)))

            VStack(spacing: 0) {
                Text(dateLine)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.ink.opacity(0.8))
                Text(formatMinutes(minute))
                    .font(.system(size: 64, weight: .light))
                    .tracking(-2.5)
                    .foregroundStyle(Palette.ink)
            }
            .padding(.top, 26)

            LoopingPhase(period: 6, still: 0.75) { t in
                let shown = Phase.window(t, 0.25, 0.35, 0.9, 0.97)
                notification
                    .opacity(shown)
                    .offset(y: -30 * (1 - Phase.ramp(t, 0.25, 0.35)))
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A check-in notification on your lock screen: lunch slipped, with a plate you can get down.")
    }

    private var notification: some View {
        HStack(alignment: .top, spacing: 10) {
            FuelOrb(size: 18, breathing: false, glow: 0)
                .frame(width: 34, height: 34)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Lunch slipped")
                        .font(Typography.data(14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("now")
                        .font(Typography.data(11, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                }
                Text("Here’s 680 kcal you can get down in 5 minutes.")
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Color(hex: 0xD4D4D8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(hex: 0x28282E, opacity: 0.85), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
    }
}

// MARK: - Covered

struct CoveredStep: View {
    @Bindable var model: OnboardingViewModel
    @Environment(AppEnvironment.self) private var env
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

            ActionButton(title: "Start my day") { startDay() }
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
                .hintCopy()
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
        return L10n( "\(total.formatted()) kcal a day\(protein). Short in the evening? I’ll help close it.")
    }

    private func planAccessibilityLabel(_ meals: [(String, Int)]) -> String {
        let list = meals.map { "\($0.0) at \(formatMinutes($0.1))" }.joined(separator: ", ")
        return L10n( "\(list). A check-in comes 45 minutes after each if it doesn’t show.")
    }

    private var quiet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)
            Circle()
                .fill(RadialGradient(
                    stops: [
                        .init(color: Color(hex: 0xF4F4F5), location: 0),
                        .init(color: Color(hex: 0xA1A1AA), location: 0.3),
                        .init(color: Color(hex: 0x3F3F46), location: 0.7),
                        .init(color: Color(hex: 0x18181B), location: 1),
                    ],
                    center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: 125
                ))
                .frame(width: 160, height: 160)
                .shadow(color: Color(hex: 0xA1A1AA, opacity: 0.25), radius: 30)
                .opacity(0.8)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text("Quiet mode").sectionLabelStyle()
                .appearIn(1, rise: 16)
            Headline("No check-ins.", tail: "Log when you like.", size: 40)
                .appearIn(2, rise: 16)
            Text(quietCopy)
                .font(Typography.data(15, weight: .regular))
                .foregroundStyle(Color(hex: 0xD4D4D8))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .appearIn(3, rise: 16)
            Text("You can still log meals and see your week. No targets, no reminders.")
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .appearIn(4, rise: 16)
            // No upsell here: someone in quiet mode was flagged by the safety screen.
            ActionButton(title: "Start") { model.advance() }
                .padding(.top, 8)
                .appearIn(5, rise: 16)
        }
    }

    private var quietCopy: String {
        switch model.result?.enforcementDisabledReason {
        case "EATING_DISORDER_SCREEN":
            return L10n( "From your answers, I won’t push you to eat. If eating feels hard right now, a doctor or an eating-disorder service can help in a way an app can’t.")
        default:
            return L10n( "I won’t push you to eat — that’s your care team’s call, not an app’s. This isn’t a substitute for their plan.")
        }
    }

    private func startDay() {
        if env.flags.isOn(.paywall) {
            showingPaywall = true
        } else {
            model.advance()
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
