import SwiftUI

/// One spacing scale, used everywhere instead of ad-hoc numbers. Roughly a
/// 1.4–1.6 ratio so hero areas breathe and data groups tighten.
enum Space {
    /// 4 — hairline gaps, icon-to-text.
    static let xxs: CGFloat = 4
    /// 8 — within a tight group (label + value).
    static let xs: CGFloat = 8
    /// 12 — between rows in a card.
    static let sm: CGFloat = 12
    /// 20 — default gap between elements.
    static let md: CGFloat = 20
    /// 32 — between distinct sections.
    static let lg: CGFloat = 32
    /// 52 — around a hero, top-of-screen air.
    static let xl: CGFloat = 52

    /// Standard screen side padding.
    static let gutter: CGFloat = 20
}

/// Corner radii — one small set, continuous curvature.
enum Radius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 26
    static let pill: CGFloat = 999
}
