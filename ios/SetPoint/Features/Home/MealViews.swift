import PhotosUI
import SwiftUI

/// Inline meal composer — a field that sends into the day. Camera stays on the
/// right; a send disc appears once there's something to log.
struct SearchComposer: View {
    @Bindable var model: LogMealViewModel
    var focused: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    var photoNamespace: Namespace.ID?
    var photoGeometryID = "photo-log-image"
    var prompt = "What did you eat?"
    /// Typing on its own: the words are the big text on the sheet.
    var large = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickerItem: PhotosPickerItem?

    private var showHint: Bool {
        focused.wrappedValue
            && model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (model.phase == .compose || isFailed)
    }

    private var isFailed: Bool {
        if case .failed = model.phase { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let photo = model.photo {
                photoChip(photo)
            }

            HStack(alignment: .bottom, spacing: 8) {
                HStack(spacing: 8) {
                    TextField(prompt, text: $model.text, axis: .vertical)
                        .font(large ? Typography.display(26) : Typography.data(16))
                        .tracking(large ? -0.7 : 0)
                        .lineLimit(1 ... 4)
                        .focused(focused)
                        .submitLabel(.send)
                        .onSubmit(submit)
                        .disabled(model.phase == .parsing)
                        .accessibilityHint("Food name is enough.")

                    if showHint {
                        Text("Food name is enough")
                            .font(Typography.data(12, weight: .medium))
                            .foregroundStyle(Palette.inkFaint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .fixedSize()
                            .allowsHitTesting(false)
                            .transition(.opacity)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .glass(radius: 25, fill: Color.white.opacity(0.05), stroke: Color.white.opacity(0.10))

                cameraButton

                if model.canSubmit {
                    sendButton
                        .transition(.scale.combined(with: .opacity))
                }
            }

            if case let .failed(message) = model.phase {
                Text(message)
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.danger)
                    .padding(.leading, 14)
            }
        }
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: model.canSubmit)
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: showHint)
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: model.photo != nil)
        .accessibilityElement(children: .contain)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.attach(data)
                    model.mode = .type
                }
                pickerItem = nil
                focused.wrappedValue = true
            }
        }
        .photosPicker(isPresented: $model.showPhotoPicker, selection: $pickerItem, matching: .images)
        .fullScreenCover(isPresented: $model.showCamera) {
            CameraCapture(
                onPhoto: { data in
                    model.showCamera = false
                    focused.wrappedValue = false
                    Task { await model.logPhoto(data) }
                },
                onCancel: { model.showCamera = false }
            )
            .ignoresSafeArea()
        }
    }

    private func photoChip(_ photo: MealPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            photoThumb(photo)
            Button {
                model.removePhoto()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.45))
            }
            .offset(x: 6, y: -6)
            .accessibilityLabel("Remove photo")
        }
        .padding(.leading, 4)
        .padding(.top, 6)
    }

    @ViewBuilder
    private func photoThumb(_ photo: MealPhoto) -> some View {
        Image(uiImage: photo.preview)
            .resizable()
            .scaledToFill()
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .modifier(OptionalMatchedGeometry(id: photoGeometryID, namespace: photoNamespace))
    }

    private var cameraButton: some View {
        Menu {
            PhotoSourceButtons(model: model)
        } label: {
            Image(systemName: "camera")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Palette.ink)
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.white.opacity(0.05)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.phase == .parsing)
        .accessibilityLabel("Add a photo")
    }

    private var sendButton: some View {
        Button(action: submit) {
            EmberBall(size: 50, glow: true) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log")
    }

    private func submit() {
        guard model.canSubmit else { return }
        focused.wrappedValue = false
        onSubmit()
    }
}

private struct OptionalMatchedGeometry: ViewModifier {
    let id: String
    var namespace: Namespace.ID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// Meal listing → detail. Medium detent is the glance (photo, name, kcal);
/// large reveals the breakdown and remove.
struct MealDetailSheet: View {
    var onRemove: (() async throws -> Void)?
    var onSaveAsMeal: (() -> Void)? = nil
    /// After a fix is saved, so the presenter can reload its list.
    var onFixed: (() -> Void)? = nil
    /// Today's calorie target, for "x% of today". Nil off Today.
    var dayKcalTarget: Int? = nil
    /// Log the same plate again, now.
    var onLogAgain: (() -> Void)? = nil
    /// Save as my meal right here, over this sheet (instead of after it closes).
    var onSaveDraft: ((SavedMealDraft) async -> Bool)? = nil
    var editorSaving = false
    var editorError: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var removing = false
    @State private var error: String?
    @State private var photo: UIImage?
    /// The meal as shown — replaced by the corrected one after a fix.
    @State private var meal: MealSummary
    @State private var fixing = false
    @State private var confirmingDelete = false
    @State private var draft: SavedMealDraft?
    @State private var saved = false

