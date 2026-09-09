import SwiftUI

/// The hero stat (§5.2): the running gap, framed by goal. Never hard-cuts — the
/// number counts to its new value (§5a, `.contentTransition(.numericText)`).
struct LedgerHero: View {
    let ledger: HomeResponse.Ledger
    let framing: HomeResponse.Framing

    private var underEating: Bool { framing.state == "under" }

    private var caption: String {
        switch framing.state {
        case "under": return "to eat today"
        case "over": return "over today"
        default: return "on target today"
        }
    }

    var body: some View {
        Card(tint: underEating ? Palette.accentSoft.opacity(0.55) : Palette.surface) {
            VStack(alignment: .leading, spacing: 6) {
                Text(caption)
                    .sectionLabelStyle()

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(abs(framing.heroKcal))")
                        .font(Typography.hero)
                        .foregroundStyle(underEating ? Palette.accent : Palette.ink)
                        .contentTransition(.numericText(value: Double(framing.heroKcal)))
                    Text("kcal")
                        .font(Typography.data(18, weight: .medium))
                        .foregroundStyle(Palette.inkFaint)
                }

                Text("\(ledger.consumedKcal) of \(ledger.targetKcal) eaten · \(ledger.mealsToday) meal\(ledger.mealsToday == 1 ? "" : "s")")
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
    }
}

struct ProteinRow: View {
    let ledger: HomeResponse.Ledger

    var body: some View {
        if let target = ledger.targetProteinG {
            let consumed = Int(ledger.consumedProteinG.rounded())
            let goal = Int(target.rounded())
            Card {
                HStack {
                    Text("Protein")
                        .font(Typography.data(14, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                    Spacer()
                    Text("\(consumed) / \(goal) g")
                        .font(Typography.data(15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: Double(consumed)))
                }
            }
        }
    }
}

/// The check-in's content, shared between the Home card and the full-screen
/// prescription view — the same view at two sizes so `matchedGeometryEffect`
/// can morph one into the other (§5a).
struct CheckInContent: View {
    let checkIn: HomeResponse.ActiveCheckIn
    var expanded = false

    private var tierThreePrompt: String? {
        checkIn.tier >= 3 ? "The last few days haven't gone to plan. Let's sort out what needs to change." : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 14 : 10) {
            Text(checkIn.tier >= 3 ? "Let's talk" : (checkIn.tier >= 2 ? "Check-in · firm" : "Check-in"))
                .sectionLabelStyle()
                .foregroundStyle(Palette.accent)

            if let message = checkIn.message ?? tierThreePrompt {
                Text(message)
                    .font(Typography.voice(expanded ? 21 : 17))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let rx = checkIn.prescription {
                Divider().overlay(Palette.ink.opacity(0.06))
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
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: expanded ? 26 : 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: expanded ? 26 : 20, style: .continuous)
                .strokeBorder(Palette.ink.opacity(0.05))
        )
    }
}
