import SwiftUI

/// After a light meal: one or two calorie-dense add-ons that bring the day
/// back toward pace — the "same bite, more calories" move for someone who
/// can't face a second plate. Each says how it goes with what was just eaten;
/// "Something else" swaps to the next idea. One tap logs it; "Not this time"
/// hides it for the rest of that meal.
struct TopUpCard: View {
    let topUp: HomeResponse.TopUp
    let busy: Bool
    let onAdd: (HomeResponse.TopUp.Option) -> Void
    let onDismiss: () -> Void

    @State private var index = 0

    private var choice: HomeResponse.TopUp.Option {
        let choices = topUp.choices
        return choices[index % choices.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Top it up").sectionLabelStyle(Palette.amber)
                Headline(title, tail: "No second plate.", size: 28)
                Text(L10n("You’re \(topUp.behindKcal.formatted()) kcal behind where \(mealName) should leave you."))
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(choice.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.amber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.quantity > 1 ? "\(item.quantity)× \(FoodText.name(item.name))" : FoodText.name(item.name))
                                .font(Typography.data(15, weight: .regular))
                                .foregroundStyle(Palette.ink)
                            if let how = item.how, !how.isEmpty {
                                Text(how)
                                    .font(Typography.data(13, weight: .regular))
                                    .foregroundStyle(Palette.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(FoodText.serving(item.servingDesc))
                                .font(Typography.data(11, weight: .regular))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        Spacer(minLength: 8)
                        Text("+\(item.kcal)")
                            .font(Typography.mono(12))
                            .foregroundStyle(Palette.amber)
                    }
                }
                if choice.totalProteinG >= 10 {
                    Text("+" + L10n("\(Int(choice.totalProteinG.rounded())) g protein"))
                        .font(Typography.mono(12))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(radius: Radius.lg, fill: Palette.ember.opacity(0.08), stroke: Palette.amber.opacity(0.30))
            .id(index)
            .transition(.opacity)

            VStack(spacing: 4) {
                ActionButton(
                    title: L10n("Add \(choice.totalKcal) kcal"),
                    busy: busy,
                    busyTitle: "Adding…",
                    symbol: "plus",
                    action: { onAdd(choice) }
                )
                HStack(spacing: 0) {
                    if topUp.choices.count > 1 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { index += 1 }
                        } label: {
                            Label("Something else", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    Button("Not this time", action: onDismiss)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
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
        return meal == L10n("Meal") ? L10n("this meal") : meal.lowercased()
    }

    private var title: String {
        let meal = TodayCopy.slotTitle(topUp.slot)
        return meal == L10n("Meal") ? L10n("Add this now.") : L10n("Add this to \(meal.lowercased()).")
    }
}

enum TopUpDismissal {
    /// One key per local day + slot: "Not now" hides it for that meal only.
    static func key(for topUp: HomeResponse.TopUp, now: Date = .now) -> String {
        let day = now.formatted(.iso8601.year().month().day())
        return "\(day):\(topUp.slot)"
    }
}
