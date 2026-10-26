import EventKit
import Foundation
import Observation
import SwiftUI
import UIKit

/// Reads EventKit on-device and uploads busy intervals only — never titles.
@MainActor
@Observable
final class CalendarManager {
    static let shared = CalendarManager()
    static let selectedIdsKey = "com.setpoint.app.calendar.selectedIds"
    /// Last known server "enabled", so a slow or failed fetch doesn't look like a disconnect.
    static let enabledKey = "com.setpoint.app.calendar.enabled"
    /// Today plus the next seven days — enough for the week screen's "Tomorrow" on a Sunday.
    static let uploadDays = 8

    var api: APIClient?
    private(set) var accessGranted = false
    private(set) var accessDenied = false
    private(set) var choices: [CalendarChoice] = []
    var selectedIds: Set<String>
    private(set) var lastError: String?
    private(set) var uploading = false
    /// A calendar or rule changed and the week is being recalculated.
    private(set) var refreshing = false
    private(set) var mealsMovedThisWeek = 0
    private(set) var week: CalendarWeekResponse?
    /// The week couldn't be fetched and there's none to show — the screen offers a retry.
    private(set) var weekError: String?
    private(set) var preview: CalendarPreviewResponse?
    var leadMin = 45
    var minBlockMin = 60
    var workdaysOnly = true
    var includeAllDay = false
    var countFree = false
    var enabled = false

