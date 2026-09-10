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
                TextField("Meal", text: $model.text, axis: .vertical)
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

/// The whole point of Today in one surface: what matters now and why.
struct TodayNowSurface: View {
    let home: HomeResponse
    let checkIn: HomeResponse.ActiveCheckIn?
    let namespace: Namespace.ID
    let geometryID: String
    let onOpenCheckIn: () -> Void

    private var fraction: Double {
        guard home.ledger.targetKcal > 0 else { return 0 }
        return min(1, max(0, Double(home.ledger.consumedKcal) / Double(home.ledger.targetKcal)))
    }

    var body: some View {
        if let checkIn {
            VStack(alignment: .leading, spacing: Space.xs) {
                if checkIn.status == "DEFERRED" {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                        Text(deferredLabel(checkIn.deferUntil))
                    }
                    .font(Typography.data(12, weight: .semibold))
                    .foregroundStyle(Palette.accentDeep)
                    .padding(.horizontal, 4)
                }

                Button(action: onOpenCheckIn) {
                    CheckInContent(checkIn: checkIn, restingElevation: .floating)
                        .matchedGeometryEffect(id: geometryID, in: namespace)
                }
                .buttonStyle(PressableCard())
            }
        } else {
            Card(
                tint: home.framing.accent ? Palette.accentTint : Palette.surfaceRaised,
                elevation: .floating,
                padding: 16
            ) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack {
                        Text("Now").sectionLabelStyle()
                        Spacer()
                        Text(stateLabel)
                            .font(Typography.data(11, weight: .semibold))
                            .foregroundStyle(stateColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(stateColor.opacity(0.1), in: Capsule())
                    }

                    Text(home.managerNote)
                        .font(Typography.voice(18))
                        .foregroundStyle(Palette.ink)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .center) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(abs(home.framing.heroKcal))")
                                .font(Typography.data(30, weight: .semibold))
                                .foregroundStyle(home.framing.accent ? Palette.accent : Palette.ink)
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(home.framing.heroKcal)))
                            Text("kcal \(metricCaption)")
                                .font(Typography.data(12))
                                .foregroundStyle(Palette.inkFaint)
                        }

                        Spacer(minLength: Space.xs)

                        VStack(alignment: .trailing, spacing: 2) {
                        Text("\(home.ledger.consumedKcal) / \(home.ledger.targetKcal)")
                                .font(Typography.data(11, weight: .medium))
                                .foregroundStyle(Palette.inkSoft)
                                .monospacedDigit()
                            if let protein = home.ledger.targetProteinG {
                                Text("\(Int(home.ledger.consumedProteinG.rounded())) / \(Int(protein.rounded())) g protein")
                                    .font(Typography.data(10))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.surfaceSunk)
                            Capsule()
                                .fill(home.framing.accent ? Palette.accent : Palette.dayOnTrack)
                                .frame(width: max(fraction > 0 ? 5 : 0, geo.size.width * fraction))
                        }
                    }
                    .frame(height: 5)
                    .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var stateLabel: String {
        switch home.framing.state {
        case "under": return "Room"
        case "over": return "Over"
        default: return "On track"
        }
    }

    private var stateColor: Color {
        home.framing.state == "under" ? Palette.accent : Palette.dayOnTrack
    }

    private var metricCaption: String {
        switch home.framing.state {
        case "under": return "left"
        case "over": return "over"
        default: return "left"
        }
    }

    private func deferredLabel(_ iso: String?) -> String {
        guard let iso, let date = MealFormat.parse(iso) else { return "Snoozed" }
        return "Until \(date.formatted(date: .omitted, time: .shortened))"
    }
}

/// The single mutable lane beneath the manager: logging progress or a landed
/// meal. The full composer is owned by Home so focus can be coordinated.
struct TodayLogStatus: View {
    let title: String
    let detail: String
    let working: Bool

    var body: some View {
        HStack(spacing: Space.sm) {
            ZStack {
                Circle()
                    .fill(working ? Palette.accentTint : Palette.dayOnTrack.opacity(0.13))
                    .frame(width: 38, height: 38)
                if working {
                    ProgressView()
                        .tint(Palette.accent)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.dayOnTrack)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.data(15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Text(detail)
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
                .elevation(.resting)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Palette.hairline))
        }
        .shimmering(working)
    }
}

/// A chronological record of what happened, plus one time-aware hint. Empty
/// future meal shells are intentionally absent.
struct TodayDayFeed: View {
    let meals: [MealSummary]
    let pending: DayTimeline.Pending?
    let currentSlot: DaySlot
    let currentClock: String
    let mealTimes: MealTimesPayload
    var landingNamespace: Namespace.ID?
    var landingCardID: String?
    let onOpenMeal: (MealSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(meals.isEmpty && pending == nil ? "Start here" : "Meals")
                    .sectionLabelStyle()
                Spacer()
                if !meals.isEmpty {
                    Text("\(meals.count) \(meals.count == 1 ? "meal" : "meals")")
                        .font(Typography.data(11))
                        .foregroundStyle(Palette.inkFaint)
                }
            }

