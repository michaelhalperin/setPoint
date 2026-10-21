import Foundation
import Observation

/// The Train screen's data, held on the phone like Today's: every change shows
/// at once, then saves to the server one at a time in the order made. If the
/// server says no, that change is put back with "Didn't save · Try again". When
/// nothing is left saving, one quiet refresh brings the server's view.
@MainActor
@Observable
final class TrainingStore {
    enum Phase: Equatable {
        case loading
        case failed(String)
        case ready
    }

    private(set) var phase: Phase = .loading
    private(set) var sessions: [TrainSession] = []
    /// Everything else the server said: targets, settings, how past days went.
    private(set) var week: TrainingWeekResponse?

    /// Called after a saved change that touches today, so Today can catch up.
    @ObservationIgnored var todayChanged: (() -> Void)?

    @ObservationIgnored private var saving = 0
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var syncedHealth = false
    @ObservationIgnored private let isPreview: Bool
    private var addCaloriesNow: Bool?
    private var nudgeNow: Int?

    init(preview: TrainingWeekResponse? = nil) {
        isPreview = preview != nil
        if let preview {
            apply(preview)
            phase = .ready
        }
    }

    // MARK: What the screen reads

    var addCalories: Bool { addCaloriesNow ?? week?.addCalories ?? true }
    var nudgeMin: Int { nudgeNow ?? week?.preWorkoutNudgeMin ?? 0 }
    var baseKcal: Int { week?.today.baseKcal ?? 0 }
    var dinnerMin: Int { week?.today.dinnerMin ?? 19 * 60 }
    var weightKg: Double { week?.weightKg ?? 80 }
    /// A snack they already eat, or a light staple that fits, for "Snack before".
    private(set) var snackBefore: TrainingWeekResponse.SnackBefore?
    private(set) var loggingSnack = false
    private(set) var loggedSnackId: String?

    /// The end of the last day sessions can be planned on.
    func horizonEnd(now: Date = .now, calendar: Calendar = .current) -> Date {
        let days = week?.horizonDays ?? 56
        return calendar.date(byAdding: .day, value: days + 1, to: calendar.startOfDay(for: now)) ?? now
    }

    /// The earliest a session can be added: a week back, for one done without the watch.
    func earliestStart(now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
    }

    /// How a past day went, as the server worked it out from all its meals.
    func serverRefuel(_ dayKey: String) -> TrainMath.Refuel? {
        (week?.days.first { $0.date == dayKey }?.refuel).flatMap(TrainMath.Refuel.init(rawValue:))
    }

    /// All food logged on a past day, as the server counted it.
    func serverEaten(_ dayKey: String) -> Int? {
        week?.days.first { $0.date == dayKey }?.eatenKcal
    }

    /// The meal that counted as a past day's refuel.
    func serverRefuelMeal(_ dayKey: String) -> TrainMath.Meal? {
        guard let meal = week?.days.first(where: { $0.date == dayKey })?.refuelMeal,
              let at = Self.parseDate(meal.at) else { return nil }
        return TrainMath.Meal(at: at, kcal: meal.kcal)
    }

    /// Today's steps as the server saw them, for when Today's meals aren't on the phone.
    var serverSteps: TrainMath.Steps? {
        week?.today.steps.map { TrainMath.Steps(before: $0.before, workout: $0.workout, refuel: $0.refuel, dinner: $0.dinner) }
    }

    // MARK: Loading

    /// The first load also sends Apple Health's workouts and fetches once more to show them.
    func load(_ env: AppEnvironment, showSpinner: Bool = false) async {
        guard !isPreview else { return }
        if showSpinner { phase = .loading }
        do {
            let fresh: TrainingWeekResponse = try await env.api.get("/api/workouts")
            if saving == 0 { apply(fresh) }
            phase = .ready
            await resolveSnack(env)
        } catch {
            if week == nil {
                phase = .failed(UserFacingError.message(for: error, fallback: L10n( "Couldn’t load your training.")))
            } else {
                phase = .ready
            }
            return
        }
        guard !syncedHealth else { return }
        syncedHealth = true
        await env.health.uploadWorkouts()
        await refresh(env)
    }

