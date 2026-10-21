import SwiftUI

/// The Training tab, week first: pick a day in the strip and the card below shows
/// it — today's food around the session, how a past one went, what a planned one
/// will add, or a rest day. Then what's coming up, and settings in one row.
/// Everything is worked out on the phone from the sessions it holds and Today's
/// meals, so a meal, a new session or a switch shows the moment it happens.
struct TrainingScreen: View {
    var preview: TrainingWeekResponse? = nil
    /// Shown as the Training tab rather than pushed from somewhere.
    var isTabRoot = false
    /// Today's data, shared with the Today tab: a meal logged anywhere is in it at once.
    var home: HomeViewModel? = nil

    @Environment(AppEnvironment.self) private var env
    @State private var store: TrainingStore
    @State private var sheet: TrainSheet?
    @State private var weekOffset = 0
    /// The day picked in the strip; nil means today.
    @State private var selectedKey: String?
    @State private var forward = true
    /// A finger moving sideways over the strip: its lift must not also pick a day.
    @State private var swiping = false

    init(preview: TrainingWeekResponse? = nil, isTabRoot: Bool = false, home: HomeViewModel? = nil) {
        self.preview = preview
        self.isTabRoot = isTabRoot
        self.home = home
        _store = State(initialValue: TrainingStore(preview: preview))
    }

