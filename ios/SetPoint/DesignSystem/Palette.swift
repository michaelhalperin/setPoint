import SwiftUI

/// Plan §6: warm, grounded, quietly confident. One accent — terracotta — reserved
/// for the manager's voice and under-eating urgency, so colour itself signals
/// "the app is talking to you". No dark-glass fitness tropes, no alarm red.
enum Palette {
    // Grounds
    static let background = Color(hex: 0xFBF6F0)
    static let surface = Color(hex: 0xFFFFFF)
    static let surfaceSunk = Color(hex: 0xF2EADF)

    // Ink
    static let ink = Color(hex: 0x2B2622)
    static let inkSoft = Color(hex: 0x6C6259)
    static let inkFaint = Color(hex: 0xAAA093)

    // The one accent
    static let accent = Color(hex: 0xD5613A)
    static let accentSoft = Color(hex: 0xF4DACE)

    // Settlement day colours — restrained, no gamified greens/reds
    static let dayOnTrack = Color(hex: 0x6E8A67)
    static let dayUnder = accent
    static let dayOver = Color(hex: 0xC3B8A8)   // going over is quiet, never urgent (§5.2)
    static let dayMissed = Color(hex: 0xD8CFC2)

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
