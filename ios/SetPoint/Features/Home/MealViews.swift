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
                    model.attach(data)
                    model.mode = .type
                    model.showCamera = false
                    focused.wrappedValue = true
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

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var removing = false
    @State private var error: String?
    @State private var photo: UIImage?
    /// The meal as shown — replaced by the corrected one after a fix.
    @State private var meal: MealSummary
    @State private var fixing = false

    init(
        meal: MealSummary,
        onRemove: (() async throws -> Void)? = nil,
        onSaveAsMeal: (() -> Void)? = nil,
        onFixed: (() -> Void)? = nil
    ) {
        _meal = State(initialValue: meal)
        self.onRemove = onRemove
        self.onSaveAsMeal = onSaveAsMeal
        self.onFixed = onFixed
    }

    var body: some View {
        screenBody.trackScreen("meal_detail")
    }

    @ViewBuilder
    private var screenBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n("Logged \(MealFormat.time(meal.loggedAt)) · \(meal.sourceLabel)"))
                    .sectionLabelStyle()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.hairline))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Headline(meal.title, size: 32)
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
                        if let confidence = meal.parseConfidence {
                            Text(confidenceLine(confidence))
                                .font(Typography.data(12, weight: .regular))
                                .foregroundStyle(confidence >= 0.7 ? Palette.positive : Palette.amber)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background((confidence >= 0.7 ? Palette.positive : Palette.amber).opacity(0.12), in: Capsule())
                        }
                    }
                }
                .appearIn(0, rise: 14)

                HStack(spacing: 8) {
                    macroTile("Protein", meal.proteinG)
                    macroTile("Carbs", meal.carbsG)
                    macroTile("Fat", meal.fatG)
                }
                .appearIn(1, rise: 14)

                let items = meal.items ?? []
                if !items.isEmpty {
                    GlassList {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { ListDivider() }
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(Typography.data(15, weight: .regular))
                                        .foregroundStyle(Palette.ink)
                                    if !item.quantity.isEmpty {
                                        Text(item.quantity)
                                            .font(Typography.data(12, weight: .regular))
                                            .foregroundStyle(Palette.inkFaint)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text("\(item.kcal)")
                                    .font(Typography.mono(13))
                                    .foregroundStyle(Palette.inkSoft)
                            }
                            .padding(.vertical, 12)
                        }
                    }
                    .appearIn(2, rise: 14)
                }

                if let notes = meal.notes, !notes.isEmpty {
                    Text(notes)
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 4) {
                    HStack(spacing: 10) {
                        ActionButton(title: "Fix", kind: .secondary) { fixing = true }
                            .disabled(removing)
                        if onSaveAsMeal != nil {
                            ActionButton(title: "Save as my meal", kind: .secondary) { onSaveAsMeal?() }
                        }
                    }
                    if onRemove != nil {
                        Button(action: beginRemoval) {
                            HStack(spacing: 8) {
                                if removing { BusyDots(tint: Palette.danger) }
                                Text(removing ? "Removing · updating totals" : "Delete this meal")
                            }
                            .font(Typography.data(14, weight: .regular))
                            .foregroundStyle(Palette.danger)
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(removing)
                    }
                    if let error {
                        Text(error)
                            .font(Typography.data(13, weight: .regular))
                            .foregroundStyle(Palette.danger)
                    }
                }
                .appearIn(3, rise: 14)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheet)
        .presentationCornerRadius(32)
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: removing)
        .task { photo = await MealPhotoCache.shared.image(for: meal) }
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

    private func macroTile(_ label: String, _ grams: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Typography.mono(9))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Palette.inkFaint)
            Text("\(Int(grams.rounded())) g")
                .font(Typography.data(18, weight: .regular))
                .foregroundStyle(Palette.ink)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 14)
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