    private let store = EKEventStore()
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    private var resyncTask: Task<Void, Never>?
    /// Set only by `-uiStub` previews: no EventKit, no network.
    private(set) var isPreview = false
    private var previewEvents: [String: [CalendarDayEvent]]?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.array(forKey: Self.selectedIdsKey) as? [String] ?? []
        self.selectedIds = Set(stored)
        self.enabled = defaults.bool(forKey: Self.enabledKey)
        refreshAuthorization()
    }

    var connected: Bool { accessGranted && enabled }

    /// On in SetPoint, but iOS has no Calendar permission — after a reinstall, or
    /// access turned off in Settings. Settings are kept; only permission is missing.
    var needsReconnect: Bool { enabled && !accessGranted }

    var ownChoices: [CalendarChoice] { choices.filter { !$0.subscribed } }
    var subscribedChoices: [CalendarChoice] { choices.filter(\.subscribed) }
    var selectedChoices: [CalendarChoice] { choices.filter { selectedIds.contains($0.id) } }

    /// "3 moved" / "On" / "Off" for the You row.
    var youRowValue: String {
        if needsReconnect { return L10n( "Reconnect") }
        guard connected else { return L10n( "Off") }
        if let moved = week?.movedCount, moved > 0 { return L10n( "\(moved) moved") }
        return L10n( "On")
    }

    func start() {
        guard observer == nil, !isPreview else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCalendars()
                await self?.uploadBusy()
                await self?.refreshWeek()
            }
        }
    }

    func refreshAuthorization() {
        guard !isPreview else { return }
        let status = EKEventStore.authorizationStatus(for: .event)
        accessGranted = status == .fullAccess
        accessDenied = status == .denied || status == .restricted || status == .writeOnly
    }

    func requestAccess() async -> Bool {
        if isPreview { return true }
        lastError = nil
        do {
            accessGranted = try await store.requestFullAccessToEvents()
        } catch {
            lastError = UserFacingError.message(for: error, fallback: L10n( "Couldn't open Calendar access."))
            accessGranted = false
        }
        refreshAuthorization()
        if accessGranted { refreshCalendars() }
        return accessGranted
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func refreshCalendars(now: Date = .now) {
        guard accessGranted, !isPreview else { return }
        let calendars = store.calendars(for: .event).sorted { $0.title < $1.title }
        if selectedIds.isEmpty {
            // Birthdays and subscribed calendars (holidays, sports) aren't the user's own time.
            let own = calendars.filter { Self.isOwnCalendar($0) }
            selectedIds = Set((own.isEmpty ? calendars : own).map(\.calendarIdentifier))
            persistSelection()
        }
        let from = Calendar.current.startOfDay(for: now)
        let to = Calendar.current.date(byAdding: .day, value: 7, to: from) ?? from
        let events = calendars.isEmpty
            ? []
            : store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: calendars))
        var counts: [String: Int] = [:]
        for event in events where Self.countsAsBusy(event, countFree: countFree) {
            counts[event.calendar.calendarIdentifier, default: 0] += 1
        }
        choices = calendars.map { calendar in
            CalendarChoice(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                source: Self.sourceLabel(calendar),
                colorHex: Self.hex(calendar.cgColor),
                subscribed: !Self.isOwnCalendar(calendar),
                eventsThisWeek: counts[calendar.calendarIdentifier] ?? 0
            )
        }
    }

    func isSelected(_ id: String) -> Bool { selectedIds.contains(id) }

    /// Keeps at least one calendar on — with none, nothing would ever count as busy.
    /// Returns false when that rule refused the change.
    @discardableResult
    func setSelected(_ id: String, _ on: Bool, upload: Bool = true) -> Bool {
        var next = selectedIds
        if on {
            next.insert(id)
        } else if next.count > 1 {
            next.remove(id)
        } else {
            return false
        }
        guard next != selectedIds else { return true }
        selectedIds = next
        persistSelection()
        if upload { resync(savingPrefs: false) }
        return true
    }

    func connect() async {
        guard await requestAccess() else { return }
        setEnabled(true)
        await savePrefs()
        await uploadBusy()
        await refreshWeek()
    }

    func disconnect() async {
        resyncTask?.cancel()
        refreshing = false
        setEnabled(false)
        week = nil
        mealsMovedThisWeek = 0
        guard !isPreview else { return }
        await savePrefs()
        try? await api?.delete("/api/calendar")
    }

    /// Saves the rules, re-reads EventKit (free events may now count) and redraws the week.
    func rulesChanged() {
        resync(savingPrefs: true)
    }

    /// One recalculation at a time: a newer change cancels the one in flight, so a
    /// slow response can't flip a toggle back.
    private func resync(savingPrefs: Bool) {
        resyncTask?.cancel()
        refreshing = true
        resyncTask = Task { [weak self] in
            guard let self else { return }
            if self.isPreview {
                try? await Task.sleep(for: .seconds(0.7))
            } else {
                if savingPrefs {
                    self.refreshCalendars()
                    await self.savePrefs()
                } else {
                    self.refreshCalendars()
                }
                guard !Task.isCancelled else { return }
                await self.uploadBusy()
                guard !Task.isCancelled else { return }
                if let response: CalendarWeekResponse = try? await self.api?.get("/api/calendar/week"), !Task.isCancelled {
                    withAnimation(Motion.settle) { self.apply(response) }
                }
            }
            guard !Task.isCancelled else { return }
            self.refreshing = false
        }
    }

    func savePrefs() async {
        guard !isPreview else { return }
        try? await api?.patch(
            "/api/settings",
            SettingsPatch(calendar: .init(
                enabled: enabled,
                leadMin: leadMin,
                minBlockMin: minBlockMin,
                workdaysOnly: workdaysOnly,
                includeAllDay: includeAllDay,
                countFree: countFree
            ))
        )
    }

    /// Learn whether it's on (from the server), then push fresh busy times and redraw.
    func sync() async {
        guard !isPreview else { return }
        refreshAuthorization()
        await refreshStatus()
        guard connected else { return }
        refreshCalendars()
        await uploadBusy()
        await refreshWeek()
    }

    /// Whether it's on and the rules, from the server. Needs no Calendar permission.
    func refreshStatus() async {
        guard !isPreview, let api else { return }
        guard let status: CalendarStatusResponse = try? await api.get("/api/calendar") else { return }
        setEnabled(status.enabled)
        leadMin = status.leadMin
        minBlockMin = status.minBlockMin
        workdaysOnly = status.workdaysOnly
        includeAllDay = status.includeAllDay
        countFree = status.countFree ?? countFree
    }

    /// After a reinstall: ask iOS again and pick up where it left off — no setup screens.
    func reconnect() async {
        guard await requestAccess() else { return }
        await uploadBusy()
        await refreshWeek()
    }

    /// Sign-out: the next account shouldn't inherit this one's calendar state.
    func clearAccountState() {
        resyncTask?.cancel()
        refreshing = false
        week = nil
        weekError = nil
        preview = nil
        mealsMovedThisWeek = 0
        setEnabled(false)
        selectedIds = []
        persistSelection()
    }

    private func setEnabled(_ value: Bool) {
        enabled = value
        if !isPreview { defaults.set(value, forKey: Self.enabledKey) }
    }

    func refreshWeek() async {
        guard !isPreview, let api else { return }
        weekError = nil
        do {
            let response: CalendarWeekResponse = try await api.get("/api/calendar/week")
            apply(response)
        } catch {
            // Keep a week already on screen; only an empty screen needs the error.
            if week == nil {
                weekError = UserFacingError.message(for: error, fallback: L10n( "Your calendar settings are safe. Try again in a moment."))
            }
        }
    }

    private func apply(_ response: CalendarWeekResponse) {
        week = response
        setEnabled(response.enabled)
        leadMin = response.leadMin
        minBlockMin = response.minBlockMin
        workdaysOnly = response.workdaysOnly
        includeAllDay = response.includeAllDay
        countFree = response.countFree
        mealsMovedThisWeek = response.movedCount
    }

    /// "Keep lunch at 13:00", or undo it. Returns false when it didn't save.
    @discardableResult
    func setKeep(date: String, slot: String, keep: Bool) async -> Bool {
        lastError = nil
        guard !isPreview else {
            try? await Task.sleep(for: .seconds(0.6))
            withAnimation(Motion.settle) { week = week?.withKeep(date: date, slot: slot, keep: keep) }
            return true
        }
        do {
            try await api?.post("/api/calendar/keep", CalendarKeepRequest(date: date, slot: slot, keep: keep))
        } catch {
            lastError = UserFacingError.message(for: error, fallback: L10n( "Couldn't change that meal. Try again."))
            return false
        }
        if let response: CalendarWeekResponse = try? await api?.get("/api/calendar/week") {
            withAnimation(Motion.settle) { apply(response) }
        } else if let week {
            // Saved, but the refresh failed — show the change anyway.
            withAnimation(Motion.settle) { self.week = week.withKeep(date: date, slot: slot, keep: keep) }
        }
        return true
    }

    /// Before connecting: which meals the picked calendars would move this week. Nothing is stored.
    func refreshPreview(now: Date = .now) async {
        guard accessGranted, !isPreview, let api else { return }
        let (from, to, blocks) = busyWindow(now: now)
        preview = try? await api.post(
            "/api/calendar/preview",
            CalendarBusyUpload(from: iso(from), to: iso(to), blocks: blocks)
        )
    }

    func uploadBusy(now: Date = .now) async {
        guard accessGranted, enabled, !isPreview, let api else { return }
        uploading = true
        defer { uploading = false }
        let (from, to, blocks) = busyWindow(now: now)
        do {
            try await api.put("/api/calendar/busy", CalendarBusyUpload(from: iso(from), to: iso(to), blocks: blocks))
        } catch {
            lastError = UserFacingError.message(for: error, fallback: L10n( "Couldn't update busy times."))
        }
    }

    /// Titles for the day screen. They're read here and never leave the phone.
    func events(on date: String) -> [CalendarDayEvent] {
        if let previewEvents { return previewEvents[date] ?? [] }
        guard accessGranted, let day = CalendarDates.date(date) else { return [] }
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        let cals = store.calendars(for: .event).filter { selectedIds.contains($0.calendarIdentifier) }
        guard !cals.isEmpty else { return [] }
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: cals))
            .filter { Self.countsAsBusy($0, countFree: countFree) }
            .map { event in
                let startMin = event.startDate <= start ? 0 : Self.minutes(from: start, to: event.startDate)
                let endMin = event.endDate >= end ? 1440 : Self.minutes(from: start, to: event.endDate)
                return CalendarDayEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Busy",
                    calendar: event.calendar.title,
                    startMin: startMin,
                    endMin: max(endMin, startMin + 1),
                    allDay: event.isAllDay
                )
            }
            .sorted { $0.startMin < $1.startMin }
    }

    private func busyWindow(now: Date) -> (Date, Date, [CalendarBusyUpload.Block]) {
        // From the start of today, so an all-day event today isn't clipped into "busy from now".
        let from = Calendar.current.startOfDay(for: now)
        let to = Calendar.current.date(byAdding: .day, value: Self.uploadDays, to: from) ?? from
        let cals = store.calendars(for: .event).filter { selectedIds.contains($0.calendarIdentifier) }
        guard !cals.isEmpty else { return (from, to, []) }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: cals)
        let blocks = store.events(matching: predicate)
            .filter { Self.countsAsBusy($0, countFree: countFree) }
            .map { CalendarBusyUpload.Block(start: iso($0.startDate), end: iso($0.endDate), allDay: $0.isAllDay) }
        return (from, to, blocks)
    }

    static func isOwnCalendar(_ calendar: EKCalendar) -> Bool {
        calendar.type != .birthday && calendar.type != .subscription
    }

    /// Cancelled, declined and tentative events never block a meal; "free" ones only when asked.
    static func countsAsBusy(_ event: EKEvent, countFree: Bool = false) -> Bool {
        if event.status == .canceled || event.status == .tentative { return false }
        if event.availability == .tentative { return false }
        if event.availability == .free && !countFree { return false }
        if let me = event.attendees?.first(where: \.isCurrentUser), me.participantStatus == .declined {
            return false
        }
        return true
    }

    private static func sourceLabel(_ calendar: EKCalendar) -> String {
        switch calendar.type {
        case .birthday: return L10n( "Contacts")
        case .subscription: return L10n( "Subscribed")
        default: return calendar.source?.title ?? L10n( "Calendar")
        }
    }

    private static func hex(_ color: CGColor?) -> UInt32 {
        guard let color,
              let rgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let c = rgb.components, c.count >= 3
        else { return 0xAAA093 }
        let clamp = { (v: CGFloat) in UInt32(max(0, min(255, (v * 255).rounded()))) }
        return clamp(c[0]) << 16 | clamp(c[1]) << 8 | clamp(c[2])
    }

    private static func minutes(from start: Date, to date: Date) -> Int {
        Int((date.timeIntervalSince(start) / 60).rounded())
    }

    private func persistSelection() {
        guard !isPreview else { return }
        defaults.set(Array(selectedIds), forKey: Self.selectedIdsKey)
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    // MARK: Preview

    #if DEBUG
    /// Sample state for `-uiStub calendar-*` screenshots: no EventKit, no network.
    func loadPreview(connected: Bool, keptTomorrow: Bool = false, reconnect: Bool = false) {
        // Stub views are built inside a body; only seed once so observation doesn't loop.
        guard !isPreview else { return }
        isPreview = true
        accessGranted = connected
        accessDenied = false
        enabled = connected || reconnect
        leadMin = 45
        minBlockMin = 60
        workdaysOnly = true
        includeAllDay = false
        countFree = false
        choices = CalendarChoice.samples
        selectedIds = Set(CalendarChoice.samples.filter { !$0.subscribed }.map(\.id))
        preview = .sample
        let sample = CalendarWeekResponse.sample
        week = connected ? (keptTomorrow ? sample.withKeep(date: sample.days[1].date, slot: "lunch", keep: true) : sample) : nil
        mealsMovedThisWeek = week?.movedCount ?? 0
        previewEvents = CalendarDayEvent.samples
    }
    #endif
}