    init(
        meal: MealSummary,
        onRemove: (() async throws -> Void)? = nil,
        onSaveAsMeal: (() -> Void)? = nil,
        onFixed: (() -> Void)? = nil,
        dayKcalTarget: Int? = nil,
        onLogAgain: (() -> Void)? = nil,
        onSaveDraft: ((SavedMealDraft) async -> Bool)? = nil,
        editorSaving: Bool = false,
        editorError: String? = nil
    ) {
        _meal = State(initialValue: meal)
        self.onRemove = onRemove
        self.onSaveAsMeal = onSaveAsMeal
        self.onFixed = onFixed
        self.dayKcalTarget = dayKcalTarget
        self.onLogAgain = onLogAgain
        self.onSaveDraft = onSaveDraft
        self.editorSaving = editorSaving
        self.editorError = editorError
    }

    var body: some View {
        screenBody.trackScreen("meal_detail")
    }

    private var canSave: Bool { onSaveDraft != nil || onSaveAsMeal != nil }

    @ViewBuilder
    private var screenBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                topBar
                if let photo { hero(photo) }
                header.appearIn(0, rise: 14)
                composition.appearIn(1, rise: 14)
                breakdown.appearIn(2, rise: 14)
                assumptions
                deleteRow
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        // What you came to do stays in reach however long the breakdown is.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actions
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.sm)
                .padding(.bottom, Space.xs)
                .background {
                    LinearGradient(colors: [Palette.sheet.opacity(0), Palette.sheet, Palette.sheet], startPoint: .top, endPoint: .bottom)
                        .padding(.top, -Space.md)
                        .ignoresSafeArea()
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheet)
        .presentationCornerRadius(32)
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: removing)
        .task { photo = await MealPhotoCache.shared.image(for: meal) }
        .confirmationDialog("Delete this meal?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete meal", role: .destructive, action: beginRemoval)
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(L10n("\(meal.kcal) kcal comes off today’s total."))
        }
        .sheet(item: $draft) { draft in
            SavedMealEditorView(
                draft: draft,
                saving: editorSaving,
                error: editorError,
                onSave: { draft in
                    let ok = await onSaveDraft?(draft) ?? false
                    if ok {
                        saved = true
                        Haptics.landed()
                    }
                    return ok
                }
            )
        }
        .fullScreenCover(isPresented: $fixing) {
            MealFixView(
                meal: meal,
                onSaved: { corrected in
                    meal = corrected
                    onFixed?()
                },
                onRemove: {
                    fixing = false
                    beginRemoval()
                },
                onClose: { fixing = false }
            )
        }
    }

    // MARK: Sections

    private var topBar: some View {
        HStack(spacing: 8) {
            chip(L10n("\(MealFormat.time(meal.loggedAt)) · \(meal.sourceLabel)"), symbol: sourceSymbol)
            if let confidence = meal.parseConfidence {
                let tint = confidence >= 0.7 ? Palette.positive : Palette.amber
                Text(confidenceLine(confidence))
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(tint.opacity(0.12), in: Capsule())
            } else if meal.isScanned {
                chip(L10n("Label values"), symbol: "checkmark.seal", tint: Palette.positive)
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.top, Space.sm)
    }

    private func hero(_ photo: UIImage) -> some View {
        Image(uiImage: photo)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hairline))
            .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            FittingHeadline(meal.title, size: 30)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(meal.kcal.formatted())
                    .font(.system(size: 52, weight: .light))
                    .tracking(-2)
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: Double(meal.kcal)))
                Text("kcal")
                    .font(Typography.data(16, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                if let target = dayKcalTarget, target > 0 {
                    Text(L10n("\(Int((Double(meal.kcal) / Double(target) * 100).rounded()))% of today"))
                        .font(Typography.mono(12))
                        .foregroundStyle(Palette.amber)
                }
            }
        }
    }

    /// Where the calories come from: one split bar, then grams and share per macro.
    private var composition: some View {
        let p = meal.proteinG * 4, c = meal.carbsG * 4, f = meal.fatG * 9
        let total = max(p + c + f, 1)
        return VStack(alignment: .leading, spacing: 10) {
            GeometryReader { box in
                HStack(spacing: 3) {
                    Capsule().fill(Palette.amber).frame(width: max(4, (box.size.width - 6) * p / total))
                    Capsule().fill(Palette.ink).frame(width: max(4, (box.size.width - 6) * c / total))
                    Capsule().fill(Palette.inkFaint).frame(width: max(4, (box.size.width - 6) * f / total))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            HStack(spacing: 8) {
                macroTile("Protein", meal.proteinG, share: p / total, color: Palette.amber)
                macroTile("Carbs", meal.carbsG, share: c / total, color: Palette.ink)
                macroTile("Fat", meal.fatG, share: f / total, color: Palette.inkFaint)
            }
        }
    }

    @ViewBuilder
    private var breakdown: some View {
        let items = meal.items ?? []
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("What’s in it").sectionLabelStyle()
                GlassList {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { ListDivider() }
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(Typography.data(15, weight: .regular))
                                    .foregroundStyle(Palette.ink)
                                Text(itemDetail(item))
                                    .font(Typography.data(12, weight: .regular))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                            Spacer(minLength: 8)
                            Text("\(item.kcal)")
                                .font(Typography.mono(13))
                                .foregroundStyle(Palette.inkSoft)
                        }
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var assumptions: some View {
        if let notes = meal.notes, !notes.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 6) {
                    Text(notes)
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Not right? Fix it") { fixing = true }
                        .font(Typography.data(13, weight: .medium))
                        .foregroundStyle(Palette.amber)
                        .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(radius: 16)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if let onLogAgain {
                ActionButton(title: L10n("Log it again · \(meal.kcal)"), symbol: "arrow.clockwise") {
                    Haptics.select()
                    onLogAgain()
                }
                .disabled(removing)
            }
            HStack(spacing: 8) {
                actionTile("Fix", symbol: "slider.horizontal.3") { fixing = true }
                if canSave {
                    actionTile(saved ? "Saved" : "Save", symbol: saved ? "star.fill" : "star", tint: saved ? Palette.amber : Palette.ink) {
                        if onSaveDraft != nil {
                            draft = SavedMealDraft(from: meal)
                        } else {
                            onSaveAsMeal?()
                        }
                    }
                    .disabled(saved)
                }
            }
            if let error {
                Text(error)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.danger)
            }
        }
    }

    @ViewBuilder
    private var deleteRow: some View {
        if onRemove != nil {
            Button { confirmingDelete = true } label: {
                HStack(spacing: 8) {
                    if removing { BusyDots(tint: Palette.danger) }
                    Text(removing ? "Removing · updating totals" : "Delete meal")
                }
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(Palette.danger)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(removing)
        }
    }

    // MARK: Pieces

    private var sourceSymbol: String {
        switch meal.source {
        case "PHOTO": return "camera"
        case "BARCODE": return "barcode.viewfinder"
        case "SAVED": return "star"
        case "PRESCRIPTION": return "bell"
        default: return "text.alignleft"
        }
    }

    private func chip(_ text: String, symbol: String, tint: Color = Palette.inkSoft) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
            Text(text).font(Typography.data(12, weight: .regular))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    private func itemDetail(_ item: MealSummary.Item) -> String {
        let protein = L10n("\(Int(item.proteinG.rounded())) g protein")
        return item.quantity.isEmpty ? protein : "\(item.quantity) · \(protein)"
    }

    private func macroTile(_ label: String, _ grams: Double, share: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(LocalizedStringKey(label))
                    .font(Typography.mono(9))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.inkFaint)
            }
            Text(L10n("\(Int(grams.rounded())) g"))
                .font(Typography.data(18, weight: .regular))
                .foregroundStyle(Palette.ink)
            Text(L10n("\(Int((share * 100).rounded()))% of kcal"))
                .font(Typography.data(11))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 14)
        .accessibilityElement(children: .combine)
    }

    private func actionTile(_ title: LocalizedStringKey, symbol: String, tint: Color = Palette.ink, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Typography.data(15, weight: .regular))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: 52)
                .glassCapsule(fill: Color.white.opacity(0.06), stroke: Color.white.opacity(0.10))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableCard())
    }

    private func confidenceLine(_ value: Double) -> String {
        if value < 0.45 { return L10n( "Rough estimate") }
        if value < 0.7 { return L10n( "Typical estimate") }
        return L10n( "High confidence")
    }

    private func beginRemoval() {
        guard let onRemove, !removing else { return }
        removing = true
        error = nil

        Task {
            do {
                try await onRemove()
                dismiss()
            } catch {
                self.error = UserFacingError.message(
                    for: error,
                    fallback: L10n( "Couldn't remove. Try again.")
                )
                removing = false
            }
        }
    }
}

/// Compact meal row for a timeline slot — not the typographic listing poster.
struct TimelineMealRow: View {
    let title: String
    var detail: String
    let kcal: Int
    var redacted = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.data(16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if !detail.isEmpty {
                    Text(detail)
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            Spacer(minLength: 8)
            Text("\(kcal) kcal")
                .font(Typography.data(14, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(kcal)))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.hairline)
        )
        .elevation(.resting)
        .redacted(reason: redacted ? .placeholder : [])
    }
}

enum MealFormat {
    static func time(_ iso: String) -> String {
        guard let date = parse(iso) else { return "" }
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }

    static func when(_ iso: String) -> String {
        guard let date = parse(iso) else { return time(iso) }
        let day = DateFormatter()
        day.dateFormat = "EEE d MMM"
        return L10n( "\(day.string(from: date)) · \(time(iso))")
    }

    static func parse(_ iso: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: iso) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: iso)
    }
}
