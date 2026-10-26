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
            .animation(
                Motion.adaptive(Motion.enter, reduceMotion: reduceMotion),
                value: home.meals.map(\.id)
            )
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
                .transition(
                    .asymmetric(
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

    /// Nothing logged yet: an empty plate and the day's meal times on a line, the next one lit.
    private var emptyHint: some View {
        let slots = home.day?.slots ?? []
        let next = slots.first { $0.slotState == .now || $0.slotState == .upcoming }
        let tail =
            next.map { "\($0.meal.title) is next at \(formatMinutes($0.atMin))." }
            ?? TodayCopy.dayScheduleLine(home)
            ?? "Meals you log land here, under their meal time."
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                stops: [
                                    .init(color: Color(hex: 0x1C1B19), location: 0.58),
                                    .init(color: Color(hex: 0x2A2723), location: 0.6),
                                    .init(color: Color(hex: 0x2A2723), location: 0.66),
                                    .init(color: Color(hex: 0x121110), location: 0.68),
                                ], center: .center, startRadius: 0, endRadius: 32)
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: .black.opacity(0.6), radius: 12, y: 8)
                    EmberDot(size: 14, glow: 0.5).opacity(0.6)
                }
                .accessibilityHidden(true)
                Headline("Clean plate so far.", tail: tail, size: 20, persistTail: next != nil || TodayCopy.dayScheduleLine(home) != nil)
            }
            if !slots.isEmpty {
                GeometryReader { geo in
                    let w = geo.size.width
                    let first = slots.map(\.atMin).min() ?? 480
                    let last = max(first + 60, slots.map(\.atMin).max() ?? 1140)
                    let x = { (m: Int) in 8 + CGFloat(m - first) / CGFloat(last - first) * (w - 16)
                    }
                    ZStack(alignment: .topLeading) {
                        Capsule().fill(Color.white.opacity(0.08)).frame(height: 2).offset(y: 8)
                        ForEach(slots) { slot in
                            let isNext = slot.id == next?.id
                            VStack(spacing: 7) {
                                Group {
                                    if isNext {
                                        Circle().strokeBorder(Palette.amber, lineWidth: 2)
                                            .background(Circle().fill(Palette.background))
                                            .frame(width: 18, height: 18)
                                            .shadow(color: Palette.amber.opacity(0.6), radius: 6)
                                    } else if slot.slotState == .missed {
                                        GhostRing(size: 10)
                                    } else {
                                        Circle().strokeBorder(
                                            Color.white.opacity(0.25), lineWidth: 1.5
                                        )
                                        .background(Circle().fill(Palette.background))
                                        .frame(width: 10, height: 10)
                                    }
                                }
                                .frame(height: 18)
                                Text(formatMinutes(slot.atMin))
                                    .font(Typography.mono(9))
                                    .foregroundStyle(isNext ? Palette.amber : Color(hex: 0x52525B))
                                    .fixedSize()
                            }
                            .position(x: x(slot.atMin), y: 18)
                        }
                    }
                }
                .frame(height: 40)
                .accessibilityHidden(true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 24, fill: Color.white.opacity(0.03))
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
                .strokeBorder(
                    Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
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
            Image(systemName: "chevron.forward")
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

/// Logging: a sheet that rises from the nav's "+". Type it, snap it with the
/// live camera, scan it, tap a usual or a recent meal, or — when you don't
/// remember — pick a rough size. While the keyboard is up, it shrinks to the
/// field and recents so it fits above it.
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
    /// Order nearby. Nil hides the tile.
    var onOrder: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var size = 1
    @State private var keyboardUp = false

    var body: some View {
        screenBody.trackScreen("log_panel")
    }

    @ViewBuilder
    private var screenBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)

            HStack(alignment: .top) {
                Headline(
                    title, tail: typing ? nil : "Tap, snap or scan it.", size: typing ? 22 : 28)
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
                prompt: "“Two eggs, toast and a latte”",
                large: typing && logger.photo == nil,
                showsCamera: !showsLiveCamera
            )
            .onChange(of: logger.text) { _, _ in
                logger.onComposerTextChanged()
            }

            if typing {
                if !logger.catalogHits.isEmpty {
                    catalogHits
                } else if !tokens.isEmpty {
                    tokenRow
                }
                if logger.text.isEmpty, !logger.recents.isEmpty { recentsRow }
            } else {
                // Short enough to fit: no scrolling. Taller (camera + a long
                // recent list): the part under the field scrolls.
                ViewThatFits(in: .vertical) {
                    browse
                    ScrollView { browse }
                        .scrollBounceBehavior(.basedOnSize)
                }
                .frame(maxHeight: browseMaxHeight)
                // Full width, so the sideways recent list runs to the screen edge;
                // `browse` puts the margins back on everything else.
                .padding(.horizontal, -Space.gutter)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                .fill(Palette.sheet)
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous
                    )
                    .strokeBorder(Palette.hairline)
                    .mask(alignment: .top) { Rectangle().frame(height: 40) }
                }
                .elevation(.lifted)
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: typing)
        .animation(
            Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: logger.backdate
        )
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        ) { _ in
            keyboardUp = true
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in
            keyboardUp = false
        }
    }

    /// Everything under the field while the keyboard is down.
    private var browse: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsLiveCamera {
                LiveMealCamera(
                    onPhoto: { data in
                        focused.wrappedValue = false
                        Task { await logger.logPhoto(data) }
                    },
                    onLibrary: { logger.openPhotoLibrary() },
                    disabled: logger.phase == .parsing
                )
            }
            modeTiles
            usuals
            recentList
            if let kcal = estimateKcal { roughSize(base: kcal) }
        }
        .padding(.horizontal, Space.gutter)
    }

    /// The live camera, until there's a photo or one is being read.
    private var showsLiveCamera: Bool {
        !typing && logger.photo == nil && logger.phase != .parsing
    }

    /// Leaves the header, the field and some of the screen above the sheet.
    private var browseMaxHeight: CGFloat {
        let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.height ?? 844
        return max(280, screen * 0.86 - 190)
    }

    private var catalogHits: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Foods").sectionLabelStyle()
            VStack(spacing: 0) {
                ForEach(logger.catalogHits.prefix(6)) { food in
                    let portion = food.portion(grams: food.defaultGrams)
                    Button {
                        focused.wrappedValue = false
                        logger.pickCatalog(food)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.name)
                                    .font(Typography.data(14, weight: .regular))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                if let serving = food.servingDesc, !serving.isEmpty {
                                    Text(serving)
                                        .font(Typography.data(12, weight: .regular))
                                        .foregroundStyle(Palette.inkFaint)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 8)
                            Text("\(portion.kcal)")
                                .font(Typography.mono(12))
                                .foregroundStyle(Palette.amber)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(PressableCard())
                    .accessibilityLabel("\(food.name), \(portion.kcal) calories")
                    if food.id != logger.catalogHits.prefix(6).last?.id {
                        Rectangle().fill(Palette.hairline).frame(height: 1)
                    }
                }
            }
            .glass(radius: 16)
        }
        .transition(.opacity)
    }

    /// The foods in what's typed so far — "two eggs, toast and a banana" → three chips.
    private var tokens: [String] {
        logger.text
            .replacingOccurrences(of: " and ", with: ",")
            .replacingOccurrences(of: " with ", with: ",")
            .replacingOccurrences(of: " + ", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 1 }
    }

    private var tokenRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("I’ll look up").sectionLabelStyle()
            FlexWrap(spacing: 8, lineSpacing: 8) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                    let last =
                        index == tokens.count - 1 && !logger.text.hasSuffix(" ")
                        && !logger.text.hasSuffix(",")
                    Text(last ? "\(token)…" : token)
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(last ? Color(hex: 0xD4D4D8) : Palette.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Capsule().fill(last ? .clear : Palette.ember.opacity(0.12)))
                        .overlay(
                            Capsule().strokeBorder(
                                last
                                    ? Palette.amber.opacity(0.5)
                                    : Color(hex: 0xFF8A50, opacity: 0.45),
                                style: StrokeStyle(lineWidth: 1, dash: last ? [4, 3] : [])))
                }
            }
            Text("Rough is fine — I’ll tidy it up.")
                .font(Typography.data(12, weight: .regular))
                .foregroundStyle(Palette.inkFaint)
                .hintCopy()
        }
        .transition(.opacity)
    }

    /// Compact only while the on-screen keyboard is actually up and the field has
    /// it — not just because there's text left over or a hardware keyboard is in use.
    private var typing: Bool {
        keyboardUp && focused.wrappedValue
    }

    private var title: String {
        if let backdate = logger.backdate { return L10n( "What was \(backdate.slot.title.lowercased())?") }
        return L10n( "What did you eat?")
    }

    private var slot: MealSlot { logger.backdate?.slot ?? currentSlot }

    private func backdateChip(_ backdate: LogMealViewModel.Backdate) -> some View {
        HStack(spacing: 6) {
            Text(
                L10n("Adding to \(backdate.slot.title.lowercased()) · \(backdate.at.formatted(date: .omitted, time: .shortened))")
            )
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
            if !showsLiveCamera {
                Menu {
                    PhotoSourceButtons(model: logger)
                } label: {
                    tileLabel("Photo", "camera")
                }
                .disabled(logger.phase == .parsing)
            }
            tile("Barcode", "barcode.viewfinder") {
                focused.wrappedValue = false
                logger.mode = .scan
                logger.openScanner()
            }
            if let onOrder {
                tile("Order", "bag", lit: true) {
                    focused.wrappedValue = false
                    onOrder()
                }
            }
        }
    }

    private func tile(
        _ title: String, _ symbol: String, lit: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            tileLabel(title, symbol, lit: lit)
        }
        .buttonStyle(PressableCard())
        .disabled(logger.phase == .parsing)
    }

    private func tileLabel(_ title: String, _ symbol: String, lit: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(lit ? Palette.hazeSoft : Palette.ink)
            Text(LocalizedStringKey(title))
                .font(Typography.data(14, weight: .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 12)
        .frame(height: 48)
        .glass(
            radius: 16, fill: lit ? Palette.haze.opacity(0.10) : Palette.glass,
            stroke: lit ? Palette.haze.opacity(0.5) : Palette.hairline)
    }

    /// The two most recently used saved plates — full list is on You.
    @ViewBuilder
    private var usuals: some View {
        let saved = SavedMealShortcuts.logSheet(from: logger.savedMeals)
        if !saved.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Your usuals").sectionLabelStyle()
                    Spacer()
                }
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8),
                    ], spacing: 8
                ) {
                    ForEach(saved) { meal in
                        usual(meal.name, kcal: meal.kcal, suggested: meal.suggested) {
                            focused.wrappedValue = false
                            Task { await logger.logSaved(meal) }
                        }
                    }
                }
            }
        }
    }

    /// Recent meals, one per name, newest first — tap one to log it again.
    /// A saved plate already on a tile above isn't listed twice.
    @ViewBuilder
    private var recentList: some View {
        let savedNames = Set(SavedMealShortcuts.logSheet(from: logger.savedMeals).map { $0.name.lowercased() })
        let meals = logger.recents.filter { !savedNames.contains(($0.summary ?? "").lowercased()) }
        if !meals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent").sectionLabelStyle()
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(meals) { meal in
                            RecentMealCard(meal: meal) {
                                focused.wrappedValue = false
                                Task { await logger.logAgain(meal) }
                            }
                            .disabled(logger.phase == .parsing)
                        }
                    }
                }
                .contentMargins(.horizontal, Space.gutter, for: .scrollContent)
                .padding(.horizontal, -Space.gutter)
            }
        }
    }

    private func usual(_ name: String, kcal: Int, suggested: Bool, action: @escaping () -> Void)
        -> some View
    {
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
                            } else if meal.isCatalog {
                                Image(systemName: "leaf")
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
                    .accessibilityLabel(
                        "Log \(meal.summary ?? "this") again, \(meal.kcal) calories")
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
            // The one lit button on the panel: everything else is glass.
            Button {
                focused.wrappedValue = false
                Task { await logger.logEstimate(slot: slot, kcal: kcal) }
            } label: {
                HStack(spacing: 10) {
                    Text(L10n("Log a \(L10nKey(sizes[size].0)) \(slot.title)"))
                        .font(Typography.data(15, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(L10n("~\(kcal.formatted()) kcal"))
                        .font(Typography.mono(13))
                        .contentTransition(.numericText(value: Double(kcal)))
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.black.opacity(0.14)))
                }
                .foregroundStyle(Color(hex: 0x1A0A04))
                .padding(.leading, 20)
                .padding(.trailing, 10)
                .frame(height: 52)
                .background {
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFFC48A), Palette.ember], startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                }
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                .shadow(color: Palette.ember.opacity(0.45), radius: 14, y: 4)
                .contentShape(Capsule())
            }
            .buttonStyle(PressableCard())
            .disabled(logger.phase == .parsing)
            .opacity(logger.phase == .parsing ? 0.6 : 1)
            .accessibilityLabel(
                "Log a \(sizes[size].0.lowercased()) \(slot.title.lowercased()), about \(kcal) kilocalories"
            )
        }
        .padding(14)
        .glass(radius: 20, fill: Color.white.opacity(0.03))
    }
}

