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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Top it up").sectionLabelStyle(Palette.amber)
                Headline(title, tail: "No second plate.", size: 28)
                Text("You’re \(topUp.behindKcal.formatted()) kcal behind where \(mealName) should leave you.")
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FlexWrap(spacing: 8, lineSpacing: 8) {
                ForEach(Array(topUp.items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.amber)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.quantity > 1 ? "\(item.quantity)× \(item.name)" : item.name)
                                .font(Typography.data(14, weight: .regular))
                                .foregroundStyle(Palette.ink)
                            Text(item.servingDesc)
                                .font(Typography.data(11, weight: .regular))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        Text("+\(item.kcal)")
                            .font(Typography.mono(12))
                            .foregroundStyle(Palette.amber)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassCapsule(fill: Palette.ember.opacity(0.10), stroke: Palette.amber.opacity(0.35))
                }
            }

            VStack(spacing: 4) {
                ActionButton(
                    title: "Add \(topUp.totalKcal) kcal",
                    busy: busy,
                    busyTitle: "Adding…",
                    symbol: "plus",
                    action: onAdd
                )
                Button("Not this time", action: onDismiss)
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(busy)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: Radius.xl)
        .background(alignment: .top) {
            AmbientGlow(tone: .ember, strength: 0.5, height: 260).offset(y: -40)
        }
        .accessibilityElement(children: .contain)
    }

    private var mealName: String {
        let meal = TodayCopy.slotTitle(topUp.slot)
        return meal == "Meal" ? "this meal" : meal.lowercased()
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