    /// A quiet refresh; it never replaces changes still saving.
    func refresh(_ env: AppEnvironment) async {
        guard !isPreview, saving == 0,
              let fresh: TrainingWeekResponse = try? await env.api.get("/api/workouts"),
              saving == 0 else { return }
        apply(fresh)
        phase = .ready
        await resolveSnack(env)
    }

    /// Logged snacks first, then a usual plate, then a light staple.
    func resolveSnack(_ env: AppEnvironment, meals extra: [MealSummary] = []) async {
        if isPreview {
            snackBefore = week?.today.snackBefore ?? TrainMath.snackBefore(server: nil, saved: [], meals: extra)
            return
        }
        async let savedCall: SavedMealsResponse? = try? await env.api.get("/api/saved-meals")
        async let settingsCall: SettingsResponse? = try? await env.api.get("/api/settings")
        var meals = extra
        var seen = Set(extra.map(\.id))
        await withTaskGroup(of: [MealSummary].self) { group in
            for offset in 0..<8 {
                group.addTask {
                    guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: .now) else { return [] }
                    let list: MealsListResponse? = try? await env.api.get("/api/meals", query: ["date": TrainMath.dayKey(day)])
                    return list?.meals ?? []
                }
            }
            for await batch in group {
                for meal in batch where seen.insert(meal.id).inserted {
                    meals.append(meal)
                }
            }
        }
        let saved = await savedCall
        let settings = await settingsCall
        snackBefore = TrainMath.snackBefore(
            server: week?.today.snackBefore,
            saved: saved?.meals ?? [],
            meals: meals,
            disliked: (settings?.dislikedFoods ?? []) + (settings?.restrictions.map(\.label) ?? []),
            pantry: settings?.pantryTokens ?? []
        )
    }

    /// Logs the suggested plate as-is — no composer, no parse.
    func logSnack(_ snack: TrainingWeekResponse.SnackBefore, env: AppEnvironment, home: HomeViewModel?) async {
        guard !loggingSnack, loggedSnackId != snack.id else { return }
        if isPreview {
            loggedSnackId = snack.id
            Haptics.landed()
            return
        }
        loggingSnack = true
        let pendingId = "pending-snack-\(UUID().uuidString)"
        let pending = Self.mealSummary(from: snack, id: pendingId)
        let slot = Self.currentSlot(in: home)
        let before = home?.applyNow { $0.inserting(pending, into: slot) }
        Haptics.landed()
        do {
            let res: LogMealResponse = try await env.api.post(
                "/api/meals",
                LogMealRequest(
                    text: snack.name,
                    macros: .init(kcal: snack.kcal, proteinG: snack.proteinG),
                    clientId: UUID().uuidString
                )
            )
            if !snack.correctionItems.isEmpty {
                let _: MealCorrectionResponse? = try? await env.api.patch(
                    "/api/meals/\(res.meal.id)",
                    MealCorrectionRequest(summary: snack.name, items: snack.correctionItems)
                )
            }
            loggedSnackId = snack.id
            let landed = Self.mealSummary(from: snack, id: res.meal.id, kcal: res.meal.kcal, proteinG: res.meal.proteinG)
            if let before { home?.restore(before) }
            home?.applyLoggedMeal(landed, slot: slot)
            env.chrome.noteLogged(mealID: res.meal.id, kcal: res.meal.kcal, title: snack.name)
            env.changes.mealsChanged()
            todayChanged?()
            await HealthKitManager.shared.writeMeal(landed)
        } catch APIError.unauthorized {
            if let before { home?.restore(before) }
        } catch {
            if let before { home?.restore(before) }
            env.chrome.reportFailure(retry: { [weak self] in
                Task { await self?.logSnack(snack, env: env, home: home) }
            })
        }
        loggingSnack = false
    }

    private static func currentSlot(in home: HomeViewModel?) -> MealSlot {
        if case let .loaded(response) = home?.phase {
            let minute = response.day?.nowMin ?? TodayLayout.minuteOfDay(from: .now)
            return TodayLayout.slot(forMinute: minute, times: response.resolvedMealTimes)
        }
        return TodayLayout.slot(forMinute: TodayLayout.minuteOfDay(from: .now), times: .standard)
    }

    private static func mealSummary(
        from snack: TrainingWeekResponse.SnackBefore,
        id: String,
        kcal: Int? = nil,
        proteinG: Double? = nil
    ) -> MealSummary {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return MealSummary(
            id: id,
            loggedAt: formatter.string(from: Date()),
            kcal: kcal ?? snack.kcal,
            proteinG: proteinG ?? snack.proteinG ?? 0,
            carbsG: 0,
            fatG: 0,
            source: "TEXT",
            summary: snack.name,
            photoUrl: nil,
            notes: nil,
            items: snack.items?.map {
                MealSummary.Item(
                    name: $0.name,
                    quantity: $0.quantity ?? "",
                    kcal: $0.kcal,
                    proteinG: $0.proteinG ?? 0,
                    carbsG: 0,
                    fatG: 0
                )
            },
            parseConfidence: nil
        )
    }

    /// Takes the server's view. Only called with nothing saving, so the switches
    /// it carries are the saved ones.
    private func apply(_ response: TrainingWeekResponse) {
        week = response
        addCaloriesNow = nil
        nudgeNow = nil
        // Older servers only list sessions inside the last days.
        let entries = response.sessions ?? response.days.flatMap { day in
            day.workouts.map { TrainingWeekResponse.Entry(id: $0.id, kind: $0.kind, source: $0.source, start: $0.start, durationMin: $0.durationMin, activeKcal: $0.activeKcal) }
        }
        sessions = entries.compactMap { e in
            guard let start = Self.parseDate(e.start) else { return nil }
            return TrainSession(id: e.id, clientId: e.clientId, seriesId: e.seriesId, kind: e.kind, source: e.source, start: start, durationMin: e.durationMin, activeKcal: e.activeKcal)
        }
        .sorted { $0.start < $1.start }
    }

    nonisolated static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    // MARK: Changes

    /// Plans a session, or a weekly repeat of it up to the horizon.
    func schedule(_ draft: SessionDraft, env: AppEnvironment) {
        let now = Date.now
        let starts = draft.start > now
            ? TrainMath.plannedStarts(from: draft.start, weekdays: draft.repeatDays, until: horizonEnd(now: now))
            : [draft.start]
        let seriesId = starts.count > 1 ? UUID().uuidString : nil
        let added = starts.map { start -> TrainSession in
            let id = UUID().uuidString
            return TrainSession(id: id, clientId: id, seriesId: seriesId, kind: draft.kind, source: "PLANNED", start: start, durationMin: draft.durationMin)
        }
        let ids = Set(added.map(\.id))
        insert(added)
        Haptics.landed()

        struct Body: Encodable {
            struct Item: Encodable {
                let clientId: String
                let start: Date
            }
            let kind: String
            let durationMin: Int
            let seriesId: String?
            let sessions: [Item]
        }
        let body = Body(kind: draft.kind, durationMin: draft.durationMin, seriesId: seriesId, sessions: added.map { .init(clientId: $0.id, start: $0.start) })
        save(env, touchesToday: added.contains { Calendar.current.isDateInToday($0.start) }) {
            try await env.api.post("/api/workouts/planned", body)
        } undo: { [weak self] in
            self?.sessions.removeAll { ids.contains($0.id) }
        } retry: { [weak self] in
            self?.schedule(draft, env: env)
        }
    }

    /// Changes a session that hasn't started; `.following` also changes the later ones in its repeat.
    func update(_ session: TrainSession, to draft: SessionDraft, scope: SessionScope, env: AppEnvironment) {
        let targets = covered(session, scope: scope)
        let before = targets
        let moved = draft.start != session.start
        let changed = targets.map { s -> TrainSession in
            var c = s
            c.kind = draft.kind
            c.durationMin = draft.durationMin
            if s.id == session.id {
                c.start = draft.start
            } else if moved {
                c.start = TrainMath.moved(s.start, from: session.start, to: draft.start)
            }
            return c
        }
        replace(changed)
        Haptics.landed()

        struct Body: Encodable {
            let kind: String
            let durationMin: Int
            let start: Date?
            let scope: String
        }
        let body = Body(kind: draft.kind, durationMin: draft.durationMin, start: moved ? draft.start : nil, scope: scope.rawValue)
        let today = (before + changed).contains { Calendar.current.isDateInToday($0.start) }
        save(env, touchesToday: today) {
            try await env.api.patch("/api/workouts/\(session.id)", body)
        } undo: { [weak self] in
            self?.replace(before)
        } retry: { [weak self] in
            self?.update(session, to: draft, scope: scope, env: env)
        }
    }

    /// Removes a session that hasn't started; `.following` also removes the rest of its repeat.
    func delete(_ session: TrainSession, scope: SessionScope, env: AppEnvironment) {
        let removed = covered(session, scope: scope)
        let ids = Set(removed.map(\.id))
        sessions.removeAll { ids.contains($0.id) }
        Haptics.landed()
        save(env, touchesToday: removed.contains { Calendar.current.isDateInToday($0.start) }) {
            try await env.api.delete("/api/workouts/\(session.id)", query: ["scope": scope.rawValue])
        } undo: { [weak self] in
            self?.insert(removed)
        } retry: { [weak self] in
            self?.delete(session, scope: scope, env: env)
        }
    }

    func setAddCalories(_ value: Bool, env: AppEnvironment) {
        let previous = addCaloriesNow
        addCaloriesNow = value
        save(env, touchesToday: true) {
            try await env.api.patch("/api/settings", SettingsPatch(training: .init(addCalories: value)))
        } undo: { [weak self] in
            self?.addCaloriesNow = previous
        } retry: { [weak self] in
            self?.setAddCalories(value, env: env)
        }
    }

    func setNudge(_ value: Int, env: AppEnvironment) {
        let previous = nudgeNow
        nudgeNow = value
        save(env, touchesToday: false) {
            try await env.api.patch("/api/settings", SettingsPatch(training: .init(preWorkoutNudgeMin: value)))
        } undo: { [weak self] in
            self?.nudgeNow = previous
        } retry: { [weak self] in
            self?.setNudge(value, env: env)
        }
    }

    // MARK: Plumbing

    /// The session, plus the later ones in its repeat that haven't started.
    private func covered(_ session: TrainSession, scope: SessionScope) -> [TrainSession] {
        guard scope == .following, let series = session.seriesId else { return [session] }
        return sessions.filter { $0.seriesId == series && $0.start >= session.start && $0.isPlanned }
    }

    private func insert(_ added: [TrainSession]) {
        sessions = (sessions + added).sorted { $0.start < $1.start }
    }

    private func replace(_ changed: [TrainSession]) {
        let byId = Dictionary(changed.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        sessions = sessions.map { byId[$0.id] ?? $0 }.sorted { $0.start < $1.start }
    }

    /// Runs `work` after every earlier save, in order. A failure puts the change
    /// back and offers to try again; the last save to finish refreshes.
    private func save(
        _ env: AppEnvironment,
        touchesToday: Bool,
        work: @escaping @MainActor () async throws -> Void,
        undo: @escaping @MainActor () -> Void,
        retry: @escaping @MainActor () -> Void
    ) {
        guard !isPreview else { return }
        saving += 1
        let previous = tail
        tail = Task { @MainActor [weak self] in
            await previous?.value
            do {
                try await work()
                if touchesToday { self?.todayChanged?() }
            } catch APIError.unauthorized {
                // Signed out; the app is leaving this screen.
            } catch {
                undo()
                env.chrome.reportFailure(retry: retry)
            }
            guard let self else { return }
            saving -= 1
            if saving == 0 { await refresh(env) }
        }
    }
}
