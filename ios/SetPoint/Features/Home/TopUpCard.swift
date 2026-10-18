import SwiftUI

/// After a light meal: one or two calorie-dense add-ons that bring the day
/// back toward pace — the "same bite, more calories" move for someone who
/// can't face a second plate. One tap logs it; "Not now" hides it for the
/// rest of that meal.
struct TopUpCard: View {
    let topUp: HomeResponse.TopUp
    let busy: Bool
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Top it up").sectionLabelStyle()
                Text(title)
                    .font(Typography.display(24))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("You’re \(topUp.behindKcal.formatted()) kcal behind. Same meal, more calories.")
                    .font(Typography.data(14))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(Array(topUp.items.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Rectangle().fill(Palette.hairline).frame(height: 1)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.quantity > 1 ? "\(item.quantity)× \(item.name)" : item.name)
                                .font(Typography.data(15, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                            Text(item.servingDesc)
                                .font(Typography.data(12))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        Spacer(minLength: Space.sm)
                        Text("\(item.kcal) kcal")
                            .font(Typography.data(14))
                            .monospacedDigit()
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .padding(.vertical, 10)
                }
            }

            HStack(spacing: Space.sm) {
                ActionButton(
                    title: "Add \(topUp.totalKcal) kcal",
                    busy: busy,
                    busyTitle: "Adding…",
                    action: onAdd
                )
                Button("Not now", action: onDismiss)
                    .font(Typography.data(15, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.horizontal, Space.sm)
                    .disabled(busy)
            }
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.hairline)
        )
        .elevation(.resting)
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        let meal = TodayCopy.slotTitle(topUp.slot)
        return meal == "Meal" ? "Add this now." : "Add this to \(meal.lowercased())."
    }
}

enum TopUpDismissal {
    /// One key per local day + slot: "Not now" hides it for that meal only.
    static func key(for topUp: HomeResponse.TopUp, now: Date = .now) -> String {
        let day = now.formatted(.iso8601.year().month().day())
        return "\(day):\(topUp.slot)"
    }
}
