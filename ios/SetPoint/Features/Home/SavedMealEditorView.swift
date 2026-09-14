import SwiftUI

/// A named plate being created or edited. Siri is a placeholder until Phase 7.
struct SavedMealDraft: Identifiable, Equatable {
    var id: String
    var existingId: String?
    var name: String
    var items: [Item]
    var suggestSlot: String?
    var useInCheckIns: Bool

    struct Item: Identifiable, Equatable {
        let id: UUID
        var name: String
        var quantity: String
        var kcal: String
        var proteinG: String
        var carbsG: String
        var fatG: String

        init(
            id: UUID = UUID(),
            name: String = "",
            quantity: String = "",
            kcal: String = "",
            proteinG: String = "",
            carbsG: String = "",
            fatG: String = ""
        ) {
            self.id = id
            self.name = name
            self.quantity = quantity
            self.kcal = kcal
            self.proteinG = proteinG
            self.carbsG = carbsG
            self.fatG = fatG
        }

        init(_ item: MealSummary.Item) {
            self.init(
                name: item.name,
                quantity: item.quantity,
                kcal: String(item.kcal),
                proteinG: Self.number(item.proteinG),
                carbsG: Self.number(item.carbsG),
                fatG: Self.number(item.fatG)
            )
        }

        var encoded: MealCorrectionRequest.Item? {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let kcal = Int(kcal), kcal >= 0,
                  let protein = Double(proteinG.replacingOccurrences(of: ",", with: ".")), protein >= 0,
                  let carbs = Double(carbsG.replacingOccurrences(of: ",", with: ".")), carbs >= 0,
                  let fat = Double(fatG.replacingOccurrences(of: ",", with: ".")), fat >= 0
            else { return nil }
            return .init(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                quantity: quantity.trimmingCharacters(in: .whitespacesAndNewlines),
                kcal: kcal,
                proteinG: protein,
                carbsG: carbs,
                fatG: fat
            )
        }

        private static func number(_ value: Double) -> String {
            value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        }
    }

    var totals: (kcal: Int, proteinG: Double, carbsG: Double, fatG: Double) {
        let encoded = items.compactMap(\.encoded)
        return (
            encoded.reduce(0) { $0 + $1.kcal },
            encoded.reduce(0) { $0 + $1.proteinG },
            encoded.reduce(0) { $0 + $1.carbsG },
            encoded.reduce(0) { $0 + $1.fatG }
        )
    }

    var write: SavedMealWrite? {
        let encoded = items.compactMap(\.encoded)
        guard encoded.count == items.count, !encoded.isEmpty else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return .init(name: trimmed, items: encoded, suggestSlot: suggestSlot, useInCheckIns: useInCheckIns)
    }

    init(from meal: MealSummary) {
        id = UUID().uuidString
        existingId = nil
        name = meal.title
        items = {
            if let items = meal.items, !items.isEmpty {
                return items.map(Item.init)
            }
            return [
                Item(
                    name: meal.title,
                    quantity: "1",
                    kcal: String(meal.kcal),
                    proteinG: Item.numberPublic(meal.proteinG),
                    carbsG: Item.numberPublic(meal.carbsG),
                    fatG: Item.numberPublic(meal.fatG)
                )
            ]
        }()
        suggestSlot = nil
        useInCheckIns = false
    }

    init(from meal: SavedMeal) {
        id = meal.id
        existingId = meal.id
        name = meal.name
        items = meal.items.isEmpty ? [Item()] : meal.items.map(Item.init)
        suggestSlot = meal.suggestSlot
        useInCheckIns = meal.useInCheckIns
    }

    init(from product: LogMealViewModel.BarcodeProduct) {
        let portion = product.food.portion(servings: product.servings)
        id = UUID().uuidString
        existingId = nil
        name = product.food.name
        items = [
            Item(
                name: product.food.name,
                quantity: product.servings == 1 ? "1 serving" : "\(product.servings.formatted()) servings",
                kcal: String(portion.kcal),
                proteinG: String(format: "%.1f", portion.proteinG),
                carbsG: String(format: "%.1f", portion.carbsG),
                fatG: String(format: "%.1f", portion.fatG)
            )
        ]
        suggestSlot = nil
        useInCheckIns = false
    }
}

