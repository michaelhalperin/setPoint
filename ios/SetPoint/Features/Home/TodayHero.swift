import SwiftUI

// The top of Today, one screen: the date with today's appetite, the fuel orb, a
// pace pill that opens the day's meals, one card for what's next (pick a usual
// and tap when it's eaten), and the day's plates as a strip of dots. When a
// check-in fires, the top of Today becomes the check-in.

// MARK: - Orb hero

struct TodayHero: View {
    let home: HomeResponse
    let moment: TodayMoment
    let date: Date
    /// Saved meals that fit the next slot — the "Pick one" rows.
    var picks: [SavedMeal] = []
    /// The pick being logged right now, if any.
    var loggingPickID: String? = nil
    /// Reload after an appetite answer.
    var onAppetiteChanged: () async -> Void = {}
    var onOpenDay: () -> Void = {}
    var onPick: (SavedMeal) -> Void = { _ in }
    var onLog: () -> Void = {}
    var onOpenCheckIn: () -> Void = {}
    /// Order nearby — no food at hand. Nil hides the pill.
    var onOrder: (() -> Void)? = nil
    /// Nutrition assistant. Nil hides the row.
    var onAskNutrition: (() -> Void)? = nil

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appetiteOpen = false
    @State private var appetiteOptimistic: String?
    @State private var appetiteBusy = false

    private var appetiteLevel: String {
        appetiteOptimistic ?? home.appetite?.level ?? "NORMAL"
    }