    var body: some View {
        SettingsScreen(
            title: "Train",
            accessory: AnyView(TrainPlanPill { sheet = .plan(defaultStart(on: .now)) }),
            showsBack: !isTabRoot,
            glow: .haze,
            showsHeadline: false
        ) {
            switch store.phase {
            case .ready:
                TimelineView(.everyMinute) { context in
                    content(now: context.date)
                }
            case let .failed(message):
                SettingsErrorBanner(message: message)
                ActionButton(title: "Try again", kind: .secondary) { Task { await store.load(env) } }
            case .loading:
                BusyDots(tint: Palette.hazeSoft)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task {
            store.todayChanged = { [home] in Task { await home?.load(showSpinner: false) } }
            await store.load(env)
        }
        // Today's steps tick from Today's meals at once; this brings past days' results.
        .onChange(of: env.changes.mealRevision) { _, _ in Task { await store.refresh(env) } }
        .sheet(item: $sheet) { sheet in sheetView(sheet) }
    }

    private func content(now: Date) -> some View {
        let byDay = TrainMath.byDay(store.sessions)
        let todayKey = TrainMath.dayKey(now)
        let latest = latestWeek(now: now)
        let days = weekDays(offset: weekOffset, byDay: byDay, now: now)
        let selected = days.first { $0.key == (selectedKey ?? todayKey) } ?? days.first { $0.isToday } ?? days[0]
        let upcoming = store.sessions.filter { $0.isPlanned && $0.start > now }
        return VStack(alignment: .leading, spacing: 14) {
            TrainWeekStrip(
                title: weekTitle,
                range: weekRange(days),
                summary: weekSummary(days),
                days: days,
                selectedKey: selected.key,
                canGoBack: weekOffset > earliestWeek,
                canGoForward: weekOffset < latest,
                onBack: { go(-1, latest: latest, byDay: byDay, now: now) },
                onForward: { go(1, latest: latest, byDay: byDay, now: now) },
                onThisWeek: weekOffset == 0 ? nil : { go(-weekOffset, latest: latest, byDay: byDay, now: now) },
                onPick: { day in
                    guard !swiping else { return }
                    Haptics.select()
                    withAnimation(Motion.settle) { selectedKey = day.key }
                }
            )
            .id(weekOffset)
            .transition(.push(from: forward ? .trailing : .leading))
            .simultaneousGesture(swipe(latest: latest, byDay: byDay, now: now))
            .appearIn(1, rise: 14)

            Text(dayLabel(selected))
                .font(Typography.mono(11))
                .tracking(1.3)
                .foregroundStyle(Palette.inkFaint)
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .id("label-\(selected.key)")
                .transition(dayChange)

            dayCard(selected, now: now)
                .id(selected.key)
                .transition(dayChange)
                .appearIn(2, rise: 14)

            TrainComingUp(
                sessions: Array(upcoming.prefix(3)),
                through: upcoming.last?.start,
                weightKg: store.weightKg,
                addCalories: store.addCalories,
                onOpen: { s in sheet = .edit(s) },
                onPlan: { sheet = .plan(defaultStart(on: now)) }
            )
            .padding(.top, 6)
            .appearIn(3, rise: 14)

            TrainSettingsRow(addCalories: store.addCalories, nudgeMin: store.nudgeMin, healthOn: env.health.connected) {
                sheet = .settings
            }
            .appearIn(4, rise: 14)
        }
    }

    // MARK: The day card

    @ViewBuilder
    private func dayCard(_ day: TrainDay, now: Date) -> some View {
        if day.sessions.isEmpty {
            TrainRestCard(day: day) { sheet = .plan(defaultStart(on: day.date)) }
        } else if day.isToday, let first = day.sessions.first {
            let trainingKcal = TrainMath.bump(day.sessions, weightKg: store.weightKg)
            let bump = store.addCalories ? trainingKcal : 0
            TrainTodayCard(
                session: first,
                baseKcal: store.baseKcal,
                bumpKcal: bump,
                targetKcal: TrainMath.target(base: store.baseKcal, bump: bump, addCalories: store.addCalories),
                addCalories: store.addCalories,
                dinnerMin: store.dinnerMin,
                steps: todaySteps(first: first, now: now),
                now: now,
                onLog: { env.chrome.logPanelOpen = true },
                onEdit: first.canEdit(now: now) ? { sheet = .edit(first) } : nil
            )
            .animation(Motion.settle, value: bump)
        } else if day.isPast {
            TrainPastCard(day: day, weightKg: store.weightKg)
        } else {
            VStack(spacing: 12) {
                ForEach(Array(day.sessions.enumerated()), id: \.element.id) { index, s in
                    TrainPlannedCard(
                        session: s,
                        dayBumpKcal: index == 0 ? TrainMath.bump(day.sessions, weightKg: store.weightKg) : nil,
                        addCalories: store.addCalories,
                        dinnerMin: store.dinnerMin,
                        onEdit: { sheet = s.canEdit(now: .now) ? .edit(s) : nil }
                    )
                }
            }
        }
    }

    /// The old day's card leaves quickly before the new one comes in, so the two never overlap.
    private var dayChange: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.1)),
            removal: .opacity.animation(.easeIn(duration: 0.1))
        )
    }

    private func dayLabel(_ day: TrainDay) -> String {
        let name = day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(AppLanguage.current.locale)).uppercased()
        return day.isToday ? L10n("TODAY · \(name)") : name
    }

    // MARK: Today

    /// Today's meals, from the Today tab's data; nil when it isn't loaded.
    private var todayMeals: [TrainMath.Meal]? {
        guard let home, case let .loaded(response) = home.phase else { return nil }
        return response.meals.compactMap { meal in
            guard let at = MealFormat.parse(meal.loggedAt), Calendar.current.isDateInToday(at) else { return nil }
            return TrainMath.Meal(at: at, kcal: meal.kcal)
        }
    }

    private func todaySteps(first: TrainSession?, now: Date) -> TrainMath.Steps? {
        guard let meals = todayMeals else { return store.serverSteps }
        let dinnerAt = Calendar.current.startOfDay(for: now).addingTimeInterval(Double(store.dinnerMin) * 60)
        return TrainMath.steps(first: first, dinnerAt: dinnerAt, meals: meals, now: now)
    }

    // MARK: The weeks

    /// Weeks back the strip shows: sessions are loaded from two weeks ago.
    private let earliestWeek = -1

    private func latestWeek(now: Date) -> Int {
        let last = store.horizonEnd(now: now).addingTimeInterval(-1)
        return Calendar.current.dateComponents([.weekOfYear], from: TrainMath.weekStart(now), to: TrainMath.weekStart(last)).weekOfYear ?? 0
    }

    private func swipe(latest: Int, byDay: [String: [TrainSession]], now: Date) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) { swiping = true }
            }
            .onEnded { value in
                let dx = value.translation.width
                if abs(dx) > 60, abs(dx) > abs(value.translation.height) * 1.5 {
                    go(dx < 0 ? 1 : -1, latest: latest, byDay: byDay, now: now)
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    swiping = false
                }
            }
    }

    /// Moves the strip; picks today on this week, else the week's first session day.
    private func go(_ step: Int, latest: Int, byDay: [String: [TrainSession]], now: Date) {
        let target = min(latest, max(earliestWeek, weekOffset + step))
        guard target != weekOffset else { return }
        forward = target > weekOffset
        let days = weekDays(offset: target, byDay: byDay, now: now)
        Haptics.select()
        withAnimation(Motion.settle) {
            weekOffset = target
            selectedKey = target == 0 ? nil : (days.first { !$0.sessions.isEmpty } ?? days[0]).key
        }
    }

    private func weekDays(offset: Int, byDay: [String: [TrainSession]], now: Date) -> [TrainDay] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .weekOfYear, value: offset, to: TrainMath.weekStart(now)) ?? now
        let todayKey = TrainMath.dayKey(now)
        let earliest = store.earliestStart(now: now)
        let horizon = store.horizonEnd(now: now)
        let meals = todayMeals
        return (0..<7).compactMap { i in
            guard let date = calendar.date(byAdding: .day, value: i, to: start) else { return nil }
            let key = TrainMath.dayKey(date)
            let sessions = byDay[key] ?? []
            let isToday = key == todayKey
            var eaten = store.serverEaten(key)
            var refuelMeal = store.serverRefuelMeal(key)
            if isToday, let meals {
                eaten = meals.reduce(0) { $0 + $1.kcal }
                refuelMeal = nil
            }
            return TrainDay(
                key: key,
                date: date,
                sessions: sessions,
                bumpKcal: store.addCalories ? TrainMath.bump(sessions, weightKg: store.weightKg) : 0,
                refuel: refuel(key: key, sessions: sessions, todayKey: todayKey, now: now),
                isToday: isToday,
                isPast: key < todayKey,
                canAdd: date >= earliest && date < horizon,
                eatenKcal: eaten,
                refuelMeal: refuelMeal
            )
        }
    }

    /// Past days as the server counted them (it has all their meals); today from
    /// Today's meals on the phone; later days are planned.
    private func refuel(key: String, sessions: [TrainSession], todayKey: String, now: Date) -> TrainMath.Refuel? {
        guard !sessions.isEmpty else { return nil }
        if key > todayKey { return .planned }
        if key == todayKey, let meals = todayMeals { return TrainMath.refuel(sessions, meals: meals, now: now) }
        return store.serverRefuel(key) ?? TrainMath.refuel(sessions, meals: [], now: now)
    }

    private var weekTitle: String {
        switch weekOffset {
        case 0: return L10n( "This week")
        case 1: return L10n( "Next week")
        case -1: return L10n( "Last week")
        default: return L10n( "In \(weekOffset) weeks")
        }
    }

    private func weekRange(_ days: [TrainDay]) -> String {
        guard let first = days.first?.date, let last = days.last?.date else { return "" }
        return L10n( "\(first.formatted(.dateTime.day())) – \(last.formatted(.dateTime.day().month(.abbreviated)))")
    }

    private func weekSummary(_ days: [TrainDay]) -> String {
        let sessions = days.reduce(0) { $0 + $1.sessions.count }
        guard sessions > 0 else { return L10n( "No sessions — tap a day to plan one") }
        let finished = days.filter { $0.refuel == .done || $0.refuel == .missed }.count
        let refueled = days.filter { $0.refuel == .done }.count
        let planned = days.filter { $0.refuel == .planned }.reduce(0) { $0 + $1.sessions.count }
        var parts = [sessions == 1 ? L10n( "1 session") : L10n( "\(sessions) sessions")]
        if finished > 0 { parts.append(L10n( "refueled after \(refueled) of \(finished)")) }
        if planned > 0 && finished > 0 { parts.append(L10n( "\(planned) planned")) }
        return parts.joined(separator: " · ")
    }

    /// 17:00 on that day; on today once 17:00 has gone, the next full hour.
    private func defaultStart(on day: Date) -> Date {
        let calendar = Calendar.current
        let evening = TrainMath.at(17, 0, on: day)
        guard calendar.isDateInToday(day), evening <= .now.addingTimeInterval(15 * 60) else { return evening }
        let nextHour = calendar.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? .now
        return calendar.isDateInToday(nextHour) ? nextHour : TrainMath.at(17, 0, on: nextHour)
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetView(_ sheet: TrainSheet) -> some View {
        switch sheet {
        case let .plan(start):
            PlanSessionSheet(
                start: start,
                earliest: store.earliestStart(),
                horizonEnd: store.horizonEnd(),
                weightKg: store.weightKg,
                addCalories: store.addCalories,
                busyDays: Set(store.sessions.map { TrainMath.dayKey($0.start) }),
                onSave: { draft in store.schedule(draft, env: env) }
            )
        case let .edit(session):
            EditSessionSheet(
                session: session,
                followingCount: store.sessions.filter { $0.seriesId != nil && $0.seriesId == session.seriesId && $0.start >= session.start }.count,
                horizonEnd: store.horizonEnd(),
                weightKg: store.weightKg,
                addCalories: store.addCalories,
                onSave: { draft, scope in store.update(session, to: draft, scope: scope, env: env) },
                onDelete: { scope in store.delete(session, scope: scope, env: env) }
            )
        case .settings:
            let today = TrainMath.byDay(store.sessions)[TrainMath.dayKey(.now)] ?? []
            TrainSettingsSheet(
                addCalories: store.addCalories,
                nudgeMin: store.nudgeMin,
                healthOn: env.health.connected,
                baseKcal: store.baseKcal,
                todayTrainingKcal: TrainMath.bump(today, weightKg: store.weightKg),
                onAddCalories: { store.setAddCalories($0, env: env) },
                onNudge: { store.setNudge($0, env: env) }
            )
        }
    }
}
