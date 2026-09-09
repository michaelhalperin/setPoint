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

/// The active check-in, surfaced on Home. Tapping it will morph into the full
/// prescription view (§5a shared-element transition) once that screen exists;
/// for now it opens as a detented sheet.
struct CheckInCard: View {
    let checkIn: HomeResponse.ActiveCheckIn
    @State private var expanded = false

    var body: some View {
        Button { expanded = true } label: {
            Card(tint: Palette.surface) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(checkIn.tier >= 2 ? "Check-in · firm" : "Check-in")
                        .sectionLabelStyle()
                        .foregroundStyle(Palette.accent)

                    if let message = checkIn.message {
                        Text(message)
                            .font(Typography.voice(17))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let rx = checkIn.prescription {
                        Divider().overlay(Palette.ink.opacity(0.06))
                        ForEach(rx.items) { item in
                            HStack {
                                Text(item.quantity > 1 ? "\(Int(item.quantity))× \(item.name)" : item.name)
                                    .font(Typography.data(14))
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
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $expanded) {
            PrescriptionDetail(checkIn: checkIn)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct PrescriptionDetail: View {
    let checkIn: HomeResponse.ActiveCheckIn

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(checkIn.message ?? "Time to eat.")
                .font(Typography.voice(22))
                .foregroundStyle(Palette.ink)

            if let rx = checkIn.prescription {
                ForEach(rx.items) { item in
                    HStack {
                        Text(item.quantity > 1 ? "\(Int(item.quantity))× \(item.name)" : item.name)
                        Spacer()
                        Text("\(item.kcal) kcal")
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .font(Typography.data(16))
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.background)
    }
}
