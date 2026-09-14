import SwiftUI

/// A tiny trend line per goal: rising, falling, level.
struct GoalSparkline: Shape {
    let goal: Goal

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 76, sy = rect.height / 52
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        switch goal {
        case .bulk:
            path.move(to: p(4, 46))
            path.addCurve(to: p(72, 6), control1: p(26, 44), control2: p(44, 22))
        case .diet:
            path.move(to: p(4, 6))
            path.addCurve(to: p(72, 46), control1: p(26, 8), control2: p(44, 30))
        case .maintain:
            path.move(to: p(4, 28))
            path.addCurve(to: p(40, 26), control1: p(16, 18), control2: p(28, 38))
            path.addCurve(to: p(72, 27), control1: p(52, 14), control2: p(62, 22))
        }
        return path
    }
}

/// The road from now to the target: a line that draws itself, a dot travelling it.
struct TargetCurve: View {
    let falling: Bool
    let startLabel: String

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let y: (CGFloat) -> CGFloat = { falling ? (1 - $0) * h : $0 * h }
            let start = CGPoint(x: 0.1 * w, y: y(0.8))
            let c1 = CGPoint(x: 0.43 * w, y: y(0.8))
            let c2 = CGPoint(x: 0.63 * w, y: y(0.32))
            let end = CGPoint(x: 0.91 * w, y: y(0.21))
            let curve = Path { p in
                p.move(to: start)
                p.addCurve(to: end, control1: c1, control2: c2)
            }

            ZStack {
                curve.stroke(Palette.surfaceSunk, style: StrokeStyle(lineWidth: 6, lineCap: .round))

                LoopingPhase(period: 5, still: 1) { t in
                    let u = Phase.ramp(t, 0.02, 0.5)
                    ZStack {
                        curve
                            .trim(from: 0, to: u)
                            .stroke(Palette.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        Circle()
                            .fill(Palette.accent)
                            .overlay(Circle().strokeBorder(Palette.background, lineWidth: 3))
                            .frame(width: 18, height: 18)
                            .position(bezier(u, start, c1, c2, end))
                            .opacity(u > 0.01 && u < 0.99 ? 1 : 0)
                    }
                }

                Circle()
                    .fill(Palette.ink)
                    .overlay(Circle().strokeBorder(Palette.background, lineWidth: 3))
                    .frame(width: 16, height: 16)
                    .position(start)
                Text(startLabel)
                    .font(Typography.data(13, weight: .bold))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize()
                    .position(x: start.x + 26, y: start.y + (falling ? -24 : 26))

                LoopingPhase(period: 2.2, still: 1) { t in
                    Circle()
                        .fill(Palette.accentSoft)
                        .frame(width: 26, height: 26)
                        .scaleEffect(0.7 + 1.4 * Phase.ramp(t, 0, 0.7))
                        .opacity(0.8 * (1 - Phase.ramp(t, 0, 0.7)))
                }
                .position(end)
                Circle().fill(Palette.accent).frame(width: 18, height: 18).position(end)
            }
        }
        .accessibilityHidden(true)
    }

    private func bezier(_ t: CGFloat, _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt, b = 3 * mt * mt * t, c = 3 * mt * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
                       y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
    }
}
