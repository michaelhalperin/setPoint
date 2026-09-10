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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickerItem: PhotosPickerItem?

    private var showHint: Bool {
        focused.wrappedValue && (model.phase == .compose || isFailed)
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
                TextField(prompt, text: $model.text, axis: .vertical)
                    .font(Typography.data(16))
                    .lineLimit(1 ... 4)
                    .focused(focused)
                    .submitLabel(.send)
                    .onSubmit(submit)
                    .disabled(model.phase == .parsing)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                cameraButton

                if model.canSubmit {
                    sendButton
                        .transition(.scale.combined(with: .opacity))
                }
            }

            if showHint {
                Text("Food name is enough.")
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkFaint)
                    .padding(.leading, 14)
                    .transition(.opacity)
            }

            if case let .failed(message) = model.phase {
                Text(message)
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.accent)
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
                }
                pickerItem = nil
                focused.wrappedValue = true
            }
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
        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
            Image(systemName: "camera")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 34)
                .background(Palette.surfaceSunk, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.phase == .parsing)
        .accessibilityLabel("Add a photo")
    }

    private var sendButton: some View {
        Button(action: submit) {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Palette.accent, in: Circle())
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
    let meal: MealSummary
    var onRemove: (() async throws -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detent: PresentationDetent = .medium
    @State private var removing = false
    @State private var error: String?
    @State private var photo: UIImage?

    private var expanded: Bool { detent == .large }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: expanded ? 220 : 128)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 0) {
                    glance
                    VStack(alignment: .leading, spacing: Space.md) {
                        plate
                        notesBlock
                        meta
                        removeControl
                    }
                    .padding(.top, expanded ? Space.md : 0)
                    .frame(maxHeight: expanded ? nil : 0, alignment: .top)
                    .clipped()
                    .allowsHitTesting(expanded)
                    .accessibilityHidden(!expanded)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, photo == nil ? Space.lg : Space.md)
                .padding(.bottom, Space.lg)
            }
        }
        .scrollDisabled(!expanded)
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.background)
        .animation(Motion.adaptive(Motion.sheet, reduceMotion: reduceMotion), value: expanded)
        .task { photo = await MealPhotoCache.shared.image(for: meal) }
    }

    private var glance: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(meal.title)
                    .font(Typography.voice(expanded ? 28 : 24))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(expanded ? MealFormat.when(meal.loggedAt) : MealFormat.time(meal.loggedAt))
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkFaint)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(meal.kcal)")
                    .font(Typography.data(expanded ? 40 : 32, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(meal.kcal)))
                Text("kcal")
                    .font(Typography.data(15))
                    .foregroundStyle(Palette.inkFaint)
            }

            HStack(spacing: 0) {
                macroStat("Protein", meal.proteinG)
                macroStat("Carbs", meal.carbsG)
                macroStat("Fat", meal.fatG)
            }
        }
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var plate: some View {
        let items = meal.items ?? []
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Items")
                    .sectionLabelStyle()
                    .staggerReveal(expanded, index: 0, rise: 8)

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Palette.hairline) }
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(Typography.data(15))
                                    .foregroundStyle(Palette.ink)
                                if !item.quantity.isEmpty {
                                    Text(item.quantity)
                                        .font(Typography.data(12))
                                        .foregroundStyle(Palette.inkFaint)
                                }
                            }
                            Spacer(minLength: 8)
                            Text("\(item.kcal) kcal")
                                .font(Typography.data(13))
                                .foregroundStyle(Palette.inkSoft)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .staggerReveal(expanded, index: 1, rise: 10)
            }
        }
    }

    @ViewBuilder
    private var notesBlock: some View {
        if let notes = meal.notes, !notes.isEmpty {
            Text(notes)
                .font(Typography.voice(16))
                .foregroundStyle(Palette.inkSoft)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .staggerReveal(expanded, index: 2, rise: 8)
        }
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("From \(meal.sourceLabel.lowercased())")
                .font(Typography.data(13))
                .foregroundStyle(Palette.inkFaint)
            if let confidence = meal.parseConfidence {
                Text(confidenceLine(confidence))
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .staggerReveal(expanded, index: 3, rise: 8)
    }

    private func confidenceLine(_ value: Double) -> String {
        if value < 0.45 { return "Rough estimate" }
        if value < 0.7 { return "Typical estimate" }
        return "High confidence"
    }

    @ViewBuilder
    private var removeControl: some View {
        if onRemove != nil {
            VStack(alignment: .leading, spacing: Space.xs) {
                if let error {
                    Text(error)
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.accent)
                }

                if removing {
                    HStack(spacing: Space.sm) {
                        ProgressView()
                            .tint(Palette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Removing meal")
                                .font(Typography.data(14, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                            Text("Updating totals…")
                                .font(Typography.data(11))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(Palette.accentTint, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .transition(.opacity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Removing meal and updating today's totals")
                } else {
                    Button {
                        beginRemoval()
                    } label: {
                        Label("Remove meal", systemImage: "trash")
                            .font(Typography.data(14, weight: .semibold))
                            .foregroundStyle(Palette.accentDeep)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Palette.accentTint, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: removing)
            .padding(.top, Space.xs)
            .staggerReveal(expanded, index: 4, rise: 8)
        }
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
                    fallback: "Couldn't remove. Try again."
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
        return "\(day.string(from: date)) · \(time(iso))"
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
