import SwiftUI

/// Plan §6: a distinct, slightly editorial voice for anything the manager "says"
/// (check-ins, prescriptions, notes), visually separated from the cold data
/// (ledger numbers, macros).
enum Typography {
    /// The manager speaking — serif, editorial.
    static func voice(_ size: CGFloat = 19, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Cold data — ledger, macros, counts.
    static func data(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let hero = Font.system(size: 58, weight: .semibold, design: .rounded)
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
