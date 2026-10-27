import SwiftUI

/// The two most recently used saved plates — what the log sheet offers for a one-tap log.
enum SavedMealShortcuts {
    static let logSheetCount = 2

    static func logSheet(from meals: [SavedMeal]) -> [SavedMeal] {
        Array(meals.sorted(by: moreRecent).prefix(logSheetCount))
    }

    private static func moreRecent(_ a: SavedMeal, _ b: SavedMeal) -> Bool {
        let aTime = a.lastUsedAt.flatMap(MealFormat.parse)?.timeIntervalSince1970 ?? 0
        let bTime = b.lastUsedAt.flatMap(MealFormat.parse)?.timeIntervalSince1970 ?? 0
        if aTime != bTime { return aTime > bTime }
        if a.useCount != b.useCount { return a.useCount > b.useCount }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}

/// You → My meals. The full list lives here; the log sheet only shows recent ones.
struct SavedMealsSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var meals: [SavedMeal]
    @State private var error: String?
    @State private var loaded: Bool
    @State private var editor: SavedMealDraft?
    @State private var editorSaving = false
    @State private var editorError: String?
    private let usesPreview: Bool

    init(previewMeals: [SavedMeal]? = nil) {
        _meals = State(initialValue: previewMeals ?? [])
        _loaded = State(initialValue: previewMeals != nil)
        usesPreview = previewMeals != nil
    }

    var body: some View {
        InnerScreen(spacing: 12, onRefresh: { await load() }) {
            ScreenHeader(label: "My meals") {
                RoundIconButton("plus", label: "Add a plate") { editor = SavedMealDraft() }
            }

            if !loaded, error == nil {
                BusyDots(tint: Palette.amber)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if meals.isEmpty {
                empty
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                        Button { editor = SavedMealDraft(from: meal) } label: {
                            plateCard(meal)
                        }
                        .buttonStyle(PressableCard())
                        .appearIn(index + 1, rise: 10)
                    }
                }
            }

            if let error {
                SettingsErrorBanner(message: error)
                ActionButton(title: "Try again", kind: .secondary) { Task { await load() } }
            }
        }
        .sheet(item: $editor) { draft in
            SavedMealEditorView(
                draft: draft,
                saving: editorSaving,
                error: editorError,
                onSave: { await save($0) },
                onDelete: draft.existingId.map { id in { await remove(id: id) } }
            )
        }
        .onChange(of: editor?.id) { _, _ in editorError = nil }
        .task { if !usesPreview { await load() } }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("None yet.")
                .font(Typography.data(17, weight: .medium))
                .foregroundStyle(Palette.ink)
            Text("After you log, tap Save as my meal — or add a plate here.")
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .hintCopy()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 22)
        .appearIn(1, rise: 14)
    }

    private func plateCard(_ meal: SavedMeal) -> some View {
        HStack(spacing: 14) {
            kcalMark(meal)
            VStack(alignment: .leading, spacing: 6) {
                Text(FoodText.name(meal.name))
                    .font(Typography.data(17, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let slot = meal.suggestSlot.flatMap(MealSlot.init(rawValue:)) {
                        Text(slot.title)
                            .font(Typography.mono(10))
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.amber)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(Palette.ember.opacity(0.14), in: Capsule())
                    }
                    if let last = meal.lastUsedAt {
                        Text(MealFormat.when(last))
                            .font(Typography.data(12, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                            .lineLimit(1)
                    } else {
                        Text(usedLine(meal))
                            .font(Typography.data(12, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                            .lineLimit(1)
                            .hintCopy()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 22, fill: Color.white.opacity(0.035))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meal.name), \(meal.kcal) kilocalories")
        .accessibilityHint("Opens the editor")
    }

    private func kcalMark(_ meal: SavedMeal) -> some View {
        ZStack {
            Circle()
                .stroke(Palette.ember.opacity(0.22), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(1, Double(meal.kcal) / 900))
                .stroke(Palette.amber, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(meal.kcal.formatted())
                    .font(Typography.data(13, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("kcal")
                    .font(Typography.mono(8))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .frame(width: 58, height: 58)
        .accessibilityHidden(true)
    }

    private func usedLine(_ meal: SavedMeal) -> String {
        if let last = meal.lastUsedAt { return MealFormat.when(last) }
        if meal.useCount > 0 {
            return meal.useCount == 1 ? L10n( "Logged once") : L10n( "Logged \(meal.useCount) times")
        }
        return L10n( "Not logged yet")
    }

    private func load() async {
        error = nil
        do {
            let res: SavedMealsResponse = try await env.api.get("/api/saved-meals")
            meals = res.meals
            loaded = true
        } catch {
            self.error = UserFacingError.message(for: error, fallback: L10n( "Couldn’t load your meals. Try again."))
            loaded = true
        }
    }

    private func save(_ draft: SavedMealDraft) async -> Bool {
        guard let write = draft.write, !editorSaving else { return false }
        editorSaving = true
        editorError = nil
        defer { editorSaving = false }
        do {
            if let id = draft.existingId {
                let _: SavedMealResponse = try await env.api.patch("/api/saved-meals/\(id)", write)
            } else {
                let _: SavedMealResponse = try await env.api.post("/api/saved-meals", write)
            }
            await load()
            return true
        } catch {
            editorError = UserFacingError.message(for: error, fallback: L10n( "Couldn’t save. Try again."))
            return false
        }
    }

    private func remove(id: String) async -> Bool {
        guard !editorSaving else { return false }
        editorSaving = true
        editorError = nil
        defer { editorSaving = false }
        do {
            try await env.api.delete("/api/saved-meals/\(id)")
            meals.removeAll { $0.id == id }
            return true
        } catch {
            editorError = UserFacingError.message(for: error, fallback: L10n( "Couldn’t remove that plate. Try again."))
            return false
        }
    }
}
