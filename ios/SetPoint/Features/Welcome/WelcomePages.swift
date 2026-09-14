import SwiftUI

// The four pitch pages. One idea each, a two-line headline, and a looping
// illustration that does the explaining. Loops are phase-driven
// (`LoopingPhase`) and hold a still frame under Reduce Motion.

enum WelcomeLayout {
    /// Room under each page for the controls `WelcomeView` overlays.
    static let controlsClearance: CGFloat = 104
}

/// "Line one." / *line two.* — the pitch's headline voice.
private struct WelcomeHeadline: View {
    let first: String
    let second: String
    var color: Color = Palette.ink
    var accent: Color = Palette.accent
    var size: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(first)
                .font(Typography.display(size))
                .foregroundStyle(color)
                .appearIn(0)
            Text(second)
                .font(Typography.voiceItalic(size))
                .foregroundStyle(accent)
                .appearIn(1)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct WelcomeSubline: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.data(17))
            .foregroundStyle(Palette.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appearIn(2)
    }
}

// MARK: - A · You forget to eat

struct WelcomeHookPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SetPoint")
                .font(Typography.data(13, weight: .bold))
                .tracking(2.4)
                .textCase(.uppercase)
                .foregroundStyle(Palette.background.opacity(0.75))
                .padding(.top, Space.sm)

            Spacer(minLength: Space.sm)

            LoopingPhase(period: 6, still: 0) { t in
                DayDial(
                    breakfastMin: 480, lunchMin: 780, dinnerMin: 1140,
                    quietStartMin: 1380, quietEndMin: 420,
                    theme: .terra, showsHand: true
                ) { EmptyView() }
                    .offset(y: -4 * sin(t * 2 * .pi))
            }
            .frame(maxWidth: 340)
            .frame(maxWidth: .infinity)

            Spacer(minLength: Space.sm)

            WelcomeHeadline(
                first: "You forget to eat.",
                second: "I don’t.",
                color: Palette.background,
                accent: Color(hex: 0xFFE3D3),
                size: 50
            )
            .padding(.bottom, WelcomeLayout.controlsClearance + 30)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - B · Lunch slips. I notice.

struct WelcomeNoticePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Spacer(minLength: Space.md)
            LoopingPhase(period: 7, still: 0.75) { t in
                NoticeScene(t: t)
            }
            .frame(height: 260)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Breakfast logged at 8. Lunch time passes with nothing logged, and a check-in arrives at 13:45.")
            Spacer(minLength: Space.md)
            WelcomeHeadline(first: "Lunch slips.", second: "I notice.")
            WelcomeSubline(text: "Even when the app is closed.")
                .padding(.bottom, WelcomeLayout.controlsClearance)
        }
        .padding(.horizontal, 24)
    }
}

private struct NoticeScene: View {
    let t: Double

    private let windowStart = 360.0, windowEnd = 1320.0

    var body: some View {
        VStack(spacing: 0) {
            CheckInBanner(title: "Lunch slipped", detail: "Nothing logged since breakfast", time: "13:45")
                .opacity(Phase.window(t, 0.5, 0.58, 0.9, 0.97))
                .offset(y: -26 * (1 - Phase.ramp(t, 0.5, 0.58)))
            Spacer()
            dayLine
        }
    }

