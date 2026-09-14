import SwiftUI

/// Today's live state on the dial: each meal's state, the day so far, and now.
struct DialToday: Equatable {
    var states: [MealSlot: SlotState]
    /// Nil draws no day-so-far ring or now marker (a schedule preview).
    var nowMin: Int?
    /// The day-so-far ring: accent while watching, green once covered, faint in quiet mode.
    var ringColor: Color = Palette.accent
    /// Quiet mode shows no bells — nothing will check in.
    var showsBells = true
    /// The meal whose check-in has fired.
    var firedSlot: MealSlot?
}

/// The day as a 24-hour dial — SetPoint's motif. Midnight at the top, running
/// clockwise. Usual meal times are knobs on the ring, quiet hours a darker arc,
/// and a bell sits just past each meal where a check-in would come if nothing's
/// logged. It opens the app, the user sets it, and it's their plan at the end.
struct DayDial<Center: View>: View {
    enum Theme { case paper, terra }

    let breakfastMin: Int
    let lunchMin: Int
    let dinnerMin: Int
    let quietStartMin: Int
    let quietEndMin: Int
    var theme: Theme = .paper
    var showsHourLabels = true
    var showsHand = false
    /// How much of the bright ring is drawn (0...1), or nil for none.
    var ringProgress: Double?
    /// Knobs and bells pop in when this flips on.
    var markersShown = true
    /// Live state for Today; nil draws the plain schedule (onboarding).
    var today: DialToday?
    @ViewBuilder var center: () -> Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var meals: [(MealSlot, Int)] {
        [(.breakfast, breakfastMin), (.lunch, lunchMin), (.dinner, dinnerMin)]
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let r = size * 0.33
            let ringWidth = size * 0.076
            let knobSize = min(44, max(18, size * 0.13))
            let bellSize = min(28, max(12, size * 0.082))

            ZStack {
                Circle()
                    .stroke(trackColor, lineWidth: ringWidth)
                    .frame(width: r * 2, height: r * 2)
                    .position(c)

                quietArc(radius: r, width: ringWidth)
                    .position(c)

                if let nowMin = today?.nowMin, let today, nowMin > quietEndMin {
                    Circle()
                        .trim(from: Double(quietEndMin) / 1440, to: Double(nowMin) / 1440)
                        .stroke(today.ringColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: r * 2, height: r * 2)
                        .position(c)
                }

                if let ringProgress {
                    Circle()
                        .trim(from: 0, to: ringProgress)
                        .stroke(theme == .terra ? Palette.background : Palette.accent,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: r * 2, height: r * 2)
                        .position(c)
                }

                if showsHourLabels {
                    ForEach([0, 6, 12, 18], id: \.self) { hour in
                        Text("\(hour)")
                            .font(Typography.data(11, weight: .semibold))
                            .foregroundStyle(labelColor)
                            .position(point(hour * 60, radius: r - size * 0.11, center: c))
                    }
                }

                Image(systemName: "moon.fill")
                    .font(.system(size: size * 0.036, weight: .semibold))
                    .foregroundStyle(theme == .terra ? Palette.background.opacity(0.75) : Palette.inkSoft)
                    .position(point(quietMidpoint, radius: r, center: c))

                if showsHand {
                    LoopingPhase(period: 14, still: 0.54) { t in
                        Capsule()
                            .fill(Palette.background)
                            .frame(width: 3, height: r - 26)
                            .offset(y: -(r - 26) / 2)
                            .rotationEffect(.degrees(t * 360))
                    }
                    .position(c)
                    Circle().fill(Palette.background).frame(width: 12, height: 12).position(c)
                }

                ForEach(Array(meals.enumerated()), id: \.offset) { index, entry in
                    let (slot, minute) = entry
                    let state = today?.states[slot]
                    knob(slot, state: state, size: knobSize)
                        .scaleEffect(markersShown ? 1 : 0.2)
                        .opacity(markersShown ? 1 : 0)
                        .animation(markerAnimation(index), value: markersShown)
                        .position(point(minute, radius: r, center: c))
                    if showsBell(for: state) {
                        PingBell(
                            fill: theme == .terra ? Palette.background : Palette.accentTint,
                            stagger: Double(index) * 0.8,
                            fired: today?.firedSlot == slot,
                            size: bellSize
                        )
                        .scaleEffect(markersShown ? 1 : 0.2)
                        .opacity(markersShown ? 1 : 0)
                        .animation(markerAnimation(index).delay(0.15), value: markersShown)
                        .position(point(CheckInSchedule.minute(afterMeal: minute), radius: r + size * 0.118, center: c))
                    }
                }

                if let nowMin = today?.nowMin {
                    Circle()
                        .fill(Palette.ink)
                        .overlay(Circle().strokeBorder(Palette.background, lineWidth: 3))
                        .frame(width: 13, height: 13)
                        .position(point(nowMin, radius: r, center: c))
                }

                center()
                    .position(c)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Pieces

    @ViewBuilder
    private func knob(_ slot: MealSlot, state: SlotState?, size: CGFloat) -> some View {
        switch state {
        case .logged:
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(Palette.background)
                .frame(width: size, height: size)
                .background(Palette.ink, in: Circle())
                .elevation(.resting)
        case .missed:
            Image(systemName: slot.symbol)
                .font(.system(size: size * 0.39, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: size, height: size)
                .background(Palette.accentTint, in: Circle())
                .overlay(Circle().strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: size > 30 ? 2.5 : 1.5, dash: [4, 3])))
        case .upcoming:
            Image(systemName: slot.symbol)
                .font(.system(size: size * 0.39, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
                .frame(width: size, height: size)
                .background(Palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(Palette.surfaceSunk, lineWidth: 2))
                .elevation(.resting)
        case .now, nil:
            ZStack {
                if state == .now {
                    LoopingPhase(period: 2, still: 1) { t in
                        Circle()
                            .fill(Palette.accentSoft)
                            .scaleEffect(1 + 0.9 * Phase.ramp(t, 0, 0.7))
                            .opacity(0.8 * (1 - Phase.ramp(t, 0, 0.7)))
                    }
                }
                Image(systemName: slot.symbol)
                    .font(.system(size: size * 0.39, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: size, height: size)
                    .background(theme == .terra ? Palette.background : Palette.surface, in: Circle())
                    .overlay {
                        if theme == .paper { Circle().strokeBorder(Palette.accent, lineWidth: size > 30 ? 3 : 2) }
                    }
                    .elevation(.resting)
            }
            .frame(width: size, height: size)
        }
    }

    private func showsBell(for state: SlotState?) -> Bool {
        guard let today else { return true }
        return today.showsBells && state != .logged
    }

    @ViewBuilder
    private func quietArc(radius r: CGFloat, width: CGFloat) -> some View {
        let start = Double(quietStartMin) / 1440
        let end = Double(quietEndMin) / 1440
        let color = theme == .terra ? Palette.ink.opacity(0.22) : Color(hex: 0xE4D9CA)
        ZStack {
            if start <= end {
                Circle().trim(from: start, to: end).stroke(color, lineWidth: width)
            } else {
                Circle().trim(from: start, to: 1).stroke(color, lineWidth: width)
                Circle().trim(from: 0, to: end).stroke(color, lineWidth: width)
            }
        }
        .rotationEffect(.degrees(-90))
        .frame(width: r * 2, height: r * 2)
    }

    // MARK: Geometry

    private func point(_ minute: Int, radius: CGFloat, center: CGPoint) -> CGPoint {
        let angle = CGFloat(minute) / 1440 * 2 * .pi
        return CGPoint(x: center.x + radius * CGFloat(Foundation.sin(Double(angle))),
                       y: center.y - radius * CGFloat(Foundation.cos(Double(angle))))
    }

    private var quietMidpoint: Int {
        let span = (quietEndMin - quietStartMin + 1440) % 1440
        return (quietStartMin + span / 2) % 1440
    }

    private var trackColor: Color {
        theme == .terra ? Palette.background.opacity(0.16) : Palette.surfaceSunk
    }

    private var labelColor: Color {
        theme == .terra ? Palette.background.opacity(0.55) : Palette.inkFaint
    }

    private func markerAnimation(_ index: Int) -> Animation {
        Motion.adaptive(Motion.nudge, reduceMotion: reduceMotion)
            .delay(Motion.stagger(index, step: 0.22, reduceMotion: reduceMotion))
    }

    private var accessibilitySummary: String {
        let times = meals.map { "\($0.0.title) \(formatMinutes($0.1))" }.joined(separator: ", ")
        return "Meal times: \(times). Quiet from \(formatMinutes(quietStartMin)) to \(formatMinutes(quietEndMin))."
    }
}

/// A bell that sends out a soft ring every couple of seconds; solid once it has fired.
private struct PingBell: View {
    let fill: Color
    let stagger: Double
    var fired = false
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            if !fired {
                LoopingPhase(period: 2.4, offset: stagger, still: 1) { t in
                    Circle()
                        .fill(fill)
                        .scaleEffect(0.7 + 1.4 * Phase.ramp(t, 0, 0.7))
                        .opacity(0.8 * (1 - Phase.ramp(t, 0, 0.7)))
                }
            }
            Circle().fill(fired ? Palette.accent : fill)
            Image(systemName: "bell.fill")
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(fired ? .white : Palette.accent)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    DayDial(breakfastMin: 480, lunchMin: 780, dinnerMin: 1140, quietStartMin: 1380, quietEndMin: 420) {
        Text("Standard").font(Typography.voice(26))
    }
    .padding()
    .background(Palette.background)
}
