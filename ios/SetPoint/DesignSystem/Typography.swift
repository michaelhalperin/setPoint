import SwiftUI
import UIKit

/// Design v2: one sans family and one mono. Headlines are *light* and tight, with
/// a dim tail (see `Headline`). Numbers, times and labels are mono. Everything
/// scales with Dynamic Type.
enum Typography {
    /// The manager speaking — plain sans. Big lines go light, like a headline.
    static func voice(_ size: CGFloat = 19, weight: Font.Weight = .regular) -> Font {
        let w: Font.Weight = (weight == .regular && size >= 22) ? .light : weight
        return scaled(size, weight: w, design: .default, style: .body)
    }

    /// Emphasis inside a manager line — the same face, a step lighter.
    static func voiceItalic(_ size: CGFloat = 19) -> Font {
        scaled(size, weight: .light, design: .default, style: .body)
    }

    /// Interface text — buttons, rows, body. Design v2 never goes heavier than
    /// medium, and big numbers (24pt and up) are always light.
    static func data(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        scaled(size, weight: capped(weight, size: size), design: .default, style: .body)
    }

    private static func capped(_ weight: Font.Weight, size: CGFloat) -> Font.Weight {
        if size >= 24 { return .light }
        switch weight {
        case .semibold, .bold, .heavy, .black: return .medium
        default: return weight
        }
    }

    /// Numbers, times, units and labels.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        scaled(size, weight: weight, design: .monospaced, style: .body)
    }

    /// The orb's number.
    static let hero = Font.system(size: 46, weight: .light)

    /// A large light display line — screen titles, onboarding steps.
    static func display(_ size: CGFloat = 30) -> Font {
        scaled(size, weight: .light, design: .default, style: .largeTitle)
    }

    static let sectionLabel = Font.system(size: 11, weight: .regular, design: .monospaced)

    private static func scaled(_ size: CGFloat, weight: Font.Weight, design: UIFontDescriptor.SystemDesign, style: UIFont.TextStyle) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: uiWeight(weight))
        let font = base.fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: size) } ?? base
        return Font(UIFontMetrics(forTextStyle: style).scaledFont(for: font))
    }

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}

extension View {
    /// Mono, uppercase, tracked, faint — a label above a section.
    /// Hebrew drops the mono face, tracking and forced caps; those only work in Latin.
    func sectionLabelStyle(_ color: Color = Palette.inkFaint) -> some View {
        modifier(SectionLabelStyle(color: color))
    }

    /// Tight tracking for a light display line (-3.5% of the size).
    func displayTracking(_ size: CGFloat) -> some View {
        modifier(DisplayTracking(size: size))
    }
}

private struct SectionLabelStyle: ViewModifier {
    let color: Color
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        let hebrew = locale.language.languageCode?.identifier == "he"
        content
            .font(hebrew ? Typography.data(11, weight: .regular) : Typography.sectionLabel)
            .tracking(hebrew ? 0 : 1.3)
            .textCase(hebrew ? nil : .uppercase)
            .foregroundStyle(color)
    }
}

private struct DisplayTracking: ViewModifier {
    let size: CGFloat
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content.tracking(locale.language.languageCode?.identifier == "he" ? 0 : -0.035 * size)
    }
}
