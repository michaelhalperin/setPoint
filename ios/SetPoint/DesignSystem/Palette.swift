import SwiftUI

/// Design v2: cinematic dark. A near-black ground, glass surfaces, bone text and
/// bone primary buttons. Two lights carry meaning: **ember** (orange) is food,
/// **haze** (indigo) is training. Nothing else gets a colour.
///
/// The app runs dark only (`UIUserInterfaceStyle = Dark`), so every token is a
/// single value. The older names (`ink`, `surface`, `accent`…) are kept and
/// mapped onto the new palette so every screen picks it up.
enum Palette {
    // MARK: Ground and surfaces

    /// The ground — #09090B.
    static let background = Color(hex: 0x09090B)
    /// An opaque glass tone, for surfaces that must hide what's under them.
    static let surface = Color(hex: 0x131316)
    /// Sheets and raised panels — #141417 with a touch more lift.
    static let surfaceRaised = Color(hex: 0x18181B)
    /// Recessed fills: secondary buttons, chips, tracks, skeletons.
    static let surfaceSunk = Color(hex: 0x1A1A1D)
    /// The bottom sheet ground.
    static let sheet = Color(hex: 0x141417)

    /// Translucent glass — white at 4.5% over whatever is behind.
    static let glass = Color.white.opacity(0.045)
    /// Glass, one step brighter (pressed / selected).
    static let glassHi = Color.white.opacity(0.08)
    /// The 9% white border every glass surface carries.
    static let hairline = Color.white.opacity(0.09)
    /// A stronger border for selected controls.
    static let hairlineHi = Color.white.opacity(0.16)

    static let scrim = Color(hex: 0x09090B, opacity: 0.6)

    // MARK: Text

    /// Bone — text and primary buttons.
    static let ink = Color(hex: 0xF5F5F4)
    /// Secondary text.
    static let inkSoft = Color(hex: 0xA1A1AA)
    /// Labels, the dim tail of a headline, meta.
    static let inkFaint = Color(hex: 0x8B8B94)
    /// Text on a bone button.
    static let onBone = Color(hex: 0x09090B)

    // MARK: Ember — food

    static let ember = Color(hex: 0xFF7A3D)
    static let amber = Color(hex: 0xFFB86B)
    static let emberDeep = Color(hex: 0xF06A2E)
    /// Text on an ember surface.
    static let onEmber = Color(hex: 0x1A0A04)

    static let accent = ember
    /// Accent used as *text* on the dark ground: amber reads better than ember.
    static let accentDeep = amber
    static let accentTint = Color(hex: 0x271711)
    static let accentSoft = Color(hex: 0x3A2015)

    // MARK: Haze — training

    static let haze = Color(hex: 0x818CF8)
    static let hazeSoft = Color(hex: 0xC7D2FE)
    static let hazeTint = Color(hex: 0x15152A)

    // MARK: Status

    static let positive = Color(hex: 0x86EFAC)
    static let danger = Color(hex: 0xF87171)

    // Accents drawn on a bone card.
    static let onInkHeart = Color(hex: 0xD2501A)
    static let onInkPositive = Color(hex: 0x2F7A45)
    /// The second voice on an ember card.
    static let onAccentVoice = Color(hex: 0x1A0A04, opacity: 0.68)

    // Quiet decorative strokes and fills.
    static let idleRing = Color.white.opacity(0.08)
    static let quietArc = Color.white.opacity(0.18)
    static let stackedCardNear = Color(hex: 0x18181B)
    static let stackedCardFar = Color(hex: 0x111113)

    /// Illustrations of the system lock screen.
    static let lockScreenInk = Color(hex: 0x141417)
    static let lockScreenText = Color(hex: 0xF5F5F4)

    static let dayOnTrack = positive
    static let dayUnder = ember
    static let dayOver = amber
    static let dayMissed = Color.white.opacity(0.14)

    static func day(_ kind: String) -> Color {
        switch kind {
        case "ON_TRACK": return dayOnTrack
        case "UNDER": return dayUnder
        case "OVER": return dayOver
        default: return dayMissed
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
