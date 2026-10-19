import SwiftUI

// Design v2's signature pieces: the fuel orb, its ring, the ambient glow behind a
// screen, glass surfaces and the light headline with a dim tail.

// MARK: Fuel orb

/// The glowing sphere at the centre of Today. A lit ember ball that breathes
/// slowly; it dims while the day is in quiet mode.
struct FuelOrb: View {
    var size: CGFloat = 180
    var dimmed = false
    var breathing = true
    var glow: Double = 0.4
    /// Haze is the training orb.
    var haze = false

    var body: some View {
        LoopingPhase(period: 4.5, still: 0) { t in
            let beat = breathing ? (1 - cos(t * 2 * .pi)) / 2 : 0
            orb
                .scaleEffect(1 + 0.045 * beat)
                .brightness(0.06 * beat)
        }
        .frame(width: size, height: size)
        .opacity(dimmed ? 0.35 : 1)
        .saturation(dimmed ? 0.2 : 1)
        .accessibilityHidden(true)
    }

    private var orb: some View {
        Circle()
            .fill(haze ? Self.hazeGradient(size: size) : Self.gradient(size: size))
            .overlay {
                // Shade the lower right so it reads as a sphere, not a disc.
                Circle().fill(
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.5)],
                        center: UnitPoint(x: 0.3, y: 0.25),
                        startRadius: size * 0.35,
                        endRadius: size * 0.62
                    )
                )
            }
            .shadow(color: (haze ? Palette.haze : Palette.ember).opacity(glow), radius: size * 0.22)
    }

    static func hazeGradient(size: CGFloat) -> RadialGradient {
        RadialGradient(
            stops: [
                .init(color: Color(hex: 0xEEF2FF), location: 0),
                .init(color: Color(hex: 0xC7D2FE), location: 0.18),
                .init(color: Color(hex: 0x818CF8), location: 0.46),
                .init(color: Color(hex: 0x312E81), location: 0.78),
                .init(color: Color(hex: 0x0F0E2A), location: 1),
            ],
            center: UnitPoint(x: 0.34, y: 0.28),
            startRadius: 0,
            endRadius: size * 0.78
        )
    }

    static func gradient(size: CGFloat) -> RadialGradient {
        RadialGradient(
            stops: [
                .init(color: Color(hex: 0xFFE9CC), location: 0),
                .init(color: Color(hex: 0xFFB86B), location: 0.18),
                .init(color: Color(hex: 0xF06A2E), location: 0.46),
                .init(color: Color(hex: 0x6E220E), location: 0.76),
                .init(color: Color(hex: 0x1E0A05), location: 1),
            ],
            center: UnitPoint(x: 0.34, y: 0.28),
            startRadius: 0,
            endRadius: size * 0.78
        )
    }
}

/// A small lit ball — the "+" log button, the dot inside a primary button.
struct EmberBall<Label: View>: View {
    var size: CGFloat = 42
    var glow = false
    @ViewBuilder var label: Label

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color(hex: 0xFFE0B8), Palette.ember],
                    center: UnitPoint(x: 0.35, y: 0.3),
                    startRadius: 0,
                    endRadius: size * 0.6
                )
            )
            .frame(width: size, height: size)
            .shadow(color: Palette.ember.opacity(glow ? 0.55 : 0), radius: size * 0.42)
            .overlay { label.foregroundStyle(Palette.onEmber) }
    }
}

extension EmberBall where Label == Image {
    init(size: CGFloat = 42, glow: Bool = false, systemName: String) {
        self.size = size
        self.glow = glow
        self.label = Image(systemName: systemName)
    }
}

/// The progress ring around the orb: a faint track and an amber arc that glows.
/// Past the target, a bone overflow arc runs a second lap — white on amber, not
/// another orange, so “over” reads at a glance.
struct OrbRing: View {
    var progress: Double
    var lineWidth: CGFloat = 4
    var tint: Color = Palette.amber
    /// Drawn on top when `progress` exceeds 1 — defaults to bone for contrast.
    var overflowTint: Color = Palette.ink
    var track: Color = Palette.idleRing

