import SwiftUI

// Today (§5.2), rebuilt around one question: am I on pace today, and what do I
// do next? These are its blocks, top to bottom; HomeContent composes them.

// MARK: - Header

/// The date, then the manager speaking. The note is the screen's headline.
struct TodayHeader: View {
    let date: Date
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(Typography.data(13, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
            Text(note)
                .font(Typography.voice(24))
                .foregroundStyle(Palette.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Day panel

/// What's left, protein, and the shape of the day so far. The accent appears
/// only while there's still food to eat (§5.2) — never in quiet mode, never for
/// going over.
struct DayPanel: View {
    let home: HomeResponse

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownHero = 0
    @State private var settledIn = false

    private var ledger: HomeResponse.Ledger { home.ledger }
    private var hero: Int { home.framing.heroKcal }
    private var urgent: Bool { home.enforcementEnabled && home.framing.state == "under" }
    private var behind: Bool { home.day?.pace?.status == "behind" }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .top, spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(abs(shownHero).formatted())
                            .font(Typography.data(44, weight: .semibold))
                            .foregroundStyle(urgent ? Palette.accent : Palette.ink)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(shownHero)))
                        Text(TodayCopy.heroCaption(home.framing))
                            .font(Typography.data(14, weight: .medium))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    Text("\(ledger.consumedKcal.formatted()) of \(ledger.targetKcal.formatted()) kcal eaten")
                        .font(Typography.data(12, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .monospacedDigit()
                }
                Spacer(minLength: Space.xs)
                if let target = ledger.targetProteinG, target > 0 {
                    ProteinGauge(consumed: ledger.consumedProteinG, target: target, animate: settledIn)
                }
            }

            if let day = home.day {
                DayTrack(
                    day: day,
                    meals: home.meals,
                    mealTimes: home.resolvedMealTimes,
                    urgent: urgent,
                    showsMissed: home.enforcementEnabled
                )
            } else {
                IntakeBar(
                    consumed: ledger.consumedKcal,
                    target: ledger.targetKcal,
                    state: home.framing.state,
                    urgent: urgent
                )
            }

            if let line = TodayCopy.paceLine(home) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(behind ? Palette.accent : Palette.dayOnTrack)
                        .frame(width: 7, height: 7)
                    Text(line)
                        .font(Typography.data(13, weight: .medium))
                        .foregroundStyle(behind ? Palette.accentDeep : Palette.inkSoft)
                        .contentTransition(.opacity)
                }
                .opacity(settledIn ? 1 : 0)
                .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion).delay(0.28), value: settledIn)
                .transition(.opacity)
            }
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Palette.surfaceRaised)
                .elevation(.floating)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(Palette.hairline)
                )
        }
        .task(id: home.ledger.consumedKcal) { rollNumbers() }
    }

    /// Count the hero number up to its value on first paint, and roll it when a
    /// meal changes the ledger. `.numericText` does the visual roll.
    private func rollNumbers() {
        guard !reduceMotion else {
            shownHero = hero
            settledIn = true
            return
        }
        if !settledIn {
            withAnimation(Motion.enter.delay(0.15)) {
                shownHero = hero
                settledIn = true
            }
        } else {
            withAnimation(Motion.settle) { shownHero = hero }
        }
    }
}

/// Protein as a first-class number beside the kcal, not a footnote. The bar
/// grows to its fraction once the panel settles in.
struct ProteinGauge: View {
    let consumed: Double
    let target: Double
    var animate: Bool

    private var fraction: Double { min(1, max(0, consumed / target)) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text("Protein").sectionLabelStyle()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(consumed.rounded()))")
                    .font(Typography.data(20, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: consumed))
                Text("/ \(Int(target.rounded())) g")
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkFaint)
            }
            Capsule()
                .fill(Palette.surfaceSunk)
                .frame(width: 84, height: 5)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Palette.inkSoft)
                        .frame(width: max(fraction > 0 ? 5 : 0, 84 * (animate ? fraction : 0)), height: 5)
                }
                .animation(Motion.settle.delay(0.2), value: animate)
                .animation(Motion.settle, value: fraction)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Protein, \(Int(consumed.rounded())) of \(Int(target.rounded())) grams")
    }
}

/// Fallback when the backend doesn't send the day's shape: a plain intake bar.
private struct IntakeBar: View {
    let consumed: Int
    let target: Int
    let state: String
    let urgent: Bool

    private var fraction: Double {
        target > 0 ? min(1, max(0, Double(consumed) / Double(target))) : 0
    }

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Palette.surfaceSunk)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(urgent ? Palette.accent : state == "over" ? Palette.dayOver : Palette.dayOnTrack)
                        .frame(width: max(fraction > 0 ? 6 : 0, geo.size.width * fraction))
                }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// The day as a line — rhythm is what the manager watches (§2). Usual meal
