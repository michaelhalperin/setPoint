import SwiftUI

/// Plan §6: a distinct, slightly editorial voice for anything the manager "says"
/// (check-ins, prescriptions, notes), visually separated from the cold data
/// (ledger numbers, macros).
///
/// The voice is **Fraunces** (bundled, SIL OFL — see Resources/Fonts/OFL.txt),
/// an optical serif tuned soft and un-wonky. Data stays on SF Rounded. If the
/// bundled face somehow fails to load, `Font.custom` falls back to the system
/// serif on its own.
enum Typography {
    // Bundled family name + PostScript faces.
    private static let voiceFamily = "Fraunces"
    private static let voiceMedium = "Fraunces-Medium"
    private static let voiceItalic = "Fraunces-Italic"

    /// The manager speaking — editorial serif. `weight: .medium`/`.semibold`
    /// swaps to the Medium cut; anything lighter uses Regular.
    private static let heavier: Set<Font.Weight> = [.medium, .semibold, .bold, .heavy, .black]

    static func voice(_ size: CGFloat = 19, weight: Font.Weight = .regular) -> Font {
        let face = heavier.contains(weight) ? voiceMedium : voiceFamily
        return .custom(face, size: size, relativeTo: .body)
    }

    /// The manager, emphatic — serif italic (used sparingly, e.g. a single
    /// stressed phrase).
    static func voiceItalic(_ size: CGFloat = 19) -> Font {
        .custom(voiceItalic, size: size, relativeTo: .body)
    }

    /// Cold data — ledger, macros, counts.
    static func data(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// The hero ledger number — big, confident, rounded (Fraunces figures read
    /// too delicate at display size).
    static let hero = Font.system(size: 58, weight: .semibold, design: .rounded)

    /// A large serif display line — the onboarding "you're set", step headers.
    static func display(_ size: CGFloat = 30) -> Font {
        .custom(voiceFamily, size: size, relativeTo: .largeTitle)
    }

    static let sectionLabel = Font.system(size: 12, weight: .semibold, design: .rounded)
}

extension View {
    /// Uppercase, tracked, faint — a quiet section header.
    func sectionLabelStyle() -> some View {
        self.font(Typography.sectionLabel)
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(Palette.inkFaint)
    }
}