    var body: some View {
        VStack(spacing: Space.sm) {
            header
            FuelOrbDial(progress: progress, dimmed: moment == .quiet) {
                VStack(spacing: 2) {
                    Text(home.ledger.consumedKcal.formatted())
                        .font(Typography.hero)
                        .tracking(-1.8)
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: Double(home.ledger.consumedKcal)))
                    Text(orbCaption)
                        .font(Typography.mono(12))
                        .foregroundStyle(overTarget ? Palette.ink : Color(hex: 0xFDE6CF))
                        .contentTransition(.opacity)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(orbAccessibility)
            }
            .padding(.top, Space.xs)
            .tourAnchor("today.orb")

            Button(action: onOpenDay) {
                StatusPill(dot: statusDot, text: statusText) {
                    Text("·").foregroundStyle(Palette.inkFaint)
                    Text(mealsLine)
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .buttonStyle(PressableCard())
            .tourAnchor("today.pace")
            .accessibilityHint("Shows today’s meals")

            nutritionEntry

                Group {
                    if AppetiteTodayVisibility.resolve(home: home) == .ask {
                        AppetiteTodayLine(home: home, onChanged: {
                            appetiteBusy = true
                            await onAppetiteChanged()
                            appetiteBusy = false
                        })
                    } else {
                        momentCard
                            .tourAnchor("today.next")
                    }
                }
                .appearIn(1, rise: 16)

            PlateStrip(home: home, loading: appetiteBusy)
                .padding(.top, Space.sm)
                .tourAnchor("today.dots")
        }
        // Overlay keeps the menu floating — it must not grow the hero layout.
        .overlay(alignment: .topTrailing) {
            if appetiteOpen {
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture { appetiteOpen = false }
                    AppetiteDropdown(level: appetiteLevel) { level in
                        appetiteOpen = false
                        pickAppetite(level)
                    }
                    .padding(.top, 44)
                    .shadow(color: .black.opacity(0.55), radius: 24, y: 10)
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: appetiteOpen)
        .onChange(of: home.appetite?.level) { _, synced in
            if synced == appetiteOptimistic { appetiteOptimistic = nil }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.wide).locale(AppLanguage.current.locale)))
                    .font(Typography.data(20, weight: .regular))
                    .tracking(-0.4)
                    .foregroundStyle(Palette.ink)
                Text(subline)
                    .font(Typography.mono(11))
                    .tracking(1.3)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 8)
            if home.enforcementEnabled, home.appetite != nil {
                AppetiteChip(level: appetiteLevel, open: appetiteOpen) {
                    appetiteOpen.toggle()
                }
            }
        }
        .zIndex(1)
    }

    private func pickAppetite(_ value: String) {
        guard value != appetiteLevel else { return }
        Haptics.select()
        appetiteOptimistic = value
        appetiteBusy = true
        Task {
            struct Body: Encodable { let level: String }
            defer { appetiteBusy = false }
            do {
                try await env.api.put("/api/appetite/today", Body(level: value))
                await onAppetiteChanged()
            } catch {
                appetiteOptimistic = nil
            }
        }
    }

    private var subline: String {
        let day = date.formatted(.dateTime.day().month(.abbreviated).locale(AppLanguage.current.locale))
        if moment == .quiet { return L10n( "\(day) · quiet mode") }
        if let training = home.training, !training.workouts.isEmpty { return L10n( "\(day) · training day") }
        return day
    }

    // MARK: Status

    private var progress: Double {
        Double(home.ledger.consumedKcal) / Double(max(home.ledger.targetKcal, 1))
    }

    private var overTarget: Bool { home.ledger.consumedKcal > home.ledger.targetKcal }

    private var overBy: Int { home.ledger.consumedKcal - home.ledger.targetKcal }

    private var orbCaption: String {
        overTarget
            ? L10n("+\(overBy.formatted()) over")
            : L10n("of \(home.ledger.targetKcal.formatted()) kcal")
    }

    private var orbAccessibility: String {
        if overTarget {
            return L10n( "\(home.ledger.consumedKcal) of \(home.ledger.targetKcal) kilocalories, \(overBy) over")
        }
        return L10n( "\(home.ledger.consumedKcal) of \(home.ledger.targetKcal) kilocalories")
    }

    private var behind: Bool { home.day?.pace?.status == "behind" }

    private var statusText: String {
        switch moment {
        case .quiet: return L10n( "Quiet mode")
        case .covered: return L10n( "Day closed")
        case .checkIn, .conversation: return L10n( "Checking in")
        case .snoozed: return L10n( "Snoozed")
        default: return behind ? L10n( "A bit behind") : L10n( "On pace")
        }
    }

    private var statusDot: Color {
        switch moment {
        case .quiet: return Palette.inkSoft
        case .covered: return Palette.amber
        case .checkIn, .conversation, .snoozed: return Palette.ember
        default: return behind ? Palette.ember : Palette.positive
        }
    }

    private var mealsLine: String {
        switch home.ledger.mealsToday {
        case 0: return L10n( "nothing yet")
        case 1: return L10n( "1 meal")
        case let n: return L10n( "\(n) meals")
        }
    }

    // MARK: Moment card

    private var momentCard: some View {
        GlassCard(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(momentLabel).sectionLabelStyle()
                Spacer(minLength: 8)
                if let kcal = nextKcal {
                    Text("~\(kcal.formatted()) kcal")
                        .font(Typography.mono(12))
                        .foregroundStyle(Palette.amber)
                }
            }
            momentBody
            if home.needsWeighIn == true {
                HStack(spacing: 6) {
                    Image(systemName: "scalemass")
                        .font(.system(size: 12, weight: .medium))
                    Text("A weigh-in is due — it’s on Progress.")
                        .font(Typography.data(13, weight: .regular))
                }
                .foregroundStyle(Palette.amber)
                .padding(.top, 2)
            }
        }
    }

    /// Under the ledger. Hidden when the flag is off (`onAskNutrition` is nil).
    @ViewBuilder
    private var nutritionEntry: some View {
        if let onAskNutrition {
            Button(action: onAskNutrition) {
                HStack(spacing: 10) {
                    FuelOrb(size: 16, breathing: false, glow: 0.35)
                    Text(L10n("Nutrition assistant"))
                        .font(Typography.data(14, weight: .regular))
                        .foregroundStyle(Palette.ink)
                    Text(L10n("AI"))
                        .font(Typography.mono(10, weight: .medium))
                        .foregroundStyle(Palette.amber)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .glassCapsule(fill: Palette.ember.opacity(0.12), stroke: Palette.ember.opacity(0.38))
            }
            .buttonStyle(PressableCard())
            .accessibilityLabel(L10n("Nutrition assistant · AI"))
        }
    }

    @ViewBuilder
    private var momentBody: some View {
        switch moment {
        case let .watching(_, _, _, light) where !light && !picks.isEmpty:
            Headline("Pick one.", tail: "Tap when it’s eaten.", size: 24)
            VStack(spacing: 8) {
                ForEach(Array(picks.enumerated()), id: \.element.id) { index, meal in
                    pickRow(meal, primary: index == 0)
                }
                orLinks("Something else")
            }
        case .watching:
            Headline(TodayCopy.headline(moment), tail: tail, size: 24, persistTail: true)
                .contentTransition(.opacity)
            orLinks("Log it")
        case .snoozed:
            Headline(TodayCopy.headline(moment), tail: "Eat sooner and I’ll stay quiet.", size: 26)
            HStack(spacing: 10) {
                if home.activeCheckIn != nil {
                    ActionButton(title: "Open it now", action: onOpenCheckIn)
                }
                ActionButton(title: "I ate", kind: .secondary, action: onLog)
            }
        default:
            Headline(TodayCopy.headline(moment), tail: tail, size: 26, persistTail: true)
                .contentTransition(.opacity)
            ActionButton(title: "Log something extra", kind: .secondary, action: onLog)
                .padding(.top, 4)
        }
    }

    private func pickRow(_ meal: SavedMeal, primary: Bool) -> some View {
        let logging = loggingPickID == meal.id
        return Button { onPick(meal) } label: {
            HStack(spacing: 12) {
                (Text(meal.name)
                    + Text(isUsual(meal) ? "  · your usual" : "")
                        .font(Typography.data(12, weight: .regular))
                        .foregroundColor(Palette.inkFaint))
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(meal.kcal.formatted())
                    .font(Typography.mono(12))
                    .foregroundStyle(Palette.inkSoft)
                ZStack {
                    Circle().fill(primary ? Palette.ink : Color.white.opacity(0.10))
                    if logging {
                        ProgressView()
                            .controlSize(.small)
                            .tint(primary ? Palette.onBone : Palette.ink)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(primary ? Palette.onBone : Palette.ink)
                    }
                }
                .frame(width: 34, height: 34)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCard())
        .disabled(loggingPickID != nil)
        .accessibilityLabel("Log \(meal.name), \(meal.kcal) kilocalories")
    }

    /// "Order nearby" beside the plain log link, when ordering is on offer.
    @ViewBuilder
    private func orLinks(_ title: String) -> some View {
        if let onOrder {
            HStack(spacing: 8) {
                Button(action: onOrder) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Order nearby")
                            .font(Typography.data(14, weight: .regular))
                    }
                    .foregroundStyle(Palette.hazeSoft)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .glassCapsule(fill: Palette.haze.opacity(0.10), stroke: Palette.haze.opacity(0.45))
                }
                .buttonStyle(PressableCard())
                somethingElse(title)
                    .frame(maxWidth: .infinity)
            }
        } else {
            somethingElse(title)
        }
    }

    private func somethingElse(_ title: String) -> some View {
        Button(action: onLog) {
            (Text(LocalizedStringKey(title)) + Text(" ") + Text(Image(systemName: "arrow.forward")))
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func isUsual(_ meal: SavedMeal) -> Bool {
        guard case let .watching(slot, _, _, _) = moment else { return false }
        return meal.useCount > 0 && meal.suggestSlot == slot
    }

    private var tail: String? {
        if let detail = TodayCopy.detail(moment, home: home, now: date) { return detail }
        if case let .watching(_, dueMin, _, _) = moment {
            return L10n( "Check-in at \(clock24(dueMin)) if it’s not logged.")
        }
        return nil
    }

    private var momentLabel: String {
        switch moment {
        case let .watching(slot, dueMin, overdue, light):
            let title = TodayCopy.slotTitle(slot)
            if overdue { return L10n( "Checking in · \(title)") }
            if light { return L10n( "Top-up · back \(clock24(dueMin))") }
            let at = home.nextCheckIn?.mealMin ?? dueMin
            let moved = !(home.movedSlots ?? []).isEmpty
            return moved
                ? L10n( "Next · \(title) · \(clock24(at)) · moved")
                : L10n( "Next · \(title) · \(clock24(at))")
        case let .snoozed(until):
            let back = until.map { clock24(TodayLayout.minuteOfDay(from: $0)) } ?? L10n( "later")
            return L10n( "Snoozed · back \(back)")
        case .covered: return L10n( "Today")
        case .quiet: return L10n( "Today")
        case .toGo: return L10n( "Still to go")
        case .checkIn, .conversation: return L10n( "Check-in")
        }
    }

    private var nextKcal: Int? {
        guard case let .watching(_, _, _, light) = moment else { return nil }
        if light { return home.topUp?.totalKcal }
        if let plate = home.appetite?.nextPlate { return plate.kcal }
        return home.day?.pace?.next?.suggestedKcal
    }
}

// MARK: - Picks

enum TodayPicks {
    /// Up to two saved meals for the next slot: ones saved for that slot (most used
    /// first), then any-time meals closest to the plate's size. A meal saved for a
    /// different slot (oats at dinner) never shows.
    static func resolve(saved: [SavedMeal], moment: TodayMoment, targetKcal: Int?) -> [SavedMeal] {
        guard case let .watching(slot, _, _, light) = moment, !light else { return [] }
        let forSlot = saved
            .filter { $0.suggestSlot == slot }
            .sorted { ($0.suggested ? 1 : 0, $0.useCount) > ($1.suggested ? 1 : 0, $1.useCount) }
        let anyTime = saved
            .filter { $0.suggestSlot == nil }
            .sorted { a, b in
                guard let target = targetKcal else { return a.useCount > b.useCount }
                return abs(a.kcal - target) < abs(b.kcal - target)
            }
        return Array((forSlot + anyTime).prefix(2))
    }
}

// MARK: - Appetite chip + dropdown

/// Header trigger — opens the custom appetite panel over Today.
private struct AppetiteChip: View {
    let level: String
    var open: Bool
    let action: () -> Void

    private var label: String {
        switch level {
        case "LOW": return L10n( "Appetite low")
        case "HUNGRY": return L10n( "Hungry")
        default: return L10n( "Normal appetite")
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                AppetiteBars(level: level)
                Text(LocalizedStringKey(label))
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Image(systemName: open ? "xmark" : "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
                    .frame(width: 12)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .glassCapsule(
                fill: open ? Color.white.opacity(0.10) : Color.white.opacity(0.05),
                stroke: open ? Color.white.opacity(0.18) : Color.white.opacity(0.10)
            )
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel(L10n("Appetite: \(label)"))
        .accessibilityHint(open ? L10n("Closes the menu") : L10n("Opens appetite options"))
        .accessibilityAddTraits(open ? .isSelected : [])
    }
}

/// Custom appetite picker — not a system Menu.
private struct AppetiteDropdown: View {
    let level: String
    let onPick: (String) -> Void

    private static let options: [(id: String, title: String, note: String)] = [
        ("HUNGRY", "Hungry", "Bigger plates today"),
        ("NORMAL", "Normal", "As planned"),
        ("LOW", "Low", "Smaller, denser meals"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today’s appetite")
                .font(Typography.mono(10))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Palette.inkFaint)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 2)

            ForEach(Self.options, id: \.id) { option in
                let selected = level == option.id
                Button {
                    onPick(option.id)
                } label: {
                    HStack(spacing: 12) {
                        AppetiteBars(level: option.id)
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(option.title))
                                .font(Typography.data(15, weight: selected ? .medium : .regular))
                                .foregroundStyle(Palette.ink)
                            Text(LocalizedStringKey(option.note))
                                .font(Typography.data(12, weight: .regular))
                                .foregroundStyle(Palette.inkSoft)
                        }
                        Spacer(minLength: 8)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.amber)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selected ? Color.white.opacity(0.08) : Color.clear)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(width: 248)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Palette.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Palette.hairlineHi)
                )
        }
        .accessibilityLabel("Appetite options")
    }
}