extension SavedMealDraft.Item {
    static func numberPublic(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct SavedMealEditorView: View {
    @Binding var draft: SavedMealDraft
    var saving = false
    var error: String?
    let onSave: () async -> Bool

    @Environment(\.dismiss) private var dismiss

    private var canSave: Bool { draft.write != nil }

    var body: some View {
        SettingsScreen(title: draft.existingId == nil ? "My meal" : "Edit meal", subtitle: "Log it in one tap next time.") {
            VStack(alignment: .leading, spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Name").sectionLabelStyle()
                    TextField("Usual oats", text: $draft.name)
                        .font(Typography.voice(20, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .padding(14)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.hairline))
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack {
                        Text("Items").sectionLabelStyle()
                        Spacer()
                        Button {
                            draft.items.append(.init())
                        } label: {
                            Label("Add food", systemImage: "plus")
                                .font(Typography.data(12, weight: .semibold))
                                .foregroundStyle(Palette.accentDeep)
                        }
                        .buttonStyle(.plain)
                        .disabled(draft.items.count >= 20)
                    }

                    ForEach($draft.items) { $item in
                        editorItem($item)
                    }

                    let totals = draft.totals
                    HStack {
                        Text("\(totals.kcal) kcal")
                            .font(Typography.data(18, weight: .heavy))
                            .foregroundStyle(Palette.ink)
                            .monospacedDigit()
                        Spacer()
                        Text("P \(Int(totals.proteinG.rounded())) · C \(Int(totals.carbsG.rounded())) · F \(Int(totals.fatG.rounded()))")
                            .font(Typography.data(12, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .padding(.top, Space.xxs)
                }

                SettingsCard(padding: 0) {
                    VStack(spacing: 0) {
                        suggestRow
                        Divider().overlay(Palette.hairline)
                        Toggle(isOn: $draft.useInCheckIns) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use in check-ins")
                                    .font(Typography.data(16, weight: .bold))
                                    .foregroundStyle(Palette.ink)
                                Text("Show this as the suggestion when this meal is due.")
                                    .font(Typography.data(12))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                        }
                        .tint(Palette.accent)
                        .padding(16)
                        Divider().overlay(Palette.hairline)
                        SettingsRow(symbol: "waveform", title: "Siri phrase", value: "Coming later", showsChevron: false)
                            .opacity(0.55)
                            .accessibilityLabel("Siri phrase, coming later")
                    }
                }

                if let error {
                    Text(error)
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.accentDeep)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SettingsSaveBar(
                note: draft.useInCheckIns ? "Check-ins will offer this plate." : nil,
                saving: saving,
                disabled: !canSave
            ) {
                Task {
                    if await onSave() { dismiss() }
                }
            }
        }
    }

    private var suggestRow: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Suggest at").sectionLabelStyle()
            SegmentedPills(
                options: [nil, "breakfast", "lunch", "dinner"],
                selection: $draft.suggestSlot,
                title: { slot in
                    switch slot {
                    case "breakfast": return "Breakfast"
                    case "lunch": return "Lunch"
                    case "dinner": return "Dinner"
                    default: return "None"
                    }
                }
            )
        }
        .padding(16)
    }

    private func editorItem(_ item: Binding<SavedMealDraft.Item>) -> some View {
        Card(tint: Palette.surfaceRaised, padding: 14) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack {
                    TextField("Food", text: item.name)
                        .font(Typography.data(16, weight: .semibold))
                    if draft.items.count > 1 {
                        Button {
                            draft.items.removeAll { $0.id == item.wrappedValue.id }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.accentDeep)
                        }
                        .buttonStyle(.plain)
                    }
                }
                TextField("Portion", text: item.quantity)
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
                HStack(spacing: Space.xs) {
                    field("kcal", text: item.kcal)
                    field("P", text: item.proteinG)
                    field("C", text: item.carbsG)
                    field("F", text: item.fatG)
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).sectionLabelStyle()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .font(Typography.data(14, weight: .semibold))
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(Palette.surfaceSunk.opacity(0.7), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}

#if DEBUG
extension SavedMeal {
    static let samples: [SavedMeal] = [
        .init(
            id: "sm_oats",
            name: "Usual oats",
            items: [.init(name: "Oats with milk", quantity: "1 bowl", kcal: 420, proteinG: 18, carbsG: 62, fatG: 10)],
            kcal: 420,
            proteinG: 18,
            carbsG: 62,
            fatG: 10,
            suggestSlot: "breakfast",
            useInCheckIns: true,
            lastUsedAt: nil,
            useCount: 11,
            suggested: true
        ),
        .init(
            id: "sm_lunch",
            name: "Lunch box",
            items: [.init(name: "Chicken rice", quantity: "1 box", kcal: 680, proteinG: 45, carbsG: 70, fatG: 18)],
            kcal: 680,
            proteinG: 45,
            carbsG: 70,
            fatG: 18,
            suggestSlot: "lunch",
            useInCheckIns: true,
            lastUsedAt: nil,
            useCount: 6,
            suggested: false
        ),
    ]
}

extension BarcodeFood {
    static let sampleYogurt = BarcodeFood(
        code: "3017620422003",
        name: "Greek yogurt",
        brand: "Chobani",
        servingG: 170,
        kcal100g: 97,
        proteinG100g: 9,
        carbsG100g: 3.6,
        fatG100g: 5,
        fetchedAt: "2026-09-14T12:00:00Z"
    )
}

#Preview("Saved meal") {
    SavedMealEditorView(
        draft: .constant(SavedMealDraft(from: SavedMeal.samples[0])),
        onSave: { true }
    )
    .environment(AppEnvironment.preview())
}
#endif