/// One recent meal as a card in the sideways list: what it was, when, and its
/// calories, with a + to log it again.
private struct RecentMealCard: View {
    let meal: MealSummary
    let action: () -> Void

    @State private var thumb: UIImage?

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    icon
                    Spacer(minLength: 8)
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(meal.summary ?? "")
                        .font(Typography.data(14, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    Text(when)
                        .font(Typography.mono(11))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                }
                Text(L10n("\(meal.kcal.formatted()) kcal"))
                    .font(Typography.mono(12))
                    .foregroundStyle(Palette.amber)
            }
            .padding(12)
            .frame(width: 156, alignment: .leading)
            .glass(radius: 18)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableCard())
        .task(id: meal.id) {
            if meal.photoUrl != nil { thumb = await MealPhotoCache.shared.image(for: meal) }
        }
        .accessibilityLabel("Log \(meal.summary ?? "this") again, \(meal.kcal) calories")
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.05))
            if let thumb {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var symbol: String {
        switch meal.source {
        case "PHOTO": return "camera"
        case "BARCODE": return "barcode"
        case "CATALOG": return "leaf"
        case "SAVED": return "star"
        default: return "text.alignleft"
        }
    }

    /// "Today · 8:05", "Yesterday · 13:10", or "Mon 19 Oct".
    private var when: String {
        guard let date = MealFormat.parse(meal.loggedAt) else { return "" }
        let locale = AppLanguage.current.locale
        let calendar = Calendar.current
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
        if calendar.isDateInToday(date) { return L10n("Today · \(time)") }
        if calendar.isDateInYesterday(date) { return L10n("Yesterday · \(time)") }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
    }
}