struct CalendarChoice: Identifiable, Hashable {
    let id: String
    let title: String
    let source: String
    let colorHex: UInt32
    let subscribed: Bool
    let eventsThisWeek: Int

    /// "Google · 14 events this week"
    var subtitle: String {
        if subscribed { return source }
        let events = eventsThisWeek == 1 ? L10n("1 event") : L10n("\(eventsThisWeek) events")
        return L10n( "\(source) · \(events) this week")
    }
}

struct CalendarDayEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let calendar: String
    let startMin: Int
    let endMin: Int
    let allDay: Bool
}

struct CalendarBusyUpload: Encodable {
    let from: String
    let to: String
    let blocks: [Block]
    struct Block: Encodable {
        let start: String
        let end: String
        let allDay: Bool
    }
}

struct CalendarStatusResponse: Decodable {
    let enabled: Bool
    let leadMin: Int
    let minBlockMin: Int
    let workdaysOnly: Bool
    let includeAllDay: Bool
    var countFree: Bool?
}

struct CalendarKeepRequest: Encodable {
    let date: String
    let slot: String
    let keep: Bool
}

struct CalendarPreviewResponse: Decodable, Equatable {
    let movedCount: Int
    let moved: [Moved]

    struct Moved: Decodable, Equatable {
        let date: String
        let weekday: Int
        let slot: String
        let usualMin: Int
        let atMin: Int
    }