    private var dayLine: some View {
        GeometryReader { geo in
            let inset: CGFloat = 36
            let width = geo.size.width - inset * 2
            let x: (Double) -> CGFloat = { inset + CGFloat(($0 - windowStart) / (windowEnd - windowStart)) * width }
            let y: CGFloat = 20
            let cursor = 480 + (825 - 480) * Phase.ramp(t, 0.06, 0.55)

            ZStack {
                Image(systemName: "sun.max")
                    .foregroundStyle(Palette.inkFaint)
                    .position(x: 10, y: y)
                Image(systemName: "moon")
                    .foregroundStyle(Palette.inkFaint)
                    .position(x: geo.size.width - 10, y: y)

                Capsule().fill(Palette.surfaceSunk)
                    .frame(width: width, height: 8)
                    .position(x: inset + width / 2, y: y)
                Capsule().fill(Palette.inkFaint.opacity(0.35))
                    .frame(width: x(cursor) - inset, height: 8)
                    .position(x: inset + (x(cursor) - inset) / 2, y: y)

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.background)
                    .frame(width: 30, height: 30)
                    .background(Palette.ink, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.background, lineWidth: 3))
                    .position(x: x(480), y: y)

                ZStack {
                    Circle()
                        .fill(Palette.accentSoft)
                        .scaleEffect(0.7 + 1.4 * Phase.ramp((t * 3.5).truncatingRemainder(dividingBy: 1), 0, 0.7))
                        .opacity(0.8 * (1 - Phase.ramp((t * 3.5).truncatingRemainder(dividingBy: 1), 0, 0.7)))
                    Circle().fill(Palette.surfaceRaised)
                    Circle().strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 2.5, dash: [4, 3]))
                }
                .frame(width: 36, height: 36)
                .position(x: x(780), y: y)

                Circle()
                    .strokeBorder(Palette.inkFaint, lineWidth: 2)
                    .background(Circle().fill(Palette.surfaceRaised))
                    .frame(width: 22, height: 22)
                    .position(x: x(1140), y: y)

                Capsule().fill(Palette.ink)
                    .frame(width: 3, height: 40)
                    .position(x: x(cursor), y: y)

                timeLabel("8:00", color: Palette.inkSoft).position(x: x(480), y: y + 42)
                timeLabel("13:00", color: Palette.accentDeep).position(x: x(780), y: y + 42)
                timeLabel("19:00", color: Palette.inkFaint).position(x: x(1140), y: y + 42)
            }
        }
        .frame(height: 70)
    }

    private func timeLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Typography.data(12, weight: .bold))
            .foregroundStyle(color)
            .monospacedDigit()
    }
}

/// A notification-shaped card.
private struct CheckInBanner: View {
    let title: String
    let detail: String
    let time: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.background)
                .frame(width: 40, height: 40)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(Typography.data(15, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(time)
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkFaint)
                }
                Text(detail)
                    .font(Typography.data(14))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Palette.surfaceRaised)
                .elevation(.lifted)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.hairline))
        }
    }
}

// MARK: - C · Not a nag. A plan.

struct WelcomePlanPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Spacer(minLength: Space.md)
            LoopingPhase(period: 6, still: 0.8) { t in
                PlanCard(t: t)
            }
            .padding(.horizontal, Space.sm)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("A check-in suggests lunch: chicken breast, rice and olive oil. One tap on I ate this logs it.")
            Spacer(minLength: Space.md)
            WelcomeHeadline(first: "Not a nag.", second: "A plan.")
            WelcomeSubline(text: "Exactly what to eat. One tap to log.")
                .padding(.bottom, WelcomeLayout.controlsClearance)
        }
        .padding(.horizontal, 24)
    }
}

private struct PlanCard: View {
    let t: Double

    private let items: [(symbol: String, name: String, kcal: Int)] = [
        ("fork.knife", "Chicken breast", 248),
        ("takeoutbag.and.cup.and.straw.fill", "White rice", 205),
        ("drop.fill", "Olive oil", 119),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Check-in · 13:45")
                .sectionLabelStyle(Palette.accent)
            Text("Here’s your lunch.")
                .font(Typography.voice(24))
                .foregroundStyle(Palette.ink)

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let shown = Phase.window(t, 0.03 + Double(index) * 0.04, 0.1 + Double(index) * 0.04, 0.88, 0.96)
                HStack(spacing: 12) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 34, height: 34)
                        .background(Palette.surfaceSunk, in: Circle())
                    Text(item.name)
                        .font(Typography.data(16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(item.kcal) kcal")
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkFaint)
                }
                .opacity(shown)
                .offset(y: 10 * (1 - shown))
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.accent)
                Text("I ate this")
                    .font(Typography.data(16, weight: .bold))
                    .foregroundStyle(.white)
                Circle()
                    .fill(.white)
                    .frame(width: 40, height: 40)
                    .scaleEffect(0.4 + 3.6 * Phase.ramp(t, 0.52, 0.72))
                    .opacity(t > 0.52 ? 0.55 * (1 - Phase.ramp(t, 0.52, 0.72)) : 0)
                    .offset(x: 60)
            }
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 4)
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Palette.surface)
                .elevation(.lifted)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Palette.hairline))
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Palette.background)
                .frame(width: 60, height: 60)
                .background(Palette.ink, in: Circle())
                .overlay(Circle().strokeBorder(Palette.background, lineWidth: 4))
                .scaleEffect(Phase.ramp(t, 0.6, 0.7))
                .rotationEffect(.degrees(-20 * (1 - Phase.ramp(t, 0.6, 0.7))))
                .opacity(Phase.window(t, 0.6, 0.65, 0.9, 0.97))
                .offset(x: 14, y: -14)
        }
        .offset(y: -4 * sin(t * 2 * .pi))
    }
}