// MARK: - Plate strip

/// The day's plates as dots on a line: amber when eaten, a lit ring for the one
/// due now, faint rings for later, and training as a haze square.
struct PlateStrip: View {
    let home: HomeResponse
    /// True while appetite is saving — the hour line reshapes for the new day.
    var loading = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Kind { case meal(SlotState), snack(SlotState), training }

    private struct Stop: Identifiable {
        let id: String
        let atMin: Int
        let kind: Kind
    }

    private var stops: [Stop] {
        let now = home.day?.nowMin ?? 0
        var out = (home.day?.slots ?? []).map { slot -> Stop in
            var state = slot.slotState
            if state == .missed, !home.enforcementEnabled { state = .upcoming }
            return Stop(id: slot.slot, atMin: slot.atMin, kind: .meal(state))
        }
        for extra in home.appetite?.extraSlots ?? [] {
            out.append(Stop(id: extra.slot, atMin: extra.atMin, kind: .snack(extra.atMin < now ? .logged : .upcoming)))
        }
        for workout in home.training?.workouts ?? [] {
            out.append(Stop(id: "training-\(workout.id)", atMin: workout.startMin, kind: .training))
        }
        return out.sorted { $0.atMin < $1.atMin }
    }

    var body: some View {
        let stops = stops
        let count = max(stops.count, 3)
        ZStack {
            if !stops.isEmpty {
                strip(stops)
                    .opacity(loading ? 0.22 : 1)
            }
            if loading {
                loadingStrip(count: count)
                    .transition(.opacity)
            }
        }
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: loading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loading ? L10n("Updating meal times") : accessibilitySummary(stops))
    }

    private func strip(_ stops: [Stop]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(stops) { stop in
                VStack(spacing: 6) {
                    dot(stop)
                        .frame(width: 13, height: 13)
                    Text(clock24(stop.atMin))
                        .font(Typography.mono(10))
                        .foregroundStyle(labelColor(stop))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(alignment: .top) {
            GeometryReader { geo in
                let inset = geo.size.width / CGFloat(stops.count) / 2
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: max(0, geo.size.width - inset * 2), height: 1)
                    .offset(x: inset, y: 6)
            }
        }
    }

    /// Traveling amber pulse across placeholder hour marks while the day reshapes.
    private func loadingStrip(count: Int) -> some View {
        LoopingPhase(period: 1.35, still: 0.35) { t in
            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    let wave = Phase.window(t, Double(i) / Double(count) * 0.55, Double(i) / Double(count) * 0.55 + 0.18, Double(i) / Double(count) * 0.55 + 0.22, Double(i) / Double(count) * 0.55 + 0.4)
                    VStack(spacing: 6) {
                        Circle()
                            .strokeBorder(Palette.amber.opacity(0.25 + 0.55 * wave), lineWidth: 1.5)
                            .background(Circle().fill(Palette.amber.opacity(0.12 * wave)))
                            .frame(width: 13, height: 13)
                            .scaleEffect(0.88 + 0.14 * wave)
                        Capsule()
                            .fill(Color.white.opacity(0.06 + 0.14 * wave))
                            .frame(width: 30, height: 7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .background(alignment: .top) {
                GeometryReader { geo in
                    let inset = geo.size.width / CGFloat(count) / 2
                    let track = max(0, geo.size.width - inset * 2)
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Palette.amber.opacity(0), Palette.amber, Palette.amber.opacity(0)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: min(56, track * 0.35), height: 2)
                            .offset(x: t * max(0, track - min(56, track * 0.35)))
                    }
                    .frame(width: track, height: 2)
                    .offset(x: inset, y: 5.5)
                }
            }
        }
    }

    @ViewBuilder
    private func dot(_ stop: Stop) -> some View {
        switch stop.kind {
        case .training:
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Palette.haze)
                .shadow(color: Palette.haze.opacity(0.7), radius: 5)
        case let .meal(state):
            ring(state, size: 13)
        case let .snack(state):
            ring(state, size: 9)
        }
    }

    @ViewBuilder
    private func ring(_ state: SlotState, size: CGFloat) -> some View {
        switch state {
        case .logged:
            Circle()
                .fill(Palette.amber)
                .frame(width: size, height: size)
                .shadow(color: Palette.amber.opacity(0.6), radius: 4)
        case .now:
            Circle()
                .fill(Palette.background)
                .overlay(Circle().strokeBorder(Palette.amber, lineWidth: 2))
                .frame(width: size, height: size)
                .shadow(color: Palette.amber.opacity(0.8), radius: 6)
        case .missed:
            Circle()
                .fill(Palette.background)
                .overlay(Circle().strokeBorder(Palette.ember.opacity(0.6), lineWidth: 1.5))
                .frame(width: size, height: size)
        case .upcoming:
            Circle()
                .fill(Palette.background)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5))
                .frame(width: size, height: size)
        }
    }

    private func labelColor(_ stop: Stop) -> Color {
        switch stop.kind {
        case .training: return Palette.hazeSoft
        case let .meal(state), let .snack(state):
            switch state {
            case .now: return Palette.ink
            case .logged: return Palette.inkSoft
            default: return Palette.inkFaint
            }
        }
    }

    private func accessibilitySummary(_ stops: [Stop]) -> String {
        stops.map { stop in
            switch stop.kind {
            case .training:
                return L10n( "Training \(clock24(stop.atMin))")
            case let .meal(state), let .snack(state):
                let name = TodayCopy.slotTitle(stop.id)
                let word: String
                switch state {
                case .logged: word = L10n("eaten")
                case .now: word = L10n("due now")
                case .missed: word = L10n("missed")
                case .upcoming: word = L10n("later")
                }
                return L10n( "\(name) \(clock24(stop.atMin)), \(word)")
            }
        }
        .joined(separator: "; ")
    }
}