/// times are ticks, logged meals are dots sized by how much they were, time
/// already gone is shaded, and a marker shows now. On appear the elapsed
/// portion and the now marker sweep out from the left; the meal dots drop in
/// after (§5a — staggered, spring, nothing under Reduce Motion).
struct DayTrack: View {
    let day: HomeResponse.Day
    let meals: [MealSummary]
    let mealTimes: MealTimesPayload
    let urgent: Bool
    /// Quiet mode never marks a meal time as missed.
    let showsMissed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swept = false

    private static let railY: CGFloat = 12
    private static let labelWidth: CGFloat = 72

    static func dotSize(_ kcal: Int) -> CGFloat {
        min(16, max(8, 7 + CGFloat(kcal) / 110))
    }

    var body: some View {
        let layout = DayTrackLayout(mealTimes: mealTimes, nowMin: day.nowMin)
        GeometryReader { geo in
            let width = geo.size.width
            let nowX = width * layout.fraction(day.nowMin)
            let sweep: CGFloat = swept ? 1 : 0
            let railY = Self.railY

            Capsule()
                .fill(Palette.surfaceSunk)
                .frame(width: width, height: 6)
                .position(x: width / 2, y: railY)

            Capsule()
                .fill(Palette.inkFaint.opacity(0.3))
                .frame(width: max(6, nowX) * sweep, height: 6)
                .position(x: max(6, nowX) * sweep / 2, y: railY)

            ForEach(day.slots) { slot in
                let x = width * layout.fraction(slot.atMin)
                let state = shownState(slot)
                SlotTick(state: state, urgent: urgent)
                    .position(x: x, y: railY)
                Text(slot.meal.title)
                    .font(Typography.data(10, weight: state == .now ? .bold : .semibold))
                    .foregroundStyle(labelColor(state))
                    .lineLimit(1)
                    .frame(width: Self.labelWidth)
                    .position(x: min(max(x, Self.labelWidth / 2), width - Self.labelWidth / 2), y: railY + 22)
            }

            ForEach(Array(datedMeals.enumerated()), id: \.element.0.id) { index, entry in
                let (meal, minute) = entry
                let size = Self.dotSize(meal.kcal)
                Circle()
                    .fill(Palette.ink)
                    .overlay(Circle().strokeBorder(Palette.surfaceRaised, lineWidth: 2))
                    .frame(width: size, height: size)
                    .scaleEffect(swept ? 1 : 0.1)
                    .opacity(swept ? 1 : 0)
                    .position(x: width * layout.fraction(minute), y: railY)
                    .animation(
                        Motion.adaptive(Motion.nudge, reduceMotion: reduceMotion)
                            .delay(Motion.stagger(index, step: 0.06, reduceMotion: reduceMotion) + 0.18),
                        value: swept
                    )
            }

            Capsule()
                .fill(urgent ? Palette.accent : Palette.inkSoft)
                .frame(width: 3, height: 20)
                .opacity(sweep)
                .position(x: min(max(nowX * sweep, 1.5), width - 1.5), y: railY)
        }
        .frame(height: 44)
        .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion), value: swept)
        .onAppear { swept = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// Logged meals that have a time, kept in a stable order for the stagger.
    private var datedMeals: [(MealSummary, Int)] {
        meals.compactMap { meal in
            TodayLayout.minuteOfDay(meal.loggedAt).map { (meal, $0) }
        }
    }

    private func shownState(_ slot: HomeResponse.Day.Slot) -> SlotState {
        slot.slotState == .missed && !showsMissed ? .upcoming : slot.slotState
    }

    private func labelColor(_ state: SlotState) -> Color {
        switch state {
        case .now: return urgent ? Palette.accentDeep : Palette.ink
        case .logged: return Palette.inkSoft
        case .missed, .upcoming: return Palette.inkFaint
        }
    }

    private var accessibilitySummary: String {
        day.slots
            .map { slot -> String in
                switch slot.slotState {
                case .logged: return "\(slot.meal.title) logged"
                case .now: return "\(slot.meal.title) due now"
                case .missed: return "\(slot.meal.title), no meal logged"
                case .upcoming: return "\(slot.meal.title) later"
                }
            }
            .joined(separator: ", ")
    }
}

private struct SlotTick: View {
    let state: SlotState
    let urgent: Bool

    var body: some View {
        switch state {
        case .logged:
            // The meal dots mark it; a ring here would collide with them.
            EmptyView()
        case .now:
            Circle()
                .fill(Palette.surfaceRaised)
                .overlay(Circle().strokeBorder(urgent ? Palette.accent : Palette.ink, lineWidth: 2.5))
                .frame(width: 14, height: 14)
        case .missed:
            Circle()
                .fill(Palette.surfaceRaised)
                .overlay(Circle().strokeBorder(Palette.inkFaint, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2])))
                .frame(width: 12, height: 12)
        case .upcoming:
            Circle()
                .fill(Palette.surfaceSunk)
                .overlay(Circle().strokeBorder(Palette.inkFaint.opacity(0.55), lineWidth: 1.5))
                .frame(width: 12, height: 12)
        }
    }
}

