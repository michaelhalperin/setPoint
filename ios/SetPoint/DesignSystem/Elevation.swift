import SwiftUI

/// Depth (Pass 0). Warm, soft, wide shadows — never a hard drop. The tint is
/// `ink`, not black, so cards feel like they're lifting off a warm paper ground
/// rather than floating in a void.
enum Elevation {
    case flat
    case resting
    case floating
    case lifted

    var shadows: [(color: Color, radius: CGFloat, y: CGFloat)] {
        switch self {
        case .flat:
            return []
        case .resting:
            return [(.init(hex: 0x2B2622, opacity: 0.06), 14, 6)]
        case .floating:
            return [
                (.init(hex: 0x2B2622, opacity: 0.10), 28, 14),
                (.init(hex: 0x2B2622, opacity: 0.05), 6, 2),
            ]
        case .lifted:
            return [
                (.init(hex: 0x2B2622, opacity: 0.16), 44, 26),
                (.init(hex: 0x2B2622, opacity: 0.06), 8, 3),
            ]
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
