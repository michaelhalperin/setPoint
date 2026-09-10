import SwiftUI

/// The check-in's content, shared between the Home card and the full-screen
/// prescription view — the same view at two sizes so `matchedGeometryEffect`
/// can morph one into the other (§5a).
struct CheckInContent: View {
    let checkIn: HomeResponse.ActiveCheckIn
    var expanded = false
    /// Home card uses `.floating` so it reads as the thing to tap; the morphed
    /// full-screen version always lifts hardest.
    var restingElevation: Elevation = .resting

    private var tierThreePrompt: String? {
        checkIn.tier >= 3 ? "Rough few days. Let’s adjust." : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 14 : 10) {
            Text(checkIn.tier >= 3 ? "Let's talk" : "Check-in")
                .sectionLabelStyle()
                .foregroundStyle(Palette.accent)

            if let message = checkIn.message ?? tierThreePrompt {
                Text(message)
                    .font(Typography.voice(expanded ? 22 : 17))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(expanded ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let rx = checkIn.prescription {
                Divider().overlay(Palette.hairline)
                ForEach(rx.items) { item in
                    HStack {
                        Text(item.quantity > 1 ? "\(Int(item.quantity))× \(item.name)" : item.name)
                            .font(Typography.data(expanded ? 15 : 14))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\(item.kcal) kcal")
                            .font(Typography.data(13))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
                Text("\(rx.totalKcal) kcal · \(Int(rx.totalProteinG.rounded())) g protein")
                    .font(Typography.data(12, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .padding(expanded ? 22 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: expanded ? Radius.xl : Radius.lg, style: .continuous)
                .fill(Palette.surface)
                .elevation(expanded ? .lifted : restingElevation)
                .overlay(
                    RoundedRectangle(cornerRadius: expanded ? Radius.xl : Radius.lg, style: .continuous)
                        .strokeBorder(Palette.hairline)
                )
        }
    }
}