    private var filled: Double { min(1, max(0, progress)) }
    /// Second lap, capped at one full turn past the target.
    private var overflow: Double { max(0, min(1, progress - 1)) }

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: filled)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.55), radius: 8)
            if overflow > 0.002 {
                // Second lap in bone — white on amber, not another orange.
                Circle()
                    .trim(from: 0, to: overflow)
                    .stroke(overflowTint, style: StrokeStyle(lineWidth: lineWidth + 1, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: overflowTint.opacity(0.4), radius: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Orb + ring + the number in the middle, as on Today.
struct FuelOrbDial<Center: View>: View {
    var progress: Double
    var size: CGFloat = 240
    var dimmed = false
    var tint: Color = Palette.amber
    @ViewBuilder var center: Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    private var over: Bool { progress > 1.002 }

    var body: some View {
        ZStack {
            OrbRing(progress: shown, tint: tint)
            FuelOrb(size: size - 60, dimmed: dimmed, glow: over ? 0.55 : 0.4)
            center
                .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 1.1, dampingFraction: 0.9).delay(0.15)) {
                shown = progress
            }
        }
        .onChange(of: progress) { _, value in
            withAnimation(Motion.adaptive(.spring(response: 0.9, dampingFraction: 0.88), reduceMotion: reduceMotion)) {
                shown = value
            }
        }
    }
}

// MARK: Ambient glow

/// The soft coloured light behind a screen. Ember for food screens, haze for
/// training; `strength` scales it down for busy screens.
struct AmbientGlow: View {
    enum Tone { case ember, haze, mixed, quiet }

    var tone: Tone = .mixed
    var strength: Double = 1
    var height: CGFloat = 420

    var body: some View {
        ZStack {
            switch tone {
            case .ember:
                blob(Palette.ember, 0.32, x: 0.5, y: 0.45)
            case .haze:
                blob(Palette.haze, 0.30, x: 0.5, y: 0.45)
                blob(Palette.hazeSoft, 0.10, x: 0.8, y: 0.25)
            case .mixed:
                blob(Palette.ember, 0.30, x: 0.42, y: 0.46)
                blob(Palette.haze, 0.16, x: 0.82, y: 0.7)
            case .quiet:
                blob(Color.white, 0.06, x: 0.5, y: 0.45)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .blur(radius: 30)
        .opacity(strength)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func blob(_ color: Color, _ alpha: Double, x: CGFloat, y: CGFloat) -> some View {
        GeometryReader { geo in
            RadialGradient(
                colors: [color.opacity(alpha), color.opacity(0)],
                center: UnitPoint(x: x, y: y),
                startRadius: 0,
                endRadius: min(geo.size.width, geo.size.height) * 0.55
            )
        }
    }
}

extension View {
    /// Put the ambient glow behind this screen, anchored to the top.
    func ambientGlow(_ tone: AmbientGlow.Tone = .mixed, strength: Double = 1, offsetY: CGFloat = 0) -> some View {
        background(alignment: .top) {
            AmbientGlow(tone: tone, strength: strength)
                .offset(y: offsetY)
                .ignoresSafeArea()
        }
    }
}

// MARK: Glass

extension View {
    /// A glass surface: white at 4.5% with a 9% border.
    func glass(radius: CGFloat = Radius.xl, fill: Color = Palette.glass, stroke: Color = Palette.hairline) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(stroke)
                )
        }
    }

    /// A glass capsule.
    func glassCapsule(fill: Color = Palette.glass, stroke: Color = Palette.hairline) -> some View {
        background {
            Capsule(style: .continuous)
                .fill(fill)
                .overlay(Capsule(style: .continuous).strokeBorder(stroke))
        }
    }
}

/// A padded glass card — Today's "Next up", the morning ask, the top-up.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 18
    var radius: CGFloat = Radius.xl
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(radius: radius)
    }
}

// MARK: Headline

/// A light headline with a dim tail: "How's your appetite today? *I'll shape
/// the plates.*" The tail is what the app adds; the first part is the point.
struct Headline: View {
    let text: String
    var tail: String? = nil
    var size: CGFloat = 30
    var alignment: TextAlignment = .leading

    init(_ text: String, tail: String? = nil, size: CGFloat = 30, alignment: TextAlignment = .leading) {
        self.text = text
        self.tail = tail
        self.size = size
        self.alignment = alignment
    }

    var body: some View {
        (Text(text).foregroundColor(Palette.ink)
            + Text(tail.map { " " + $0 } ?? "").foregroundColor(Palette.inkFaint))
            .font(Typography.display(size))
            .tracking(-0.03 * size)
            .lineSpacing(-size * 0.04)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: Small controls

/// A 40pt glass circle with an icon — back, close.
struct RoundIconButton: View {
    let systemName: String
    var label: String
    var size: CGFloat = 40
    let action: () -> Void

    init(_ systemName: String, label: String, size: CGFloat = 40, action: @escaping () -> Void) {
        self.systemName = systemName
        self.label = label
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10)))
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel(label)
    }
}

/// A short vertical tick — status without a glowing LED.
struct StatusTick: View {
    var color: Color

    var body: some View {
        Capsule(style: .continuous)
            .fill(color)
            .frame(width: 3, height: 12)
            .accessibilityHidden(true)
    }
}

/// Appetite as three rising bars — how full the day feels (low / normal / hungry).
struct AppetiteBars: View {
    /// `LOW`, `NORMAL`, or `HUNGRY`.
    var level: String

    private var lit: Int {
        switch level {
        case "LOW": return 1
        case "HUNGRY": return 3
        default: return 2
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(i < lit ? Palette.amber : Color.white.opacity(0.14))
                    .frame(width: 3, height: CGFloat(6 + i * 3))
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

/// A small glass capsule with a status tick: "On pace · 2 of 4 meals".
struct StatusPill<Trailing: View>: View {
    var dot: Color
    var text: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            StatusTick(color: dot)
            Text(text)
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.ink)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .glassCapsule()
    }
}

extension StatusPill where Trailing == EmptyView {
    init(dot: Color, text: String) {
        self.init(dot: dot, text: text) { EmptyView() }
    }
}

/// The step bars at the top of setup: filled bone up to the current step.
struct StepBars: View {
    let step: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < step ? Palette.ink : Color.white.opacity(0.14))
                    .frame(width: i == step - 1 ? 22 : 14, height: 4)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
        .accessibilityElement()
        .accessibilityLabel("Step \(step) of \(total)")
    }
}