// MARK: - Next card

/// The one thing to do next. A check-in always owns it, with its answers right
/// on the card; otherwise it points at the next meal time or says the day is
/// covered. Quiet mode doesn't show it at all (the caller skips it).
struct NextCard: View {
    let home: HomeResponse
    /// False while the check-in has morphed into the full-screen view, so only
    /// one view holds the matched geometry.
    let showsCheckIn: Bool
    let namespace: Namespace.ID
    let geometryID: String
    let busy: Bool
    var error: String?
    let onOpenCheckIn: () -> Void
    let onAteThis: () -> Void
    let onSomethingElse: () -> Void
    let onSnooze: () -> Void
    let onLog: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let next = TodayNext.resolve(home)
        VStack(alignment: .leading, spacing: Space.xs) {
            content(next)
                .id(next.caseKey)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 6)),
                    removal: .opacity
                ))
            if let error {
                Text(error)
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.accentDeep)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }
        }
        .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion), value: next.caseKey)
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: error)
    }

    @ViewBuilder
    private func content(_ next: TodayNext) -> some View {
        switch next {
        case .checkIn, .snoozed, .conversation:
            if let checkIn = home.activeCheckIn {
                checkInCard(checkIn, next: next)
            }
        case let .meal(slot, atMin, kcal):
            promptCard(
                symbol: slot.symbol,
                eyebrow: "Next",
                line: "\(slot.title) around \(formatMinutes(atMin))",
                detail: "About \(kcal.formatted()) kcal"
            )
        case let .toGo(kcal):
            promptCard(
                symbol: "fork.knife",
                eyebrow: "Still to go",
                line: "About \(kcal.formatted()) kcal left today",
                detail: "A snack or a late meal covers it."
            )
        case .covered:
            coveredCard
        case .quiet:
            EmptyView()
        }
    }

    private func checkInCard(_ checkIn: HomeResponse.ActiveCheckIn, next: TodayNext) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if next == .snoozed {
                Label(snoozedLabel(checkIn.deferUntil), systemImage: "clock")
                    .font(Typography.data(12, weight: .semibold))
                    .foregroundStyle(Palette.accentDeep)
                    .padding(.horizontal, 4)
            }

            Button(action: onOpenCheckIn) {
                if showsCheckIn {
                    CheckInContent(checkIn: checkIn, restingElevation: .floating)
                        .matchedGeometryEffect(id: geometryID, in: namespace)
                } else {
                    CheckInContent(checkIn: checkIn, restingElevation: .floating)
                        .opacity(0)
                }
            }
            .buttonStyle(PressableCard())

            HStack(spacing: Space.xs) {
                if next == .conversation {
                    TodayPill("Talk it through", style: .primary, action: onOpenCheckIn)
                } else {
                    if checkIn.prescription != nil {
                        TodayPill(busy ? "Logging…" : "I ate this", style: .primary, action: onAteThis)
                    }
                    TodayPill("Something else", action: onSomethingElse)
                }
                Spacer(minLength: 0)
                if next == .checkIn {
                    Button(action: onSnooze) {
                        Image(systemName: "zzz")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                            .frame(width: 40, height: 40)
                            .background(Palette.surface, in: Circle())
                            .overlay(Circle().strokeBorder(Palette.hairline))
                    }
                    .buttonStyle(PressableCard())
                    .accessibilityLabel("Snooze")
                }
            }
            .disabled(busy)
            .opacity(showsCheckIn ? 1 : 0)
        }
    }

    private func promptCard(symbol: String, eyebrow: String, line: String, detail: String) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 40, height: 40)
                .background(Palette.accentTint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow).sectionLabelStyle()
                Text(line)
                    .font(Typography.voice(18))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: Space.xs)
            TodayPill("Log it", style: .primary, action: onLog)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
                .elevation(.resting)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(Palette.hairline)
                )
        }
    }

    private var coveredCard: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.inkSoft)
                .frame(width: 36, height: 36)
                .background(Palette.surface, in: Circle())
            Text(home.framing.state == "over" ? "That's the day covered. Nothing to fix." : "That's the day covered.")
                .font(Typography.voice(17))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceSunk.opacity(0.7), in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func snoozedLabel(_ iso: String?) -> String {
        guard let iso, let date = MealFormat.parse(iso) else { return "Snoozed" }
        return "Snoozed until \(date.formatted(date: .omitted, time: .shortened))"
    }
}

