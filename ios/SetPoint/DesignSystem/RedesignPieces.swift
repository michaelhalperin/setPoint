import SwiftUI

// Small shared pieces for the second pass of design v2: the inner screens drawn
// as one picture each (a clock, a plate, a bridge, a week) rather than lists.

/// Back button on the left, a mono label in the middle, an optional trailing item.
struct ScreenHeader<Trailing: View>: View {
    var label: String
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if !label.isEmpty {
                Text(LocalizedStringKey(label)).sectionLabelStyle()
                    .lineLimit(1)
                    .padding(.horizontal, 56)
            }
            HStack {
                RoundIconButton("chevron.backward", label: "Back") { (onBack ?? { dismiss() })() }
                Spacer(minLength: 0)
                trailing
            }
        }
        .frame(minHeight: 40)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(label: String, onBack: (() -> Void)? = nil) {
        self.init(label: label, onBack: onBack) { EmptyView() }
    }
}

/// The scroll + glow + ground every redesigned inner screen sits on.
struct InnerScreen<Content: View>: View {
    var glow: AmbientGlow.Tone = .ember
    var glowOffset: CGFloat = -120
    var spacing: CGFloat = 16
    var scrolls = true
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if scrolls {
                ScrollView {
                    stack
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                stack
            }
        }
        .background(alignment: .top) {
            AmbientGlow(tone: glow, strength: 0.7)
                .offset(y: glowOffset)
                .ignoresSafeArea()
        }
        .background(Palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xl)
            .frame(maxWidth: .infinity, maxHeight: scrolls ? nil : .infinity, alignment: .topLeading)
    }
}

/// Diagonal stripes — a busy stretch on a calendar.
struct Hatch: View {
    var opacity: Double = 0.13
    var spacing: CGFloat = 7

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            ctx.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: 2.5)
        }
        .background(Color.white.opacity(0.03))
        .accessibilityHidden(true)
    }
}

/// A busy block: stripes, a hairline and the calendar's colour along the top.
struct BusyBlock: View {
    var color: Color = Palette.haze
    var counts = true
    var radius: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if counts {
                Hatch()
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Color.white.opacity(0.12)))
                    .overlay(alignment: .top) {
                        Rectangle().fill(color).frame(height: 2)
                            .clipShape(shape)
                    }
            } else {
                shape.strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A small lit ball used as a marker — a moved meal, a reminder.
struct EmberDot: View {
    var size: CGFloat = 14
    var haze = false
    var glow: Double = 0.8

    var body: some View {
        Circle()
            .fill(RadialGradient(
                colors: haze ? [Color(hex: 0xEEF2FF), Palette.haze] : [Color(hex: 0xFFE0B8), Palette.ember],
                center: UnitPoint(x: 0.35, y: 0.3),
                startRadius: 0,
                endRadius: size * 0.6
            ))
            .frame(width: size, height: size)
            .shadow(color: (haze ? Palette.haze : Palette.ember).opacity(glow), radius: size * 0.6)
            .accessibilityHidden(true)
    }
}

/// A dashed ring where something used to be — a meal's usual time.
struct GhostRing: View {
    var size: CGFloat = 10
    var color: Color = Palette.amber

    var body: some View {
        Circle()
            .strokeBorder(color.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
            .background(Circle().fill(Palette.background))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Dots travelling along a line — data flowing in or out of Apple Health.
struct FlowingDots: View {
    var color: Color
    var length: CGFloat
    var downward = true
    var count = 3
    var period: Double = 2.7

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .top) {
                ForEach(0..<count, id: \.self) { i in
                    let phase = ((t / period) + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
                    let p = downward ? phase : 1 - phase
                    let fade = min(1, min(phase, 1 - phase) * 8)
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .shadow(color: color, radius: 5)
                        .opacity(reduceMotion ? 0.8 : fade)
                        .offset(y: p * (length - 7))
                }
            }
            .frame(width: 7, height: length, alignment: .top)
        }
        .accessibilityHidden(true)
    }
}

/// A chip that is on (ember tint) or off (glass), for multi-select rows.
struct ToggleChip: View {
    let title: String
    let on: Bool
    var haze = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background {
                    Capsule().fill(on ? (haze ? Palette.haze.opacity(0.16) : Palette.ember.opacity(0.13)) : Color.white.opacity(0.05))
                }
                .overlay {
                    Capsule().strokeBorder(on ? (haze ? Palette.hazeSoft.opacity(0.6) : Color(hex: 0xFF8A50, opacity: 0.6)) : Color.white.opacity(0.10))
                }
        }
        .buttonStyle(PressableCard())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A selectable tile with an ember edge when chosen — goals, paces, plates.
struct ChoiceTile<Content: View>: View {
    let selected: Bool
    var radius: CGFloat = 20
    var padding: CGFloat = 14
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) {
            content
                .padding(padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(selected
                              ? AnyShapeStyle(LinearGradient(colors: [Palette.ember.opacity(0.14), Palette.ember.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.white.opacity(0.03)))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(selected ? Color(hex: 0xFF8A50, opacity: 0.6) : Color.white.opacity(0.08))
                }
                .shadow(color: Palette.ember.opacity(selected ? 0.14 : 0), radius: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCard())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A gradient-edged callout card — ember for food, haze for patterns and training.
struct CalloutCard<Content: View>: View {
    var haze = false
    var padding: CGFloat = 18
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        let tint = haze ? Palette.haze : Palette.ember
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.13), tint.opacity(0.03)], startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(haze ? Palette.hazeSoft.opacity(0.35) : Color(hex: 0xFF8A50, opacity: 0.40))
            }
    }
}

/// A light-on-dark pill button: "Move dinner to 20:00", "Keep lunch".
struct BonePill: View {
    let title: String
    var done = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(Typography.data(13, weight: .medium))
                .foregroundStyle(done ? Palette.positive : Palette.onBone)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(done ? Palette.positive.opacity(0.12) : Palette.ink, in: Capsule())
                .overlay(Capsule().strokeBorder(done ? Palette.positive.opacity(0.4) : .clear))
        }
        .buttonStyle(PressableCard())
    }
}

/// 24-hour clock text for minutes since midnight — "13:00".
func clock24(_ minutes: Int) -> String {
    let m = ((minutes % 1440) + 1440) % 1440
    return String(format: "%02d:%02d", m / 60, m % 60)
}