// MARK: - D · Firm. Then quiet.

struct WelcomeQuietPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Spacer(minLength: Space.md)
            LoopingPhase(period: 7, still: 0.8) { t in
                EscalationScene(t: t)
            }
            .frame(height: 280)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("If you ignore a check-in: a nudge, then firm, then a talk — then I go quiet.")
            Spacer(minLength: Space.md)
            WelcomeHeadline(first: "Firm.", second: "Then quiet.")
            WelcomeSubline(text: "No streaks. No guilt. No endless pings.")
                .padding(.bottom, WelcomeLayout.controlsClearance)
        }
        .padding(.horizontal, 24)
    }
}

private struct EscalationScene: View {
    let t: Double

    private struct Node {
        let x: CGFloat, y: CGFloat, size: CGFloat
        let fill: Color, symbol: String, tint: Color
        let label: String, start: Double
    }

    private let nodes = [
        Node(x: 70, y: 196, size: 38, fill: Palette.accentTint, symbol: "bell.fill", tint: Palette.accent, label: "Nudge", start: 0.06),
        Node(x: 150, y: 146, size: 46, fill: Palette.accent, symbol: "bell.fill", tint: .white, label: "Firm", start: 0.14),
        Node(x: 230, y: 96, size: 46, fill: Palette.accentDeep, symbol: "bubble.left.fill", tint: Palette.background, label: "Let’s talk", start: 0.23),
        Node(x: 316, y: 216, size: 42, fill: Palette.surfaceSunk, symbol: "moon.fill", tint: Palette.inkSoft, label: "Quiet", start: 0.36),
    ]

    var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width / 350, sy = geo.size.height / 280
            let p: (CGFloat, CGFloat) -> CGPoint = { CGPoint(x: $0 * sx, y: $1 * sy) }
            let path = Path { path in
                path.move(to: p(10, 236))
                path.addLine(to: p(70, 196))
                path.addLine(to: p(150, 146))
                path.addLine(to: p(230, 96))
                path.addCurve(to: p(316, 216), control1: p(268, 72), control2: p(272, 216))
                path.addLine(to: p(344, 216))
            }
            let line = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)

            ZStack {
                path.stroke(Palette.accentSoft, style: line)
                path.trim(from: 0, to: Phase.ramp(t, 0, 0.45)).stroke(Palette.accent, style: line)

                ForEach(Array(nodes.enumerated()), id: \.offset) { _, node in
                    let pop = Phase.ramp(t, node.start, node.start + 0.06)
                    VStack(spacing: 8) {
                        Image(systemName: node.symbol)
                            .font(.system(size: node.size * 0.4, weight: .semibold))
                            .foregroundStyle(node.tint)
                            .frame(width: node.size, height: node.size)
                            .background(node.fill, in: Circle())
                            .elevation(.resting)
                        Text(node.label)
                            .font(Typography.data(12, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize()
                    }
                    .scaleEffect(0.2 + 0.8 * pop)
                    .opacity(pop * (1 - Phase.ramp(t, 0.88, 0.96)))
                    .position(x: node.x * sx, y: node.y * sy + 20)
                }
            }
        }
    }
}
