import PhotosUI
import SwiftUI

/// Meal logging (§5.5) — free text, a photo, or both. When the user submits, what
/// they wrote lifts to a compact "you said" chip and a shimmering `.redacted`
/// skeleton of the breakdown slides in beneath it; the real numbers then resolve
/// into the same card (count-up, staggered items), with a one-tap undo if the
/// parse is wrong.
struct LogMealSheet: View {
    /// Called once the user is done (logged & kept, or cancelled) — reload Home.
    let onFinished: () -> Void
    var previewModel: LogMealViewModel?

    @Environment(AppEnvironment.self) private var env
    @State private var model: LogMealViewModel?

    var body: some View {
        Group {
            if let model {
                LogMealBody(model: model, onFinished: onFinished)
            } else {
                Color.clear
            }
        }
        .task {
            if model == nil {
                model = previewModel ?? LogMealViewModel(
                    api: env.api,
                    onMealChanged: { env.changes.mealsChanged() }
                )
            }
        }
    }
}

private struct LogMealBody: View {
    @Bindable var model: LogMealViewModel
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var pickerItem: PhotosPickerItem?

    /// Skeleton stand-ins shown under the shimmer while the model is `.parsing`.
    private static let skeletonItems = ParsedBreakdown.skeletonItems

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch model.phase {
                case .compose:
                    compose
                case let .failed(message):
                    failed(message)
                default:
                    reveal
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: model.phase)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.background)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.attach(data)
                }
                pickerItem = nil
                focused = false
            }
        }
        .onChange(of: model.phase) { _, phase in
            if case .logged = phase { Haptics.landed() }
        }
        .onAppear { focused = true }
    }

    // MARK: Compose

    @ViewBuilder
    private var compose: some View {
        Text("What you ate")
            .font(Typography.voice(22))
            .foregroundStyle(Palette.ink)

        if let photo = model.photo {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: photo.preview)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button {
                    model.removePhoto()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white, Color.black.opacity(0.45))
                        .padding(8)
                }
            }
        }

        TextField("e.g. burrito bowl", text: $model.text, axis: .vertical)
            .font(Typography.data(16))
            .lineLimit(1 ... 3)
            .padding(14)
            .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .focused($focused)

        HStack(spacing: 12) {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label(model.photo == nil ? "Add photo" : "Change photo", systemImage: "camera")
                    .font(Typography.data(15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }

        ActionButton(title: "Log") {
            focused = false
            Task { await model.submit() }
        }
        .opacity(model.canSubmit ? 1 : 0.5)
        .disabled(!model.canSubmit)

        Text("A rough guess is fine.")
            .font(Typography.data(12))
            .foregroundStyle(Palette.inkFaint)
    }

    // MARK: Parse reveal (parsing skeleton → resolved result, one continuous card)

    @ViewBuilder
    private var reveal: some View {
        let logged: LogMealViewModel.Logged? = {
            if case let .logged(value) = model.phase { return value }
            return nil
        }()
        let parsing = logged == nil

        Text(headline(logged))
            .font(Typography.voice(22))
            .foregroundStyle(Palette.ink)
            .contentTransition(.opacity)

        inputChip

        ParsedBreakdown(
            summary: logged?.summary ?? "Reading the portions",
            kcal: logged?.kcal ?? 640,
            proteinG: logged?.proteinG ?? 41,
            items: logged?.items ?? Self.skeletonItems,
            notes: logged?.notes,
            redacted: parsing
        )
        .shimmering(parsing)

        if let logged {
            if logged.resolvedCheckIn {
                Text("Check-in resolved.")
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
                    .appearIn(0)
            }

            ActionButton(title: "Looks right") {
                onFinished()
            }
            .appearIn(1)

            Button(model.removing ? "Removing…" : "Remove") {
                Task { await model.undo() }
            }
            .font(Typography.data(14, weight: .medium))
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity)
            .disabled(model.removing)
            .appearIn(2)

            if let actionError = model.actionError {
                Text(actionError)
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity)
                    .appearIn()
            }
        }
    }

    private func headline(_ logged: LogMealViewModel.Logged?) -> String {
        guard let logged else { return "Estimating…" }
        return logged.fromPhoto ? "From photo" : "Logged"
    }

    /// What the user gave us, kept visible through parsing and the result so the
    /// source stays attached to the guess.
    @ViewBuilder
    private var inputChip: some View {
        let trimmed = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty || model.photo != nil {
            HStack(spacing: 10) {
                if let photo = model.photo {
                    Image(uiImage: photo.preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                Text(trimmed.isEmpty ? "Photo" : trimmed)
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surfaceSunk.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Failure

    @ViewBuilder
    private func failed(_ message: String) -> some View {
        Text("Not saved")
            .font(Typography.voice(22))
            .foregroundStyle(Palette.ink)
        inputChip
        Text(message)
            .font(Typography.data(14))
            .foregroundStyle(Palette.inkSoft)
        ActionButton(title: "Try again", kind: .secondary) { model.reset() }
    }
}

/// The macro breakdown card — used both as the redacted skeleton and the real
/// parsed result, at a stable position so the values resolve in place.
struct ParsedBreakdown: View {
    let summary: String?
    let kcal: Int
    let proteinG: Double
    let items: [LogMealResponse.Parsed.Item]
    let notes: String?
    var redacted: Bool = false

    static let skeletonItems: [LogMealResponse.Parsed.Item] = [
        .init(name: "Main portion", quantity: "1 serving", kcal: 280, proteinG: 32, carbsG: 4, fatG: 9),
        .init(name: "Side", quantity: "1 cup", kcal: 210, proteinG: 5, carbsG: 42, fatG: 3),
        .init(name: "Extras", quantity: "1 scoop", kcal: 150, proteinG: 5, carbsG: 20, fatG: 2),
    ]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                if let summary {
                    Text(summary)
                        .font(Typography.voice(17))
                        .foregroundStyle(Palette.ink)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(kcal)")
                        .font(Typography.data(28, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: Double(kcal)))
                        .monospacedDigit()
                    Text("kcal · \(Int(proteinG.rounded())) g protein")
                        .font(Typography.data(14))
                        .foregroundStyle(Palette.inkFaint)
                }

                if !items.isEmpty {
                    Divider().overlay(Palette.ink.opacity(0.06))
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack {
                            Text(item.name)
                                .font(Typography.data(14))
                                .foregroundStyle(Palette.ink)
                            Text(item.quantity)
                                .font(Typography.data(12))
                                .foregroundStyle(Palette.inkFaint)
                            Spacer()
                            Text("\(item.kcal) kcal")
                                .font(Typography.data(13))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .appearIn(redacted ? 0 : index, rise: 4)
                    }
                }

                if let notes, !notes.isEmpty {
                    Text(notes)
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .redacted(reason: redacted ? .placeholder : [])
    }
}

/// Full-screen photo parse as a trust decision: understand the guess, inspect
/// the portions, then keep it or return to the logger to correct it.
struct PhotoParseConfirm: View {
    @Bindable var model: LogMealViewModel
    var namespace: Namespace.ID
    var imageID: String
    var cardID: String
    /// Override the reject path (dev previews). Nil uses `model.undo()`.
    var onReject: (() -> Void)? = nil
    var onKeep: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false
    @State private var editing = false

    private var logged: LogMealViewModel.Logged? {
        if case let .logged(value) = model.phase { return value }
        return nil
    }

    private var parsing: Bool { logged == nil }

    private var items: [LogMealResponse.Parsed.Item] {
        if let items = logged?.items, !items.isEmpty { return items }
        return ParsedBreakdown.skeletonItems
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                HStack(alignment: .center, spacing: Space.md) {
                    photo

                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(parsing ? "Reading meal" : "Check estimate")
                            .font(Typography.display(27))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(parsing ? "Estimating portions." : "Review foods and portions.")
                            .font(Typography.data(13))
                            .foregroundStyle(Palette.inkSoft)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .staggerReveal(settled, index: 0, rise: 8)

                glance
                    .matchedGeometryEffect(id: cardID, in: namespace)
                    .redacted(reason: parsing ? .placeholder : [])
                    .shimmering(parsing)
                    .staggerReveal(settled, index: 1, rise: 8)

                plate
                    .redacted(reason: parsing ? .placeholder : [])
                    .shimmering(parsing)
                    .staggerReveal(settled, index: 2, rise: 10)

                if let notes = logged?.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Assumed").sectionLabelStyle()
                        ManagerNote(text: notes)
                    }
                    .staggerReveal(settled, index: 3, rise: 8)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.md)
            .padding(.bottom, Space.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if logged != nil {
                confirmBar
                    .staggerReveal(settled, index: 4, rise: 12)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: model.phase)
        .overlay {
            if editing, let logged {
                MealCorrectionEditor(
                    logged: logged,
                    saving: model.savingCorrection,
                    error: model.actionError,
                    onCancel: { editing = false },
                    onSave: { summary, items in
                        let saved = await model.correct(summary: summary, items: items)
                        if saved {
                            Haptics.landed()
                            editing = false
                        }
                        return saved
                    },
                    onRemove: removeMeal
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(Motion.adaptive(Motion.sheet, reduceMotion: reduceMotion), value: editing)
        .task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 240))
            settled = true
        }
    }

    @ViewBuilder
    private var photo: some View {
        if let photo = model.submittedPhoto {
            Image(uiImage: photo.preview)
                .resizable()
                .scaledToFill()
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Palette.hairline)
                )
                .clipped()
                .matchedGeometryEffect(id: imageID, in: namespace)
        }
    }

    private var glance: some View {
        Card(tint: Palette.surfaceRaised, elevation: .floating, padding: Space.md) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack {
                    Text("Found").sectionLabelStyle()
                    Spacer()
                    if let logged {
                        Text(confidenceLabel(logged.confidence))
                            .font(Typography.data(11, weight: .semibold))
                            .foregroundStyle(confidenceColor(logged.confidence))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(confidenceColor(logged.confidence).opacity(0.1), in: Capsule())
                    }
                }

                Text(logged?.summary ?? "Chicken and rice bowl")
                    .font(Typography.voice(20))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(logged?.kcal ?? 640)")
                        .font(Typography.data(32, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(logged?.kcal ?? 640)))
                    Text("kcal")
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkFaint)
                }

                Divider().overlay(Palette.hairline)

                HStack(spacing: 0) {
                    macroStat("Protein", logged?.proteinG ?? 41)
                    macroStat("Carbs", items.reduce(0) { $0 + $1.carbsG })
                    macroStat("Fat", items.reduce(0) { $0 + $1.fatG })
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func macroStat(_ label: String, _ grams: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Typography.data(11, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
                .textCase(.uppercase)
                .tracking(0.5)
            Text("\(Int(grams.rounded())) g")
                .font(Typography.data(17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
                .contentTransition(.numericText(value: grams))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var plate: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Text("Items").sectionLabelStyle()
                Spacer()
                Text("Review")
                    .font(Typography.data(10, weight: .medium))
                    .foregroundStyle(Palette.inkFaint)
            }

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(Palette.hairline) }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(Typography.data(15))
                                .foregroundStyle(Palette.ink)
                            Text(item.quantity)
                                .font(Typography.data(12))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(item.kcal) kcal")
                                .font(Typography.data(13))
                                .foregroundStyle(Palette.inkSoft)
                                .monospacedDigit()
                            if !parsing {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Palette.dayOnTrack)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private var confirmBar: some View {
        VStack(spacing: 10) {
            if let actionError = model.actionError {
                Text(actionError)
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity)
            }

            ActionButton(title: "Keep", action: onKeep)

            Button("Edit") {
                editing = true
            }
            .font(Typography.data(14, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background {
            Palette.background
                .overlay(alignment: .top) {
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }
        }
    }

    private func confidenceLabel(_ confidence: Double?) -> String {
        guard let confidence else { return "Estimate" }
        if confidence >= 0.75 { return "High confidence" }
        if confidence >= 0.5 { return "Typical estimate" }
        return "Rough estimate"
    }

    private func confidenceColor(_ confidence: Double?) -> Color {
        guard let confidence else { return Palette.inkSoft }
        return confidence >= 0.75 ? Palette.dayOnTrack : Palette.accent
    }

    private func removeMeal() {
        if let onReject {
            onReject()
        } else {
            Task { await model.undo() }
        }
    }
}

private struct EditableMealItem: Identifiable {
    let id = UUID()
    var name: String
    var quantity: String
    var kcal: String
    var proteinG: String
    var carbsG: String
    var fatG: String

    init(_ item: LogMealResponse.Parsed.Item) {
        name = item.name
        quantity = item.quantity
        kcal = String(item.kcal)
        proteinG = Self.number(item.proteinG)
        carbsG = Self.number(item.carbsG)
        fatG = Self.number(item.fatG)
    }

    init() {
        name = ""
        quantity = ""
        kcal = ""
        proteinG = ""
        carbsG = ""
        fatG = ""
    }

    var request: MealCorrectionRequest.Item? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let kcal = Int(kcal), kcal >= 0,
              let protein = decimal(proteinG), protein >= 0,
              let carbs = decimal(carbsG), carbs >= 0,
              let fat = decimal(fatG), fat >= 0 else { return nil }
        return .init(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            quantity: quantity.trimmingCharacters(in: .whitespacesAndNewlines),
            kcal: kcal,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat
        )
    }

    private func decimal(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

private struct MealCorrectionEditor: View {
    let saving: Bool
    let error: String?
    let onCancel: () -> Void
    let onSave: (String, [MealCorrectionRequest.Item]) async -> Bool
    let onRemove: () -> Void

    @State private var summary: String
    @State private var items: [EditableMealItem]
    @State private var confirmingRemove = false

    init(
        logged: LogMealViewModel.Logged,
        saving: Bool,
        error: String?,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, [MealCorrectionRequest.Item]) async -> Bool,
        onRemove: @escaping () -> Void
    ) {
        self.saving = saving
        self.error = error
        self.onCancel = onCancel
        self.onSave = onSave
        self.onRemove = onRemove
        _summary = State(initialValue: logged.summary ?? "")
        _items = State(initialValue: logged.items.isEmpty ? [.init()] : logged.items.map(EditableMealItem.init))
    }

    private var correctedItems: [MealCorrectionRequest.Item]? {
        let corrected = items.compactMap(\.request)
        return corrected.count == items.count && !corrected.isEmpty ? corrected : nil
    }

    private var canSave: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && correctedItems != nil
            && !saving
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                            .frame(width: 36, height: 36)
                            .background(Palette.surfaceSunk, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)

                    Spacer()
                    Text("Edit")
                        .font(Typography.data(13, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Edit meal")
                        .font(Typography.display(28))
                        .foregroundStyle(Palette.ink)
                    Text("Adjust foods or portions.")
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Name").sectionLabelStyle()
                    TextField("Meal name", text: $summary)
                        .font(Typography.voice(18))
                        .foregroundStyle(Palette.ink)
                        .padding(14)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(Palette.hairline)
                        )
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack {
                        Text("Items").sectionLabelStyle()
                        Spacer()
                        Button {
                            items.append(.init())
                        } label: {
                            Label("Add", systemImage: "plus")
                                .font(Typography.data(12, weight: .semibold))
                                .foregroundStyle(Palette.accentDeep)
                        }
                        .buttonStyle(.plain)
                        .disabled(saving || items.count >= 20)
                    }

                    ForEach($items) { $item in
                        EditableFoodCard(
                            item: $item,
                            canRemove: items.count > 1 && !saving,
                            onRemove: { items.removeAll { $0.id == item.id } }
                        )
                    }
                }

                if let error {
                    Text(error)
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.accentDeep)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.accentTint, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }

                removeControl
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.sm)
            .padding(.bottom, 130)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Space.xs) {
                ActionButton(title: saving ? "Saving…" : "Save") {
                    guard canSave, let correctedItems else { return }
                    Task { _ = await onSave(summary.trimmingCharacters(in: .whitespacesAndNewlines), correctedItems) }
                }
                .opacity(canSave ? 1 : 0.45)
                .disabled(!canSave)

                Button("Cancel", action: onCancel)
                    .font(Typography.data(14, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .disabled(saving)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(Palette.background.overlay(alignment: .top) {
                Rectangle().fill(Palette.hairline).frame(height: 1)
            })
        }
        .toolbar(.hidden, for: .tabBar)
    }

    @ViewBuilder
    private var removeControl: some View {
        if confirmingRemove {
            Card(tint: Palette.accentTint, padding: 14) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Remove meal?")
                        .font(Typography.voice(17))
                        .foregroundStyle(Palette.ink)
                    Text("This removes it from today.")
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkSoft)
                    HStack(spacing: Space.xs) {
                        Button("Back") { confirmingRemove = false }
                            .font(Typography.data(13, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        Button("Remove") { onRemove() }
                            .font(Typography.data(13, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Palette.accentDeep, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            Button("Remove meal") { confirmingRemove = true }
                .font(Typography.data(13, weight: .medium))
                .foregroundStyle(Palette.accentDeep)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct EditableFoodCard: View {
    @Binding var item: EditableMealItem
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        Card(tint: Palette.surfaceRaised, padding: 14) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.xs) {
                    TextField("Food", text: $item.name)
                        .font(Typography.data(16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    if canRemove {
                        Button(action: onRemove) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.accentDeep)
                                .frame(width: 30, height: 30)
                                .background(Palette.accentTint, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(item.name.isEmpty ? "food" : item.name)")
                    }
                }

                TextField("Portion, e.g. 1 cup", text: $item.quantity)
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(10)
                    .background(Palette.surfaceSunk.opacity(0.7), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

                HStack(spacing: Space.xs) {
                    numberField("kcal", text: $item.kcal)
                    numberField("protein", unit: "g", text: $item.proteinG)
                    numberField("carbs", unit: "g", text: $item.carbsG)
                    numberField("fat", unit: "g", text: $item.fatG)
                }
            }
        }
    }

    private func numberField(_ label: String, unit: String = "", text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).sectionLabelStyle()
                .tracking(0.4)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .font(Typography.data(14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Typography.data(10))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(Palette.surfaceSunk.opacity(0.7), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}

#if DEBUG
#Preview("Confirm") {
    PhotoParseConfirmPreview(model: .samplePhotoConfirm)
}

#Preview("Parsing") {
    PhotoParseConfirmPreview(model: .samplePhotoParsing)
}

private struct PhotoParseConfirmPreview: View {
    @State var model: LogMealViewModel
    @Namespace private var ns

    var body: some View {
        PhotoParseConfirm(
            model: model,
            namespace: ns,
            imageID: "preview-image",
            cardID: "preview-card",
            onKeep: {}
        )
        .environment(AppEnvironment.preview())
    }
}

#Preview("Compose sheet") {
    Color.black.sheet(isPresented: .constant(true)) {
        LogMealSheet(onFinished: {})
            .environment(AppEnvironment.preview())
            .presentationDetents([.medium, .large])
    }
}
#endif
