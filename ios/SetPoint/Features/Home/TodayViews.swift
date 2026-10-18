import SwiftUI

// Today's lower blocks: the meal log and the log dock. The hero (the day dial,
// or the check-in takeover) lives in TodayHero.swift; HomeContent composes them.

// MARK: - Meal log

/// Today's meals under their usual meal times. Only times that have food — or
/// that passed with nothing logged — get a section; upcoming ones live on the
/// dial. Quiet mode never points at a missed meal.
struct MealLog: View {
    let home: HomeResponse
    let pending: TodayPending?
    var landingNamespace: Namespace.ID?
    var landingCardID: String?
    let onOpenMeal: (MealSummary) -> Void
    let onLogMissed: (HomeResponse.Day.Slot) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion), value: home.meals.map(\.id))
            .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: pending)
    }

    @ViewBuilder
    private var content: some View {
        if let day = home.day {
            let pendingSlotID = pending?.slot.rawValue
            let sections = day.slots.filter { slot in
                slot.slotState == .logged
                    || (slot.slotState == .missed && home.enforcementEnabled)
                    || slot.id == pendingSlotID
            }
            if sections.isEmpty {
                emptyHint
            } else {
                VStack(alignment: .leading, spacing: Space.md) {
                    ForEach(sections) { slot in
                        section(slot, holdsPending: slot.id == pendingSlotID)
                    }
                }
            }
        } else {
            flatList
        }
    }

    private func section(_ slot: HomeResponse.Day.Slot, holdsPending: Bool) -> some View {
        let meals = TodayLayout.meals(in: slot, from: home.meals)
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(slot.meal.title) · \(formatMinutes(slot.atMin))")
                    .sectionLabelStyle()
                Spacer()
                if slot.kcal > 0 {
                    Text("\(slot.kcal.formatted()) kcal")
                        .font(Typography.mono(11))
                        .foregroundStyle(Palette.inkFaint)
                }
            }

            ForEach(meals) { meal in
                Button {
                    onOpenMeal(meal)
                } label: {
                    TodayMealRow(meal: meal)
                }
                .buttonStyle(PressableCard())
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            if holdsPending, let pending {
                pendingRow(pending)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if slot.slotState == .missed, meals.isEmpty, !holdsPending {
                missedRow(slot)
            }
        }
    }

    private var flatList: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if !home.meals.isEmpty || pending != nil {
                Text("Meals").sectionLabelStyle()
            }
            ForEach(home.meals) { meal in
                Button {
                    onOpenMeal(meal)
                } label: {
                    TodayMealRow(meal: meal)
                }
                .buttonStyle(PressableCard())
            }
            if let pending {
                pendingRow(pending)
            }
            if home.meals.isEmpty, pending == nil {
                emptyHint
            }
        }
    }

    private var emptyHint: some View {
        if let schedule = TodayCopy.dayScheduleLine(home) {
            Text(schedule)
                .font(Typography.data(13))
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Meals you log land here, under their meal time.")
                .font(Typography.data(13))
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func pendingRow(_ pending: TodayPending) -> some View {
        switch pending {
        case let .parsing(title, _):
            TodayMealRow(title: title, detail: "…", kcal: 640, redacted: true)
                .shimmering(true)
        case let .logged(title, kcal, _):
            landing(TodayMealRow(title: title, detail: "now", kcal: kcal))
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

    private func missedRow(_ slot: HomeResponse.Day.Slot) -> some View {
        HStack(spacing: Space.sm) {
            Text("Nothing logged")
                .font(Typography.data(15, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
            Spacer(minLength: Space.xs)
            Button {
                onLogMissed(slot)
            } label: {
                Label("Add \(slot.meal.title.lowercased())", systemImage: "plus")
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.onBone)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Palette.ink, in: Capsule())
            }
            .buttonStyle(PressableCard())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }
}

/// A logged meal on Today: optional photo, name, time, kcal.
struct TodayMealRow: View {
    let title: String
    let detail: String
    let kcal: Int
    let meal: MealSummary?
    let redacted: Bool

    @State private var photo: UIImage?

    init(meal: MealSummary) {
        title = meal.title
        detail = MealFormat.time(meal.loggedAt)
        kcal = meal.kcal
        self.meal = meal
        redacted = false
    }

    init(title: String, detail: String, kcal: Int, redacted: Bool = false) {
        self.title = title
        self.detail = detail
        self.kcal = kcal
        meal = nil
        self.redacted = redacted
    }

    var body: some View {
        HStack(spacing: 14) {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.opacity)
            } else if !detail.isEmpty {
                Text(detail)
                    .font(Typography.mono(12))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(width: 44, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if photo != nil, !detail.isEmpty {
                    Text(detail)
                        .font(Typography.mono(11))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            Spacer(minLength: 8)
            Text("\(kcal)")
                .font(Typography.mono(13))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText(value: Double(kcal)))
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: Radius.lg)
        .redacted(reason: redacted ? .placeholder : [])
        .task(id: meal?.photoUrl) {
            guard let meal else { return }
            photo = await MealPhotoCache.shared.image(for: meal)
        }
    }
}

// MARK: - Log panel

/// Logging: a sheet that rises from the nav's "+". Type it, snap it, scan it,
/// tap a usual, or — when you don't remember — pick a rough size. While the
/// field is being typed into, it shrinks to the field and recents so it fits
/// above the keyboard.
struct LogDock: View {
    @Bindable var logger: LogMealViewModel
    var focused: FocusState<Bool>.Binding
    /// A usual-size meal for the rough-size estimate; nil hides it.
    var estimateKcal: Int? = nil
    /// The meal the rough size counts for when nothing is backdated.
    var currentSlot: MealSlot = .lunch
    let photoNamespace: Namespace.ID
    let photoGeometryID: String
    let onClose: () -> Void
    let onSubmit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var size = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)

            HStack(alignment: .top) {
                Headline(title, tail: typing ? nil : "Tap, snap or scan it.", size: typing ? 22 : 28)
                Spacer(minLength: 8)
                RoundIconButton("xmark", label: "Close", action: onClose)
            }

            if let backdate = logger.backdate {
                backdateChip(backdate)
            }

            SearchComposer(
                model: logger,
                focused: focused,
                onSubmit: onSubmit,
                photoNamespace: photoNamespace,
                photoGeometryID: photoGeometryID,
                prompt: "“Two eggs, toast and a latte”"
            )

            if typing {
                if logger.text.isEmpty, !logger.recents.isEmpty { recentsRow }
            } else {
                modeTiles
                usuals
                if let kcal = estimateKcal { roughSize(base: kcal) }
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                .fill(Palette.sheet)
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                        .strokeBorder(Palette.hairline)
                        .mask(alignment: .top) { Rectangle().frame(height: 40) }
                }
                .elevation(.lifted)
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: typing)
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: logger.backdate)
    }

    private var typing: Bool {
        focused.wrappedValue || !logger.text.isEmpty || logger.photo != nil
    }

    private var title: String {
        if let backdate = logger.backdate { return "What was \(backdate.slot.title.lowercased())?" }
        return "What did you eat?"
    }

    private var slot: MealSlot { logger.backdate?.slot ?? currentSlot }

    private func backdateChip(_ backdate: LogMealViewModel.Backdate) -> some View {
        HStack(spacing: 6) {
            Text("Adding to \(backdate.slot.title.lowercased()) · \(backdate.at.formatted(date: .omitted, time: .shortened))")
            Button {
                logger.backdate = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Palette.amber.opacity(0.6))
            }
            .accessibilityLabel("Log it for now instead")
        }
        .font(Typography.data(12, weight: .regular))
        .foregroundStyle(Palette.amber)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .glassCapsule(fill: Palette.ember.opacity(0.10), stroke: Palette.ember.opacity(0.25))
    }

    private var modeTiles: some View {
        HStack(spacing: 10) {
            tile("Photo", "camera") {
                logger.mode = .photo
                logger.showPhotoPicker = true
            }
            tile("Barcode", "barcode.viewfinder") {
                focused.wrappedValue = false
                logger.mode = .scan
                logger.openScanner()
            }
        }
    }

    private func tile(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .regular))
                Text(title)
                    .font(Typography.data(14, weight: .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .glass(radius: 16)
        }
        .buttonStyle(PressableCard())
        .disabled(logger.phase == .parsing)
    }

    /// Saved meals first, then today's-and-yesterday's recents, two columns.
    @ViewBuilder
    private var usuals: some View {
        let saved = Array(logger.savedMeals.prefix(4))
        let recents = Array(logger.recents.prefix(max(0, 4 - saved.count)))
        if !saved.isEmpty || !recents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Your usuals").sectionLabelStyle()
                    Spacer()
                    Text("One tap logs it")
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.inkFaint)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(saved) { meal in
                        usual(meal.name, kcal: meal.kcal, suggested: meal.suggested) {
                            focused.wrappedValue = false
                            Task { await logger.logSaved(meal) }
                        }
                    }
                    ForEach(recents) { meal in
                        usual(meal.summary ?? "Logged", kcal: meal.kcal, suggested: false) {
                            focused.wrappedValue = false
                            Task { await logger.logAgain(meal) }
                        }
                    }
                }
            }
        }
    }

    private func usual(_ name: String, kcal: Int, suggested: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(name)
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                HStack {
                    Text("\(kcal.formatted()) kcal")
                        .font(Typography.mono(12))
                        .foregroundStyle(Palette.amber)
                    Spacer(minLength: 0)
                    if suggested {
                        Text("NOW")
                            .font(Typography.mono(9, weight: .medium))
                            .foregroundStyle(Palette.onEmber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.amber, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(radius: 18, stroke: suggested ? Palette.amber.opacity(0.4) : Palette.hairline)
        }
        .buttonStyle(PressableCard())
        .disabled(logger.phase == .parsing)
        .accessibilityLabel("Log \(name), \(kcal) calories")
    }

    private var recentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(logger.recents) { meal in
                    Button {
                        focused.wrappedValue = false
                        Task { await logger.logAgain(meal) }
                    } label: {
                        HStack(spacing: 6) {
                            if meal.isScanned {
                                Image(systemName: "barcode")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                            Text(meal.summary ?? "")
                                .lineLimit(1)
                            Text("\(meal.kcal)")
                                .font(Typography.mono(12))
                                .foregroundStyle(Palette.amber)
                        }
                        .font(Typography.data(14, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .glassCapsule()
                    }
                    .buttonStyle(PressableCard())
                    .accessibilityLabel("Log \(meal.summary ?? "this") again, \(meal.kcal) calories")
                }
            }
        }
        .scrollClipDisabled()
    }

    /// Ate but don't remember the details? A rough size keeps the day honest.
    private func roughSize(base: Int) -> some View {
        let sizes = [("Small", 0.6), ("Normal", 1.0), ("Big", 1.5)]
        let kcal = Int((Double(base) * sizes[size].1 / 50).rounded()) * 50
        return VStack(alignment: .leading, spacing: 10) {
            (Text("Don’t remember exactly? ").foregroundColor(Palette.ink)
                + Text("Pick a size.").foregroundColor(Palette.inkSoft))
                .font(Typography.data(14, weight: .regular))
            SegmentedPills(options: [0, 1, 2], selection: $size, title: { sizes[$0].0 })
            ActionButton(title: "Log a \(sizes[size].0.lowercased()) \(slot.title.lowercased()) · ~\(kcal.formatted()) kcal", kind: .secondary) {
                focused.wrappedValue = false
                Task { await logger.logEstimate(slot: slot, kcal: kcal) }
            }
            .disabled(logger.phase == .parsing)
        }
        .padding(14)
        .glass(radius: 20, fill: Color.white.opacity(0.03))
    }
}

/// What the logger is doing, floating above the nav once the panel has closed:
/// working it out, queued offline, or logged.
struct LogStatusToast: View {
    @Bindable var logger: LogMealViewModel

    var body: some View {
        Group {
            switch logger.phase {
            case .parsing:
                line(symbol: nil, text: logger.submittedPrompt.isEmpty ? "Working it out…" : "Working out “\(logger.submittedPrompt)”…", working: true)
            case let .queued(message):
                line(symbol: "icloud.slash", text: message, working: false)
            case let .logged(logged) where !logger.confirmingPhoto:
                line(
                    symbol: "checkmark",
                    text: "Logged · \(logged.kcal) kcal" + (logged.resolvedCheckIn ? " · check-in answered" : ""),
                    working: false
                )
            default:
                EmptyView()
            }
        }
    }

    private func line(symbol: String?, text: String, working: Bool) -> some View {
        HStack(spacing: 8) {
            if working {
                BusyDots(tint: Palette.amber)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.amber)
            }
            Text(text)
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).fill(Color(hex: 0x1C1C20, opacity: 0.85)))
                .overlay(Capsule(style: .continuous).strokeBorder(Palette.hairline))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}
