import SwiftUI

/// A named plate being created or edited. Siri uses "Log my usual <slot>".
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
    @State private var draft: SavedMealDraft
    @State private var editingItem: UUID?
    var saving = false
    var error: String?
    let onSave: (SavedMealDraft) async -> Bool

    @Environment(\.dismiss) private var dismiss

    init(
        draft: SavedMealDraft,
        saving: Bool = false,
        error: String? = nil,
        onSave: @escaping (SavedMealDraft) async -> Bool
    ) {
        _draft = State(initialValue: draft)
        self.saving = saving
        self.error = error
        self.onSave = onSave
    }

    private var canSave: Bool { draft.write != nil }

    private static let colors: [Color] = [Palette.ember, Palette.amber, Color(hex: 0xFDE6CF), Color(hex: 0xC2410C), Color(hex: 0xFCD34D)]
    private static let slots: [(slot: String, title: String, minute: Int, x: CGFloat)] = [
        ("breakfast", "Breakfast", 480, 0.12), ("lunch", "Lunch", 780, 0.48), ("dinner", "Dinner", 1140, 0.86),
    ]

    var body: some View {
        InnerScreen(spacing: 16) {
            ScreenHeader(label: draft.existingId == nil ? "My meal" : "Edit meal")

            VStack(alignment: .leading, spacing: 4) {
                TextField("Usual oats", text: $draft.name)
                    .font(Typography.display(40))
                    .tracking(-1.4)
                    .foregroundStyle(Palette.ink)
                    .padding(.bottom, 4)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1).mask(
                            HStack(spacing: 3) { ForEach(0..<80, id: \.self) { _ in Rectangle().frame(width: 3) } }
                        )
                    }
                    .accessibilityLabel("Meal name")
                Text("Tap the name to rename · one tap to log next time")
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkFaint)
            }
            .appearIn(0, rise: 16)

            ringAndMacros.appearIn(1, rise: 14)

            VStack(spacing: 8) {
                ForEach(Array($draft.items.enumerated()), id: \.element.id) { index, $item in
                    itemRow($item, color: Self.colors[index % Self.colors.count])
                }
                Button {
                    let item = SavedMealDraft.Item()
                    draft.items.append(item)
                    editingItem = item.id
                } label: {
                    Text("+ Add food")
                        .font(Typography.data(14, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                }
                .buttonStyle(PressableCard())
                .disabled(draft.items.count >= 20)
            }
            .appearIn(2)

            slotTrack.appearIn(3)

            checkInPreview.appearIn(4)

            if let error {
                Text(error)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.danger)
            }
        }
        .animation(Motion.settle, value: editingItem)
        .animation(Motion.settle, value: draft.suggestSlot)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SettingsSaveBar(
                note: draft.useInCheckIns ? "Check-ins will offer this plate." : nil,
                saving: saving,
                disabled: !canSave
            ) {
                Task {
                    if await onSave(draft) { dismiss() }
                }
            }
        }
    }

    // MARK: Ring

    private var ringAndMacros: some View {
        let totals = draft.totals
        let kcals = draft.items.map { Int($0.kcal) ?? 0 }
        let sum = max(1, kcals.reduce(0, +))
        let grams = [totals.proteinG, totals.carbsG, totals.fatG]
        let maxG = max(1, grams.max() ?? 1)
        return HStack(spacing: 18) {
            ZStack {
                ForEach(Array(kcals.enumerated()), id: \.offset) { index, kcal in
                    let start = Double(kcals.prefix(index).reduce(0, +)) / Double(sum)
                    let end = start + Double(kcal) / Double(sum)
                    Circle()
                        .trim(from: start, to: max(start, end - 0.006))
                        .stroke(Self.colors[index % Self.colors.count], lineWidth: 20)
                        .rotationEffect(.degrees(-90))
                }
                if kcals.allSatisfy({ $0 == 0 }) {
                    Circle().stroke(Color.white.opacity(0.06), lineWidth: 20)
                }
                VStack(spacing: 2) {
                    Text(totals.kcal.formatted())
                        .font(Typography.data(32, weight: .light))
                        .tracking(-1.2)
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: Double(totals.kcal)))
                    Text("KCAL")
                        .font(Typography.mono(10))
                        .foregroundStyle(Color(hex: 0xFDE6CF))
                }
            }
            .frame(width: 130, height: 130)
            .padding(10)
            .shadow(color: Palette.ember.opacity(0.3), radius: 22)
            .animation(Motion.settle, value: kcals)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(totals.kcal) calories")

            VStack(spacing: 10) {
                ForEach(Array(zip(["Protein", "Carbs", "Fat"], [Palette.amber, Color(hex: 0xFDE6CF), Palette.ember]).enumerated()), id: \.offset) { index, macro in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(macro.0).font(Typography.data(12, weight: .regular)).foregroundStyle(Palette.inkSoft)
                            Spacer()
                            Text("\(Int(grams[index].rounded())) g").font(Typography.mono(13)).foregroundStyle(macro.1)
                        }
                        GeometryReader { geo in
                            Capsule().fill(Color.white.opacity(0.07))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(macro.1).frame(width: max(4, geo.size.width * grams[index] / maxG))
                                }
                        }
                        .frame(height: 4)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Items

    private func itemRow(_ item: Binding<SavedMealDraft.Item>, color: Color) -> some View {
        let open = editingItem == item.wrappedValue.id
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle().fill(color).frame(width: 10, height: 10).shadow(color: color.opacity(0.6), radius: 4)
                Button {
                    editingItem = open ? nil : item.wrappedValue.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.wrappedValue.name.isEmpty ? "New food" : item.wrappedValue.name)
                                .font(Typography.data(15, weight: .regular))
                                .foregroundStyle(item.wrappedValue.name.isEmpty ? Palette.inkFaint : Palette.ink)
                            Text(item.wrappedValue.quantity.isEmpty ? "Tap to fill in" : item.wrappedValue.quantity)
                                .font(Typography.data(12, weight: .regular))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        Spacer(minLength: 8)
                        Text(item.wrappedValue.kcal.isEmpty ? "—" : item.wrappedValue.kcal)
                            .font(Typography.mono(13))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if draft.items.count > 1 {
                    Button {
                        draft.items.removeAll { $0.id == item.wrappedValue.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x71717A))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item.wrappedValue.name)")
                }
            }
            if open {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("Food", text: item.name)
                            .font(Typography.data(15, weight: .regular))
                            .padding(10)
                            .glass(radius: 12, fill: Color.white.opacity(0.04))
                        TextField("Portion", text: item.quantity)
                            .font(Typography.data(13))
                            .foregroundStyle(Palette.inkSoft)
                            .padding(10)
                            .frame(width: 110)
                            .glass(radius: 12, fill: Color.white.opacity(0.04))
                    }
                    HStack(spacing: Space.xs) {
                        field("kcal", text: item.kcal)
                        field("P", text: item.proteinG)
                        field("C", text: item.carbsG)
                        field("F", text: item.fatG)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .glass(radius: 18, fill: Color.white.opacity(open ? 0.06 : 0.04))
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).sectionLabelStyle()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .font(Typography.mono(14))
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .glass(radius: 12, fill: Color.white.opacity(0.04))
    }

    // MARK: When

    /// Breakfast, lunch and dinner on a line through the day — the chosen one glows.
    private var slotTrack: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("When I offer it").sectionLabelStyle()
                Spacer()
                Button { draft.suggestSlot = nil } label: {
                    Text("Any time")
                        .font(Typography.data(12, weight: draft.suggestSlot == nil ? .medium : .regular))
                        .foregroundStyle(draft.suggestSlot == nil ? Palette.onBone : Palette.inkSoft)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(draft.suggestSlot == nil ? Palette.ink : Color.white.opacity(0.05), in: Capsule())
                        .overlay(Capsule().strokeBorder(draft.suggestSlot == nil ? .clear : Color.white.opacity(0.10)))
                }
                .buttonStyle(PressableCard())
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.amber.opacity(0.15), Palette.amber.opacity(0.5), Palette.haze.opacity(0.4)], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 2)
                        .offset(y: 19)
                    ForEach(Self.slots, id: \.slot) { s in
                        let on = draft.suggestSlot == s.slot
                        Button { draft.suggestSlot = s.slot } label: {
                            VStack(spacing: 1) {
                                ZStack {
                                    if on { EmberDot(size: 26) } else { Circle().fill(Color.white.opacity(0.35)).frame(width: 10, height: 10) }
                                }
                                .frame(height: 40)
                                Text(s.title)
                                    .font(Typography.data(13, weight: .regular))
                                    .foregroundStyle(on ? Palette.amber : Palette.inkSoft)
                                Text(formatMinutes(s.minute))
                                    .font(Typography.mono(10))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                            .frame(width: 80)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(x: s.x * w, y: 38)
                        .accessibilityLabel("Offer at \(s.title)")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .frame(height: 76)
        }
    }

    // MARK: Check-ins

    /// A switch over a preview of the notification it turns on.
    private var checkInPreview: some View {
        let slotTitle = Self.slots.first { $0.slot == draft.suggestSlot }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Offer in check-ins").sectionLabelStyle()
                Spacer()
                Toggle("Offer in check-ins", isOn: $draft.useInCheckIns)
                    .labelsHidden()
                    .tint(Palette.ember)
            }
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(RadialGradient(colors: [Color(hex: 0xFFD9A8), Palette.ember], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 30))
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(draft.useInCheckIns ? "\(slotTitle?.title ?? "A meal") slipped." : "Off · I’ll suggest something new")
                            .font(Typography.data(13, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(slotTitle.map { formatMinutes(CheckInSchedule.minute(afterMeal: $0.minute)) } ?? "any time")
                            .font(Typography.data(11, weight: .regular))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    Text("\(draft.name.isEmpty ? "Your usual" : draft.name) · \(draft.totals.kcal.formatted()) kcal · Eating it?")
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0x1C1C20, opacity: 0.85)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.10)))
            .shadow(color: .black.opacity(0.4), radius: 15, y: 10)
            .opacity(draft.useInCheckIns ? 1 : 0.35)
            .animation(Motion.settle, value: draft.useInCheckIns)
            .accessibilityHidden(true)
            Text("“Log my usual \(draft.suggestSlot ?? "meal")”")
                .font(Typography.mono(11))
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Siri phrase, Log my usual \(draft.suggestSlot ?? "meal")")
        }
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
        draft: SavedMealDraft(from: SavedMeal.samples[0]),
        onSave: { _ in true }
    )
    .environment(AppEnvironment.preview())
}
#endif
