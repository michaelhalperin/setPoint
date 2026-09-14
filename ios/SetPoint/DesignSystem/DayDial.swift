import SwiftUI

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

            ZStack {
                Circle()
                    .stroke(trackColor, lineWidth: ringWidth)
                    .frame(width: r * 2, height: r * 2)
                    .position(c)

                quietArc(radius: r, width: ringWidth)
                    .position(c)

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
                    knob(slot)
                        .scaleEffect(markersShown ? 1 : 0.2)
                        .opacity(markersShown ? 1 : 0)
                        .animation(markerAnimation(index), value: markersShown)
                        .position(point(minute, radius: r, center: c))
                    PingBell(fill: theme == .terra ? Palette.background : Palette.accentTint, stagger: Double(index) * 0.8)
                        .scaleEffect(markersShown ? 1 : 0.2)
                        .opacity(markersShown ? 1 : 0)
                        .animation(markerAnimation(index).delay(0.15), value: markersShown)
                        .position(point(CheckInSchedule.minute(afterMeal: minute), radius: r + size * 0.118, center: c))
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

    private func knob(_ slot: MealSlot) -> some View {
        Image(systemName: slot.symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Palette.accent)
            .frame(width: 44, height: 44)
            .background(theme == .terra ? Palette.background : Palette.surface, in: Circle())
            .overlay {
                if theme == .paper { Circle().strokeBorder(Palette.accent, lineWidth: 3) }
            }
            .elevation(.resting)
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

/// A bell that sends out a soft ring every couple of seconds.
private struct PingBell: View {
    let fill: Color
    let stagger: Double

    var body: some View {
        ZStack {
            LoopingPhase(period: 2.4, offset: stagger, still: 1) { t in
                Circle()
                    .fill(fill)
                    .scaleEffect(0.7 + 1.4 * Phase.ramp(t, 0, 0.7))
                    .opacity(0.8 * (1 - Phase.ramp(t, 0, 0.7)))
            }
            Circle().fill(fill)
            Image(systemName: "bell.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accent)
        }
        .frame(width: 28, height: 28)
    }
}

#Preview {
    DayDial(breakfastMin: 480, lunchMin: 780, dinnerMin: 1140, quietStartMin: 1380, quietEndMin: 420) {
        Text("Standard").font(Typography.voice(26))
    }
    .padding()
    .background(Palette.background)
}
