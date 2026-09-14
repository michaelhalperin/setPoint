import SwiftUI
import UIKit

/// Plan §6: warm, grounded, quietly confident. One accent — terracotta — reserved
/// for the manager's voice and under-eating urgency. Dark mode keeps the same
/// hierarchy on a deep paper ground.
enum Palette {
    static let background = Color(uiColor: .setPointPaper)
    static let surface = Color(uiColor: .setPointSurface)
    static let surfaceRaised = Color(uiColor: .setPointSurfaceRaised)
    static let surfaceSunk = Color(uiColor: .setPointSurfaceSunk)

    static let scrim = Color(uiColor: .setPointScrim)
    static let hairline = Color(uiColor: .setPointHairline)

    static let ink = Color(uiColor: .setPointInk)
    static let inkSoft = Color(uiColor: .setPointInkSoft)
    static let inkFaint = Color(uiColor: .setPointInkFaint)

    static let accentTint = Color(uiColor: .setPointAccentTint)
    static let accentSoft = Color(uiColor: .setPointAccentSoft)
    static let accent = Color(hex: 0xD5613A)
    static let accentDeep = Color(uiColor: .setPointAccentDeep)

    static let dayOnTrack = Color(hex: 0x6E8A67)
    static let dayUnder = accent
    static let dayOver = Color(uiColor: .setPointDayOver)
    static let dayMissed = Color(uiColor: .setPointDayMissed)

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

private extension UIColor {
    static func adaptive(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> UIColor {
        UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            let alpha = trait.userInterfaceStyle == .dark ? darkAlpha : lightAlpha
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha
            )
        }
    }

    static let setPointPaper = adaptive(light: 0xFBF6F0, dark: 0x1C1814)
    static let setPointSurface = adaptive(light: 0xFFFFFF, dark: 0x2A241F)
    static let setPointSurfaceRaised = adaptive(light: 0xFFFDFB, dark: 0x322B25)
    static let setPointSurfaceSunk = adaptive(light: 0xF2EADF, dark: 0x241F1B)
    static let setPointScrim = adaptive(light: 0x2B2622, dark: 0x000000, lightAlpha: 0.28, darkAlpha: 0.45)
    static let setPointHairline = adaptive(light: 0x2B2622, dark: 0xFBF6F0, lightAlpha: 0.06, darkAlpha: 0.12)
    static let setPointInk = adaptive(light: 0x2B2622, dark: 0xF4EDE4)
    static let setPointInkSoft = adaptive(light: 0x6C6259, dark: 0xB8AFA4)
    static let setPointInkFaint = adaptive(light: 0xAAA093, dark: 0x8A8176)
    static let setPointAccentTint = adaptive(light: 0xFBEDE4, dark: 0x3A2A22)
    static let setPointAccentSoft = adaptive(light: 0xF4DACE, dark: 0x4A3228)
    static let setPointAccentDeep = adaptive(light: 0x9E4023, dark: 0xE08A6A)
    static let setPointDayOver = adaptive(light: 0xC3B8A8, dark: 0x6E655A)
    static let setPointDayMissed = adaptive(light: 0xD8CFC2, dark: 0x4A433C)
}
