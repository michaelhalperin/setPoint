import SwiftUI
import UIKit

struct DialGhost: Equatable, Identifiable {
    var id: String { slot.rawValue }
    let slot: MealSlot
    let minute: Int
    var label: String? = nil
}

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

/// The day as a 24-hour clock — SetPoint's motif. Midnight at the top, running
/// clockwise. The face stays quiet and clock-like; the chapter ring carries
/// quiet hours, meal knobs, a filled arc for the day so far, and a pip
/// at now. A bell sits just past each meal where a check-in would come if
/// nothing's logged. It opens the app, the user sets it, and it's their plan.
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
    /// Hatched arcs just outside the ring — busy blocks for today.
    var busyArcs: [ClosedRange<Int>] = []
    /// Dark rim marks for today's workouts.
    var workoutArcs: [ClosedRange<Int>] = []
    /// Green rim marks for the post-workout refuel window.
    var refuelArcs: [ClosedRange<Int>] = []
    /// Dashed knobs at a meal's usual time after calendar moved the live knob.
    var ghostKnobs: [DialGhost] = []
    /// When set, knobs can be dragged around the ring. Onboarding leaves this nil.
    var onMove: ((MealSlot, Int) -> Void)? = nil
    @ViewBuilder var center: () -> Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragging: MealSlot?

    private var meals: [(MealSlot, Int)] {
        [(.breakfast, breakfastMin), (.lunch, lunchMin), (.dinner, dinnerMin)]
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let r = size * 0.35
            let ringWidth = min(18, max(7, size * 0.052))
            let knobSize = min(44, max(18, size * 0.13))
            let bellSize = min(28, max(12, size * 0.082))
            let faceR = r - ringWidth / 2 - max(4, size * 0.014)

            ZStack {
                Circle()
                    .fill(faceColor)
                    .overlay {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.clear, innerShade],
                                    center: .center,
                                    startRadius: faceR * 0.52,
                                    endRadius: faceR
                                )
                            )
                    }
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(faceStroke, lineWidth: 1))
                    .frame(width: faceR * 2, height: faceR * 2)
                    .position(c)
                    .allowsHitTesting(false)

                Circle()
                    .stroke(trackColor, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .frame(width: r * 2, height: r * 2)
                    .position(c)
                    .allowsHitTesting(false)

                arc(from: quietStartMin, to: quietEndMin, color: quietColor, width: ringWidth, radius: r, cap: .butt)
                    .position(c)
                    .allowsHitTesting(false)

                if let end = elapsedEndMin, let today {
                    arc(from: quietEndMin, to: end, color: today.ringColor, width: ringWidth, radius: r, cap: .butt)
                        .position(c)
                        .allowsHitTesting(false)
                }

                if let ringProgress {
                    Circle()
                        .trim(from: 0, to: ringProgress)
                        .stroke(
                            theme == .terra ? Palette.background : Palette.accent,
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: r * 2, height: r * 2)
                        .position(c)
                        .allowsHitTesting(false)
                }

                DialTicks(center: c, radius: faceR, color: tickColor)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)

                if showsHourLabels, size > 200 {
                    ForEach([0, 6, 12, 18], id: \.self) { hour in
                        Text(DialClock.cardinalLabel(hour))
                            .font(Typography.data(size > 220 ? 11 : 9, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(labelColor)
                            .padding(3)
                            .background(faceColor.opacity(0.92), in: Capsule())
                            .position(point(hour * 60, radius: faceR - size * 0.052, center: c))
                            .allowsHitTesting(false)
                    }
                }

                moonMark(size: max(15, ringWidth * 0.92), at: point(quietMidpoint, radius: r, center: c))

                ForEach(Array(busyArcs.enumerated()), id: \.offset) { _, range in
                    arc(
                        from: range.lowerBound,
                        to: range.upperBound,
                        color: Palette.ink.opacity(0.28),
                        width: max(4, ringWidth * 0.38),
                        radius: r + ringWidth * 0.72,
                        cap: .butt,
                        dashes: [3, 3]
                    )
                    .position(c)
                    .allowsHitTesting(false)
                }

                ForEach(Array(workoutArcs.enumerated()), id: \.offset) { _, range in
                    arc(
                        from: range.lowerBound,
                        to: range.upperBound,
                        color: Palette.ink.opacity(0.72),
                        width: max(5, ringWidth * 0.42),
                        radius: r + ringWidth * 0.72,
                        cap: .round
                    )
                    .position(c)
                    .allowsHitTesting(false)
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: max(9, ringWidth * 0.55), weight: .bold))
                        .foregroundStyle(Palette.background)
                        .frame(width: max(18, ringWidth * 1.15), height: max(18, ringWidth * 1.15))
                        .background(Palette.ink, in: Circle())
                        .position(point(range.lowerBound, radius: r + ringWidth * 0.72, center: c))
                        .allowsHitTesting(false)
                }

                ForEach(Array(refuelArcs.enumerated()), id: \.offset) { _, range in
                    arc(
                        from: range.lowerBound,
                        to: range.upperBound,
                        color: Palette.dayOnTrack.opacity(0.9),
                        width: max(4, ringWidth * 0.38),
                        radius: r + ringWidth * 0.72,
                        cap: .round
                    )
                    .position(c)
                    .allowsHitTesting(false)
                }

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
                    let knobPoint = point(minute, radius: r, center: c)
                    movableKnob(slot, state: state, size: knobSize, at: knobPoint, center: c, index: index)
                    if dragging == slot {
                        Text(formatMinutes(minute))
                            .font(Typography.data(11, weight: .bold))
                            .foregroundStyle(Palette.background)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Palette.ink, in: Capsule())
                            .position(point(minute, radius: r + knobSize * 0.72 + 12, center: c))
                            .allowsHitTesting(false)
                    }
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
                        .position(point(CheckInSchedule.minute(afterMeal: minute), radius: r + size * 0.105, center: c))
                    }
                }

                ForEach(ghostKnobs) { ghost in
                    Circle()
                        .strokeBorder(Palette.ink.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .frame(width: knobSize * 0.7, height: knobSize * 0.7)
                        .position(point(ghost.minute, radius: r, center: c))
                        .allowsHitTesting(false)
                    if let label = ghost.label {
                        Text(label)
                            .font(Typography.data(10, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Palette.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.hairline))
                            .position(point(ghost.minute, radius: r + knobSize * 0.7, center: c))
                            .allowsHitTesting(false)
                    }
                }

                if let nowMin = today?.nowMin {
                    nowMarker(nowMin: nowMin, radius: r, ringWidth: ringWidth, faceR: faceR, center: c, size: size)
                }

                center()
                    .position(c)
            }
            .coordinateSpace(name: "dayDial")
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Pieces

    @ViewBuilder
    private func arc(
        from startMin: Int,
        to endMin: Int,
        color: Color,
        width: CGFloat,
        radius r: CGFloat,
        cap: CGLineCap,
        dashes: [CGFloat]? = nil
    ) -> some View {
        let start = Double(((startMin % 1440) + 1440) % 1440) / 1440
        let end = Double(((endMin % 1440) + 1440) % 1440) / 1440
        let style = StrokeStyle(lineWidth: width, lineCap: cap, dash: dashes ?? [])
        ZStack {
            if start <= end {
                Circle().trim(from: start, to: end).stroke(color, style: style)
            } else {
                Circle().trim(from: start, to: 1).stroke(color, style: style)
                Circle().trim(from: 0, to: end).stroke(color, style: style)
            }
        }
        .rotationEffect(.degrees(-90))
        .frame(width: r * 2, height: r * 2)
    }

    private func moonMark(size: CGFloat, at point: CGPoint) -> some View {
        ZStack {
            Circle().fill(quietColor)
            Image(systemName: "moon.fill")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(theme == .terra ? Palette.background.opacity(0.9) : Palette.inkSoft)
        }
        .frame(width: size, height: size)
        .position(point)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func nowMarker(
        nowMin: Int,
        radius r: CGFloat,
        ringWidth: CGFloat,
        faceR: CGFloat,
        center c: CGPoint,
        size: CGFloat
    ) -> some View {
        let pip = min(16, max(10, ringWidth * 0.7))
        let stub = max(9, size * 0.038)
        ZStack {
            Capsule()
                .fill(theme == .terra ? Palette.background : Palette.ink)
                .frame(width: max(2, size * 0.007), height: stub)
                .offset(y: -(faceR - stub / 2 - 1))
                .rotationEffect(.degrees(Double(nowMin) / 1440 * 360))
                .position(c)
            Circle()
                .fill(today?.ringColor ?? Palette.ink)
                .overlay(Circle().strokeBorder(
                    theme == .terra ? Palette.accent : Palette.background,
                    lineWidth: 2.5
                ))
                .frame(width: pip, height: pip)
                .position(point(nowMin, radius: r, center: c))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

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

    // MARK: Dragging

    @ViewBuilder
    private func movableKnob(
        _ slot: MealSlot,
        state: SlotState?,
        size: CGFloat,
        at knobPoint: CGPoint,
        center: CGPoint,
        index: Int
    ) -> some View {
        let visual = knob(slot, state: state, size: size)
            .scaleEffect((markersShown ? 1 : 0.2) * (dragging == slot ? 1.15 : 1))
            .opacity(markersShown ? 1 : 0)
            .animation(markerAnimation(index), value: markersShown)
        if onMove != nil {
            visual
                .frame(width: max(44, size), height: max(44, size))
                .contentShape(Circle())
                .position(knobPoint)
                .gesture(dragGesture(slot, center: center))
        } else {
            visual.position(knobPoint)
        }
    }

    private func dragGesture(_ slot: MealSlot, center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("dayDial"))
            .onChanged { value in
                dragging = slot
                let raw = MealTimeEditing.minute(at: value.location, center: center)
                let clamped = MealTimeEditing.clamp(
                    raw, slot: slot,
                    breakfast: breakfastMin, lunch: lunchMin, dinner: dinnerMin
                )
                guard clamped != minute(for: slot) else { return }
                UISelectionFeedbackGenerator().selectionChanged()
                onMove?(slot, clamped)
            }
            .onEnded { _ in dragging = nil }
    }

    private func minute(for slot: MealSlot) -> Int {
        switch slot {
        case .breakfast: return breakfastMin
        case .lunch: return lunchMin
        case .dinner: return dinnerMin
        }
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

    /// Waking-day fill ends at now, capped at lights-out.
    private var elapsedEndMin: Int? {
        guard let now = today?.nowMin, now > quietEndMin else { return nil }
        return quietStartMin > quietEndMin ? min(now, quietStartMin) : now
    }

    private var trackColor: Color {
        theme == .terra ? Palette.background.opacity(0.16) : Palette.surfaceSunk
    }

    private var quietColor: Color {
        theme == .terra ? Palette.ink.opacity(0.28) : Palette.quietArc
    }

    private var faceColor: Color {
        theme == .terra ? Palette.background.opacity(0.12) : Palette.surfaceRaised
    }

    private var innerShade: Color {
        theme == .terra ? Palette.ink.opacity(0.055) : Palette.surfaceSunk.opacity(0.42)
    }

    private var faceStroke: Color {
        theme == .terra ? Palette.background.opacity(0.12) : Palette.hairline
    }

    private var tickColor: Color {
        theme == .terra ? Palette.background.opacity(0.45) : Palette.inkFaint
    }

    private var labelColor: Color {
        theme == .terra ? Palette.background.opacity(0.6) : Palette.inkSoft
    }

    private func markerAnimation(_ index: Int) -> Animation {
        Motion.adaptive(Motion.nudge, reduceMotion: reduceMotion)
            .delay(Motion.stagger(index, step: 0.22, reduceMotion: reduceMotion))
    }

    private var accessibilitySummary: String {
        let times = meals.map { "\($0.0.title) \(formatMinutes($0.1))" }.joined(separator: ", ")
        var summary = "Meal times: \(times). Quiet from \(formatMinutes(quietStartMin)) to \(formatMinutes(quietEndMin))."
        if let now = today?.nowMin {
            summary += " Now \(formatMinutes(now))."
        }
        return summary
    }
}

/// Hour ticks on the dial face — majors at midnight, 6, noon, 6pm.
private struct DialTicks: View {
    let center: CGPoint
    let radius: CGFloat
    let color: Color

    var body: some View {
        Canvas { context, _ in
            for hour in 0..<24 {
                let major = hour % 6 == 0
                let midnight = hour == 0
                let angle = Double(hour) / 24 * 2 * .pi
                let len: CGFloat = radius * (midnight ? 0.13 : major ? 0.1 : 0.055)
                let outer = radius - 1
                let inner = outer - max(2.5, len)
                var path = Path()
                path.move(to: CGPoint(
                    x: center.x + inner * CGFloat(sin(angle)),
                    y: center.y - inner * CGFloat(cos(angle))
                ))
                path.addLine(to: CGPoint(
                    x: center.x + outer * CGFloat(sin(angle)),
                    y: center.y - outer * CGFloat(cos(angle))
                ))
                context.stroke(
                    path,
                    with: .color(color.opacity(major ? 1 : 0.45)),
                    lineWidth: midnight ? 2.2 : major ? 1.6 : 1
                )
            }
        }
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

/// Compact cardinals so the dial reads as a clock: 12a / 6a / 12p / 6p,
/// or 00 / 06 / 12 / 18 in 24-hour regions.
enum DialClock {
    static func cardinalLabel(_ hour: Int, locale: Locale = .current) -> String {
        switch locale.hourCycle {
        case .zeroToTwentyThree, .oneToTwentyFour:
            return String(format: "%02d", hour)
        default:
            let h = hour % 12 == 0 ? 12 : hour % 12
            return hour < 12 ? "\(h)a" : "\(h)p"
        }
    }
}

/// Snap, clamp, and angle math shared by the dial drag and the meal-time picker.
enum MealTimeEditing {
    static let snapMinutes = 15
    static let breakfastEarliest = 240
    static let dinnerLatest = 1380
    static let gap = 60

    static func snap(_ minute: Int) -> Int {
        let wrapped = ((minute % 1440) + 1440) % 1440
        let snapped = Int((Double(wrapped) / Double(snapMinutes)).rounded()) * snapMinutes
        return snapped == 1440 ? 0 : snapped
    }

    static func clamp(
        _ minute: Int,
        slot: MealSlot,
        breakfast: Int,
        lunch: Int,
        dinner: Int
    ) -> Int {
        let snapped = snap(minute)
        switch slot {
        case .breakfast:
            return min(max(snapped, breakfastEarliest), lunch - gap)
        case .lunch:
            return min(max(snapped, breakfast + gap), dinner - gap)
        case .dinner:
            return min(max(snapped, lunch + gap), dinnerLatest)
        }
    }

    /// 0 at 12 o'clock, clockwise, in minutes from local midnight.
    static func minute(at location: CGPoint, center: CGPoint) -> Int {
        let dx = location.x - center.x
        let dy = location.y - center.y
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }
        return Int((angle / (2 * .pi) * 1440).rounded())
    }
}

extension MealTimesPayload {
    subscript(slot: MealSlot) -> Int {
        get {
            switch slot {
            case .breakfast: return breakfastMin
            case .lunch: return lunchMin
            case .dinner: return dinnerMin
            }
        }
        set {
            switch slot {
            case .breakfast: breakfastMin = newValue
            case .lunch: lunchMin = newValue
            case .dinner: dinnerMin = newValue
            }
        }
    }
}

#Preview("Schedule") {
    DayDial(breakfastMin: 480, lunchMin: 780, dinnerMin: 1140, quietStartMin: 1380, quietEndMin: 420) {
        Text("Standard").font(Typography.voice(26))
    }
    .padding()
    .background(Palette.background)
}

#Preview("Live") {
    DayDial(
        breakfastMin: 480, lunchMin: 780, dinnerMin: 1140,
        quietStartMin: 1380, quietEndMin: 420,
        today: DialToday(
            states: [.breakfast: .logged, .lunch: .now, .dinner: .upcoming],
            nowMin: 800,
            ringColor: Palette.accent
        )
    ) {
        VStack(spacing: 1) {
            Text("Next check-in").sectionLabelStyle()
            Text("1:45 PM")
                .font(Typography.data(42, weight: .bold))
                .foregroundStyle(Palette.ink)
        }
    }
    .padding()
    .background(Palette.background)
}
