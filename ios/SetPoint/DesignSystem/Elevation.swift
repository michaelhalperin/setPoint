import SwiftUI

/// Depth on the dark ground. Glass surfaces don't cast shadows — they're
/// separated by their 9% border — so only floating things (sheets, the nav, a
/// lifted card) get a soft black shadow.
enum Elevation {
    case flat
    case resting
    case floating
    case lifted

    var shadows: [(color: Color, radius: CGFloat, y: CGFloat)] {
        switch self {
        case .flat, .resting:
            return []
        case .floating:
            return [(.black.opacity(0.45), 28, 14)]
        case .lifted:
            return [(.black.opacity(0.6), 44, 24)]
        }
    }
}

private struct ElevationModifier: ViewModifier {
    let level: Elevation

    func body(content: Content) -> some View {
        level.shadows.reduce(AnyView(content)) { view, s in
            AnyView(view.shadow(color: s.color, radius: s.radius, x: 0, y: s.y))
        }
    }
}

extension View {
    /// Apply a stacked soft shadow. Put it on the *shape/background*, not on a
    /// container of text, so the shadow tracks the card and not the glyphs.
    func elevation(_ level: Elevation) -> some View {
        modifier(ElevationModifier(level: level))
    }
}