    /// "Tue lunch, Thu dinner, Fri lunch"
    var summary: String {
        moved.map { "\(CalendarDates.shortWeekday($0.weekday)) \($0.slot)" }.joined(separator: ", ")
    }
}

struct CalendarWeekResponse: Decodable, Equatable {
    let enabled: Bool
    let leadMin: Int
    let minBlockMin: Int
    let workdaysOnly: Bool
    let includeAllDay: Bool
    let countFree: Bool
    let today: String
    var days: [Day]
    var movedCount: Int
    var next: Next?

    struct Day: Decodable, Equatable, Identifiable {
        var id: String { date }
        let date: String
        let weekday: Int
        let blocks: [Block]
        var meals: [Meal]
    }

    struct Block: Decodable, Equatable, Hashable {
        let startMin: Int
        let endMin: Int
        let allDay: Bool
        let counts: Bool
    }

    struct Meal: Decodable, Equatable, Identifiable {
        var id: String { slot }
        let slot: String
        let usualMin: Int
        var atMin: Int
        var moved: Bool
        let reason: String?
        var kept: Bool
        let canKeep: Bool
        let earlyMin: Int?
        let busy: Span?
        let status: String
        let loggedMin: Int?
        let kcal: Int?
    }

    struct Span: Decodable, Equatable, Hashable {
        let startMin: Int
        let endMin: Int
    }