/// An expanding, fading ring — a live signal.
struct PingRing: View {
    var color: Color

    var body: some View {
        LoopingPhase(period: 1.6, still: 0) { t in
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .scaleEffect(1 + 1.4 * t)
                .opacity(0.7 * (1 - t))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Check-in takeover

/// A check-in (or the tier-3 talk) taking over the top of Today: an ember glow,
/// the manager's line, the plate, and one bone button.
struct CheckInTakeover: View {
    let home: HomeResponse
    let checkIn: HomeResponse.ActiveCheckIn
    let moment: TodayMoment
    let busy: Bool
    let error: String?
    let onOpen: () -> Void
    let onAteThis: () -> Void
    let onAlreadyAte: () -> Void
    let onSnooze: () -> Void
    /// Put the tier-3 talk away without changing the plan.
    var onLater: (() -> Void)? = nil
    /// Order nearby, for when there's nothing to eat where you are. Nil hides it.
    var onOrder: (() -> Void)? = nil

    var body: some View {
        screenBody.trackScreen("check_in")
    }

    @ViewBuilder
    private var screenBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                ZStack {
                    PingRing(color: Palette.ember)
                    Circle().fill(Palette.ember).frame(width: 7, height: 7)
                }
                .frame(width: 10, height: 10)
                Text(LocalizedStringKey(label)).sectionLabelStyle(Palette.amber)
            }
            .appearIn(0)

            Headline(TodayCopy.headline(moment), tail: TodayCopy.detail(moment, home: home), size: 42)
                .appearIn(1, rise: 16)

            if let rx = checkIn.prescription {
                Button(action: onOpen) {
                    PrescriptionCard(prescription: rx)
                }
                .buttonStyle(PressableCard())
                .accessibilityHint("Opens the full check-in")
                .appearIn(2, rise: 16)
            }

            actions
                .appearIn(3, rise: 16)

            if let error {
                Text(LocalizedStringKey(error))
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.danger)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            AmbientGlow(tone: .ember, strength: 1.2)
                .offset(y: -160)
        }
    }