            if meals.isEmpty, pending == nil {
                currentWindow(empty: true)
            } else {
                VStack(spacing: Space.xs) {
                    ForEach(meals) { meal in
                        Button {
                            onOpenMeal(meal)
                        } label: {
                            TimelineMealRow(
                                title: meal.title,
                                detail: mealDetail(meal),
                                kcal: meal.kcal
                            )
                        }
                        .buttonStyle(PressableCard())
                    }

                    if let pending {
                        pendingRow(pending)
                    }
                }

                currentWindow(empty: false)
            }
        }
    }

    @ViewBuilder
    private func pendingRow(_ pending: DayTimeline.Pending) -> some View {
        switch pending {
        case let .parsing(title):
            TimelineMealRow(title: title, detail: "Working it out…", kcal: 640, redacted: true)
                .shimmering(true)
        case let .logged(title, kcal):
            landing(TimelineMealRow(title: title, detail: "Just now", kcal: kcal))
        }
    }

    @ViewBuilder
    private func landing<Content: View>(_ content: Content) -> some View {
        if let landingCardID, let landingNamespace {
            content.matchedGeometryEffect(id: landingCardID, in: landingNamespace)
        } else {
            content
        }
    }

    private func currentWindow(empty: Bool) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: slotSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 34, height: 34)
                .background(Palette.accentTint, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(empty ? currentSlot.title : "Now · \(currentSlot.title)")
                    .font(Typography.data(14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(currentClock)
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkFaint)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceSunk.opacity(0.7), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func mealDetail(_ meal: MealSummary) -> String {
        let slot = DaySlot.assigning(iso: meal.loggedAt, times: mealTimes)
        return "\(MealFormat.time(meal.loggedAt)) · \(slot.title)"
    }

    private var slotSymbol: String {
        switch currentSlot {
        case .breakfast: return "sun.horizon.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "sunset.fill"
        }
    }
}

/// Remaining kcal as the day's vital, with enough context to understand the
/// number without turning the screen into a dashboard.
struct DayLedger: View {
    let ledger: HomeResponse.Ledger
    let framing: HomeResponse.Framing

    private var underEating: Bool { framing.state == "under" }
    private var fraction: Double {
        guard ledger.targetKcal > 0 else { return 0 }
        return min(1, max(0, Double(ledger.consumedKcal) / Double(ledger.targetKcal)))
    }

    private var caption: String {
        switch framing.state {
        case "under": return "to eat"
        case "over": return "over"
        default: return "on target"
        }
    }

    private var subtitle: String {
        guard let target = ledger.targetProteinG else { return caption }
        return "\(caption) · \(Int(ledger.consumedProteinG.rounded())) / \(Int(target.rounded())) g"
    }

    var body: some View {
        Card(tint: Palette.surfaceRaised, elevation: .floating, padding: Space.md) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .center) {
                    Text("Today").sectionLabelStyle()
                    Spacer()
                    Text(stateLabel)
                        .font(Typography.data(11, weight: .semibold))
                        .foregroundStyle(stateColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(stateColor.opacity(0.1), in: Capsule())
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(abs(framing.heroKcal))")
                        .font(Typography.hero)
                        .foregroundStyle(underEating ? Palette.accent : Palette.ink)
                        .contentTransition(.numericText(value: Double(framing.heroKcal)))
                        .monospacedDigit()
                    Text("kcal")
                        .font(Typography.data(16, weight: .medium))
                        .foregroundStyle(Palette.inkFaint)
                }
                Text(subtitle)
                    .font(Typography.data(13))
                    .foregroundStyle(underEating ? Palette.accentDeep.opacity(0.75) : Palette.inkSoft)
                    .contentTransition(.numericText(value: ledger.consumedProteinG))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.surfaceSunk)
                        Capsule()
                            .fill(underEating ? Palette.accent : Palette.dayOnTrack)
                            .frame(width: max(fraction > 0 ? 5 : 0, geo.size.width * fraction))
                    }
                }
                .frame(height: 7)
                .accessibilityHidden(true)

                HStack(spacing: 0) {
                    ledgerStat("Eaten", "\(ledger.consumedKcal)", "kcal")
                    ledgerStat("Target", "\(ledger.targetKcal)", "kcal")
                    ledgerStat(
                        "Protein",
                        "\(Int(ledger.consumedProteinG.rounded()))",
                        ledger.targetProteinG.map { "/ \(Int($0.rounded())) g" } ?? "g"
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(abs(framing.heroKcal)) kcal \(caption)")
    }

    private var stateLabel: String {
        switch framing.state {
        case "under": return "Room"
        case "over": return "Complete"
        default: return "On track"
        }
    }

    private var stateColor: Color {
        framing.state == "under" ? Palette.accent : Palette.dayOnTrack
    }

    private func ledgerStat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Typography.data(10, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Palette.inkFaint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Typography.data(16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                Text(unit)
                    .font(Typography.data(10))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Listing card for a logged meal — typographic cover, kcal as the "price".
struct MealCard: View {
    let meal: MealSummary
    @State private var photo: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MealCover(title: meal.title, height: 132, photo: photo)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(MealFormat.time(meal.loggedAt))
                        .font(Typography.data(13, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                    Text(meal.sourceLabel)
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkFaint)
                }
                Spacer()
                Text("\(meal.kcal) kcal")
                    .font(Typography.data(15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.hairline)
        )
        .elevation(.resting)
        .task(id: meal.photoUrl) { photo = await MealPhotoCache.shared.image(for: meal) }
    }
}

struct MealCover: View {
    let title: String
    var height: CGFloat = 132
    var photo: UIImage? = nil

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .overlay {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    ZStack {
                        Palette.accentTint
                        LinearGradient(
                            colors: [Color.clear, Palette.accentSoft.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if photo != nil {
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.45)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text(title)
                    .font(Typography.voice(height > 160 ? 26 : 20))
                    .foregroundStyle(photo == nil ? Palette.ink : Color.white)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .padding(16)
            }
            .clipped()
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

/// Breakfast / lunch / dinner as tactile day cards.
struct DayTimeline: View {
    struct Station: Identifiable {
        let slot: DaySlot
        let clock: String
        var meals: [MealSummary]
        var pending: Pending?
        var checkIn: HomeResponse.ActiveCheckIn?
        var id: DaySlot { slot }
    }

    enum Pending {
        case parsing(title: String)
        case logged(title: String, kcal: Int)
    }

    let stations: [Station]
    var overflowCheckIn: HomeResponse.ActiveCheckIn?
    var namespace: Namespace.ID
    var geometryID: String
    var landingNamespace: Namespace.ID?
    var landingCardID: String?
    var onOpenCheckIn: () -> Void
    var onOpenMeal: (MealSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                stationRow(station)
                    .appearIn(3 + index)
            }
            if let checkIn = overflowCheckIn {
                overflowRow(checkIn)
                    .appearIn(6)
            }
        }
    }

    @ViewBuilder
    private func stationRow(_ station: Station) -> some View {
        let filled = station.checkIn != nil || station.pending != nil || !station.meals.isEmpty
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Image(systemName: symbol(for: station.slot))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(filled ? Color.white : Palette.inkFaint)
                    .frame(width: 34, height: 34)
                    .background(filled ? Palette.accent : Palette.surfaceSunk, in: Circle())

                Text(station.slot.title)
                    .font(Typography.data(16, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                Spacer(minLength: 8)

                Text(station.clock)
                    .font(Typography.data(12, weight: .medium))
                    .foregroundStyle(Palette.inkFaint)
                }

            if let checkIn = station.checkIn {
                Button(action: onOpenCheckIn) {
                    CheckInContent(checkIn: checkIn, restingElevation: .floating)
                        .matchedGeometryEffect(id: geometryID, in: namespace)
                }
                .buttonStyle(PressableCard())
            }

            if let pending = station.pending {
                pendingCard(pending)
            }

            ForEach(station.meals) { meal in
                Button {
                    onOpenMeal(meal)
                } label: {
                    TimelineMealRow(title: meal.title, detail: MealFormat.time(meal.loggedAt), kcal: meal.kcal)
                }
                .buttonStyle(PressableCard())
            }

            if !filled {
                emptySlot
            }
        }
        .padding(Space.md)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(filled ? Palette.surfaceRaised : Palette.surface.opacity(0.72))
                .elevation(filled ? .resting : .flat)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(filled ? Palette.hairline : Palette.inkFaint.opacity(0.14))
                )
        }
    }

    @ViewBuilder
    private func overflowRow(_ checkIn: HomeResponse.ActiveCheckIn) -> some View {
        Button(action: onOpenCheckIn) {
            CheckInContent(checkIn: checkIn, restingElevation: .floating)
                .matchedGeometryEffect(id: geometryID, in: namespace)
        }
        .buttonStyle(PressableCard())
    }

    @ViewBuilder
    private func pendingCard(_ pending: Pending) -> some View {
        switch pending {
        case let .parsing(title):
            TimelineMealRow(title: title, detail: "Working it out…", kcal: 640, redacted: true)
                .shimmering(true)
        case let .logged(title, kcal):
            landing(
                TimelineMealRow(title: title, detail: "Just now", kcal: kcal)
            )
        }
    }

    @ViewBuilder
    private func landing<Content: View>(_ content: Content) -> some View {
        if let landingCardID, let landingNamespace {
            content.matchedGeometryEffect(id: landingCardID, in: landingNamespace)
        } else {
            content
        }
    }

    private var emptySlot: some View {
        Text("Empty")
            .font(Typography.voice(15))
            .foregroundStyle(Palette.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func symbol(for slot: DaySlot) -> String {
        switch slot {
        case .breakfast: return "sun.horizon.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "sunset.fill"
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