    struct Next: Decodable, Equatable {
        let date: String
        let slot: String
        let usualMin: Int
        var atMin: Int
        let earlyMin: Int
        var kept: Bool
        let reason: String?
        let busy: Span
    }

    func day(_ date: String) -> Day? { days.first { $0.date == date } }

    /// Local optimistic update (and the preview stub's Keep button).
    func withKeep(date: String, slot: String, keep: Bool) -> CalendarWeekResponse {
        var copy = self
        for d in copy.days.indices where copy.days[d].date == date {
            for m in copy.days[d].meals.indices where copy.days[d].meals[m].slot == slot && copy.days[d].meals[m].canKeep {
                var meal = copy.days[d].meals[m]
                meal.kept = keep
                meal.moved = !keep
                meal.atMin = keep ? meal.usualMin : (meal.earlyMin ?? meal.usualMin)
                copy.days[d].meals[m] = meal
            }
        }
        if var next = copy.next, next.date == date, next.slot == slot {
            next.kept = keep
            next.atMin = keep ? next.usualMin : next.earlyMin
            copy.next = next
        }
        copy.movedCount = copy.days.reduce(0) { $0 + $1.meals.filter(\.moved).count }
        return copy
    }
}

/// Local YYYY-MM-DD helpers shared by the calendar screens.
enum CalendarDates {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ iso: String) -> Date? { formatter.date(from: iso) }
    static func iso(_ date: Date) -> String { formatter.string(from: date) }

    static func shortWeekday(_ weekday: Int) -> String {
        AppLanguage.current.calendar.shortStandaloneWeekdaySymbols[((weekday % 7) + 7) % 7]
    }

    /// One letter in English ("M"), the day letter in Hebrew ("ב׳").
    static func narrowWeekday(_ weekday: Int) -> String {
        AppLanguage.current.calendar.veryShortStandaloneWeekdaySymbols[((weekday % 7) + 7) % 7]
    }

    static func longWeekday(_ weekday: Int) -> String {
        AppLanguage.current.calendar.standaloneWeekdaySymbols[((weekday % 7) + 7) % 7]
    }

    static func dayOfMonth(_ iso: String) -> String {
        guard let d = iso.split(separator: "-").last, let n = Int(d) else { return iso }
        return "\(n)"
    }

    /// "Today" / "Tomorrow" / "Thursday".
    static func relativeLabel(_ iso: String, today: String, weekday: Int) -> String {
        if iso == today { return L10n( "Today") }
        if let t = date(today), let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: t), self.iso(tomorrow) == iso {
            return L10n( "Tomorrow")
        }
        return longWeekday(weekday)
    }
}