    private var label: String {
        let time = Date().appClock
        switch CheckInFlavor(kind: checkIn.kind ?? "MEAL") {
        case .close: return L10n( "Closing the day · \(time)")
        case .light: return L10n( "Top-up · \(time)")
        case .meal: return checkIn.tier >= 3 ? L10n( "Let’s talk") : L10n( "Check-in · \(time)")
        }
    }

    private var orderDetail: String {
        let kcal = checkIn.prescription?.totalKcal ?? max(0, home.ledger.remainingKcal)
        switch CheckInFlavor(kind: checkIn.kind ?? "MEAL") {
        case .close: return L10n( "A dinner near you that fits \(kcal.formatted()) kcal")
        default: return L10n( "Places near you that fit \(kcal.formatted()) kcal")
        }
    }

    @ViewBuilder
    private var actions: some View {
        if checkIn.tier >= 3 {
            VStack(spacing: 10) {
                ActionButton(title: "Talk it through", action: onOpen)
                if let onLater {
                    ActionButton(title: "Later", kind: .secondary, action: onLater)
                }
            }
        } else {
            VStack(spacing: 10) {
                if let rx = checkIn.prescription {
                    ActionButton(
                        title: L10n("Eating it · \(rx.totalKcal.formatted()) kcal"),
                        busy: busy,
                        busyTitle: "Logging",
                        symbol: "checkmark",
                        action: onAteThis
                    )
                }
                HStack(spacing: 10) {
                    ActionButton(title: "I already ate", kind: .secondary, action: onAlreadyAte)
                    ActionButton(title: "Snooze", kind: .secondary, action: onSnooze)
                }
                .disabled(busy)
                if let onOrder {
                    Button(action: onOrder) {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Palette.hazeSoft)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("No food here? Order something")
                                    .font(Typography.data(15, weight: .regular))
                                    .foregroundStyle(Palette.ink)
                                Text(orderDetail)
                                    .font(Typography.data(12, weight: .regular))
                                    .foregroundStyle(Palette.inkSoft)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 54)
                        .background {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(LinearGradient(colors: [Palette.haze.opacity(0.12), Palette.haze.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Palette.haze.opacity(0.5))
                        }
                    }
                    .buttonStyle(PressableCard())
                    .disabled(busy)
                }
            }
        }
    }
}