/// What the logger is doing, floating above the nav once the panel has closed:
/// working it out, saved offline, couldn't read it, or logged.
struct LogStatusToast: View {
    @Bindable var logger: LogMealViewModel
    var onRetry: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        Group {
            switch logger.phase {
            case .parsing where logger.pendingKnownMeal == nil:
                working
            case let .queued(message):
                card(stroke: Palette.hazeSoft.opacity(0.30)) {
                    HStack(spacing: 12) {
                        Image(systemName: "icloud.slash")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Palette.hazeSoft)
                            .frame(width: 38, height: 38)
                            .background(Palette.haze.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No signal. Saved here.")
                                .font(Typography.data(14, weight: .regular))
                                .foregroundStyle(Palette.ink)
                            Text(message)
                                .font(Typography.data(12, weight: .regular))
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            case let .failed(message):
                card(stroke: Palette.danger.opacity(0.35)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Circle().fill(Palette.danger).frame(width: 8, height: 8).shadow(
                                color: Palette.danger, radius: 4)
                            (Text(
                                logger.submittedPrompt.isEmpty
                                    ? "" : "“\(logger.submittedPrompt)”? "
                            ).foregroundColor(Palette.ink)
                                + Text("Didn’t catch that.").foregroundColor(Palette.inkFaint))
                                .font(Typography.data(14, weight: .regular))
                                .lineLimit(2)
                        }
                        Text(message)
                            .font(Typography.data(12, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                        if onRetry != nil || onDelete != nil {
                            HStack(spacing: 8) {
                                if let onRetry {
                                    BonePill(title: "Say it again", action: onRetry)
                                }
                                if let onDelete {
                                    BonePill(title: "Delete", action: onDelete)
                                }
                            }
                        }
                    }
                }
            case let .logged(logged) where !logger.confirmingPhoto:
                line(
                    symbol: "checkmark",
                    text: "Logged · \(logged.kcal) kcal"
                        + (logged.resolvedCheckIn ? " · check-in answered" : "")
                )
            default:
                EmptyView()
            }
        }
    }

    private var tokens: [String] {
        logger.submittedPrompt
            .replacingOccurrences(of: " and ", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 1 }
    }

    private var working: some View {
        card(stroke: Palette.amber.opacity(0.25)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    SpinningOrb()
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Working it out")
                            .font(Typography.data(14, weight: .regular))
                            .foregroundStyle(Palette.ink)
                        if !logger.submittedPrompt.isEmpty {
                            Text("“\(logger.submittedPrompt)”")
                                .font(Typography.data(12, weight: .regular))
                                .foregroundStyle(Palette.inkFaint)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if tokens.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(Array(tokens.prefix(4).enumerated()), id: \.offset) { _, token in
                            Text(token)
                                .font(Typography.data(12, weight: .regular))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10)))
                                .shimmering()
                        }
                    }
                }
            }
        }
    }

    private func card<Content: View>(stroke: Color, @ViewBuilder content: () -> Content)
        -> some View
    {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous).fill(
                            Color(hex: 0x141417, opacity: 0.9))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(stroke)
                    )
                    .shadow(color: .black.opacity(0.55), radius: 20, y: 14)
            }
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
    }

    private func line(symbol: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.amber)
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

/// A lit ball inside a turning dashed ring — something is being worked out.
struct SpinningOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .strokeBorder(
                        Palette.amber.opacity(0.8),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                    )
                    .rotationEffect(
                        .degrees(
                            reduceMotion ? 0 : t.truncatingRemainder(dividingBy: 2.4) / 2.4 * 360))
                EmberDot(size: 16)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}