/// A compact action capsule for cards on Today.
struct TodayPill: View {
    enum Style { case primary, secondary }

    let title: String
    let style: Style
    let action: () -> Void

    init(_ title: String, style: Style = .secondary, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.data(14, weight: .semibold))
                .foregroundStyle(style == .primary ? Color.white : Palette.ink)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(style == .primary ? Palette.accent : Palette.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(style == .primary ? Color.clear : Palette.hairline))
        }
        .buttonStyle(PressableCard())
    }
}

// MARK: - Meal log

/// Today's meals under their usual meal times. Only times that have food — or
/// that passed with nothing logged — get a section; upcoming ones live on the
/// day track. Quiet mode never points at a missed meal.
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
            let pendingSlotID = pending == nil ? nil : pendingSlot(in: day)
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

    /// Where a meal being logged right now shows up: the slot that's due, else
    /// the latest one with food.
    private func pendingSlot(in day: HomeResponse.Day) -> String? {
        day.slots.first { $0.slotState == .now }?.id
            ?? day.slots.last { $0.slotState == .logged }?.id
            ?? day.slots.last?.id
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
                        .font(Typography.data(11, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .monospacedDigit()
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
        Text("Meals you log land here, under their meal time.")
            .font(Typography.data(13))
            .foregroundStyle(Palette.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func pendingRow(_ pending: TodayPending) -> some View {
        switch pending {
        case let .parsing(title):
            TodayMealRow(title: title, detail: "Working it out…", kcal: 640, redacted: true)
                .shimmering(true)
        case let .logged(title, kcal):
            landing(TodayMealRow(title: title, detail: "Just now", kcal: kcal))
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
                .font(Typography.voice(16))
                .foregroundStyle(Palette.inkSoft)
            Spacer(minLength: Space.xs)
            Button {
                onLogMissed(slot)
            } label: {
                Label("Add \(slot.meal.title.lowercased())", systemImage: "plus")
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.accentDeep)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Palette.accentTint, in: Capsule())
            }
            .buttonStyle(PressableCard())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.inkFaint.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
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
        HStack(spacing: Space.sm) {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .transition(.opacity)
            }
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.hairline)
        )
        .elevation(.resting)
        .redacted(reason: redacted ? .placeholder : [])
        .task(id: meal?.photoUrl) {
            guard let meal else { return }
            photo = await MealPhotoCache.shared.image(for: meal)
        }
    }
}

// MARK: - Log dock

/// Logging, always in the same place: pinned above the tab bar and rising with
/// the keyboard. It shows what's being worked out and, when filling in a
/// missed meal time, which one.
struct LogDock: View {
    @Bindable var logger: LogMealViewModel
    var focused: FocusState<Bool>.Binding
    let photoNamespace: Namespace.ID
    let photoGeometryID: String
    let onSubmit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            status

            SearchComposer(
                model: logger,
                focused: focused,
                onSubmit: onSubmit,
                photoNamespace: photoNamespace,
                photoGeometryID: photoGeometryID,
                prompt: prompt
            )
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Palette.background.opacity(0.84))
                .overlay(alignment: .top) {
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: logger.phase)
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: logger.backdate)
    }

    private var prompt: String {
        if let backdate = logger.backdate {
            return "What was \(backdate.slot.title.lowercased())?"
        }
        return "What did you eat?"
    }

    @ViewBuilder
    private var status: some View {
        switch logger.phase {
        case .parsing:
            statusLine(
                symbol: nil,
                text: logger.submittedPrompt.isEmpty ? "Working it out…" : "Working out “\(logger.submittedPrompt)”…",
                working: true
            )
        case let .logged(logged) where !logger.confirmingPhoto:
            statusLine(
                symbol: "checkmark",
                text: "Logged · \(logged.kcal) kcal" + (logged.resolvedCheckIn ? " · check-in answered" : ""),
                working: false
            )
        default:
            if let backdate = logger.backdate {
                HStack(spacing: 6) {
                    Image(systemName: backdate.slot.symbol)
                    Text("Adding to \(backdate.slot.title.lowercased()) · \(backdate.at.formatted(date: .omitted, time: .shortened))")
                    Button {
                        logger.backdate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.accentDeep.opacity(0.6))
                    }
                    .accessibilityLabel("Log it for now instead")
                }
                .font(Typography.data(12, weight: .semibold))
                .foregroundStyle(Palette.accentDeep)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Palette.accentTint, in: Capsule())
                .transition(.opacity)
            }
        }
    }

    private func statusLine(symbol: String?, text: String, working: Bool) -> some View {
        HStack(spacing: 8) {
            if working {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Palette.accent)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.dayOnTrack)
            }
            Text(text)
                .font(Typography.data(13, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .transition(.opacity)
    }
}