/// The suggested plate: one row per food, then the totals.
struct PrescriptionCard: View {
    let prescription: HomeResponse.ActiveCheckIn.Prescription
    var roomy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(prescription.items) { item in
                HStack(spacing: 12) {
                    Text(item.quantity > 1 ? "\(Int(item.quantity))× \(FoodText.name(item.name))" : FoodText.name(item.name))
                        .font(Typography.data(roomy ? 17 : 16, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text("\(item.kcal)")
                        .font(Typography.mono(13))
                        .foregroundStyle(Palette.inkSoft)
                }
                .padding(.vertical, roomy ? 12 : 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                }
            }
            HStack {
                Text("\(prescription.totalKcal.formatted()) kcal")
                    .font(Typography.mono(14))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("\(Int(prescription.totalProteinG.rounded())) g protein")
                    .font(Typography.mono(13))
                    .foregroundStyle(Palette.amber)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .padding(.bottom, 10)
        .glass(radius: Radius.xl)
        .accessibilityElement(children: .combine)
    }
}

/// A rough symbol for a food name — enough to make a list scannable.
enum FoodSymbol {
    static func `for`(_ name: String) -> String {
        let n = name.lowercased()
        if ["milk", "shake", "juice", "smoothie", "latte", "kefir"].contains(where: n.contains) { return "cup.and.saucer.fill" }
        if ["banana", "apple", "berries", "orange", "fruit", "grapes", "dates"].contains(where: n.contains) { return "leaf.fill" }
        if ["oil", "butter", "avocado"].contains(where: n.contains) { return "drop.fill" }
        if ["rice", "oats", "pasta", "bread", "toast", "granola", "bagel", "potato", "tortilla", "cereal"].contains(where: n.contains) { return "takeoutbag.and.cup.and.straw.fill" }
        if ["nut", "almond", "peanut", "seed", "trail"].contains(where: n.contains) { return "circle.hexagongrid.fill" }
        return "fork.knife"
    }
}

// MARK: - Fuel strip

/// Calories left and protein, in one glass row under the hero.
struct FuelStrip: View {
    let home: HomeResponse
    let moment: TodayMoment

    var body: some View {
        let ledger = home.ledger
        HStack(spacing: 0) {
            cell(
                value: moment == .quiet || home.framing.state != "under" ? ledger.consumedKcal : max(0, ledger.remainingKcal),
                unit: moment == .quiet ? "kcal logged" : home.framing.state == "under" ? "kcal left" : "kcal eaten",
                fraction: Double(ledger.consumedKcal) / Double(max(ledger.targetKcal, 1)),
                tint: Palette.amber
            )
            if let target = ledger.targetProteinG, target > 0 {
                Rectangle().fill(Palette.hairline).frame(width: 1, height: 40)
                cell(
                    value: Int(ledger.consumedProteinG.rounded()),
                    unit: L10n("of \(Int(target.rounded())) g protein"),
                    fraction: ledger.consumedProteinG / target,
                    tint: Palette.ink
                )
            }
        }
        .padding(.vertical, 14)
        .glass(radius: Radius.lg)
    }

    private func cell(value: Int, unit: String, fraction: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value.formatted())
                    .font(Typography.data(22, weight: .light))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: Double(value)))
                Text(LocalizedStringKey(unit))
                    .font(Typography.mono(11))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            GeometryReader { geo in
                Capsule().fill(Color.white.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint)
                            .frame(width: geo.size.width * min(1, max(0, fraction)))
                    }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
