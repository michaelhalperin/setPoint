import EventKit
import Foundation
import Observation

/// Reads EventKit on-device and uploads busy intervals only — never titles.
@MainActor
@Observable
final class CalendarManager {
    static let shared = CalendarManager()
    static let selectedIdsKey = "com.setpoint.app.calendar.selectedIds"

    var api: APIClient?
    private(set) var accessGranted = false
    private(set) var calendars: [EKCalendar] = []
    var selectedIds: Set<String>
    private(set) var lastError: String?
    private(set) var uploading = false
    private(set) var mealsMovedThisWeek = 0
    private(set) var week: [CalendarWeekBlock] = []
    var leadMin = 45
    var minBlockMin = 60
    var workdaysOnly = true
    var includeAllDay = false
    var enabled = false

    private let store = EKEventStore()
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.array(forKey: Self.selectedIdsKey) as? [String] ?? []
        self.selectedIds = Set(stored)
    }

    var connected: Bool { accessGranted && enabled }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.uploadBusy() }
        }
    }

    func requestAccess() async -> Bool {
        lastError = nil
        do {
            accessGranted = try await store.requestFullAccessToEvents()
        } catch {
            lastError = UserFacingError.message(for: error, fallback: "Couldn't open Calendar access.")
            accessGranted = false
        }
        if accessGranted { refreshCalendars() }
        return accessGranted
    }

    func refreshCalendars() {
        calendars = store.calendars(for: .event).sorted { $0.title < $1.title }
        if selectedIds.isEmpty {
            // Birthdays and subscribed calendars (holidays, sports) aren't the user's own time.
            let own = calendars.filter { Self.isOwnCalendar($0) }
            selectedIds = Set((own.isEmpty ? calendars : own).map(\.calendarIdentifier))
            persistSelection()
        }
    }

    func toggleCalendar(_ id: String) {
        var next = selectedIds
        if next.contains(id) {
            if next.count > 1 { next.remove(id) }
        } else {
            next.insert(id)
        }
        selectedIds = next
        persistSelection()
        Task { await uploadBusy() }
    }

    func connect() async {
        guard await requestAccess() else { return }
        enabled = true
        persistPrefs()
        await uploadBusy()
        await refreshStatus()
    }

    func disconnect() async {
        enabled = false
        persistPrefs()
        try? await api?.delete("/api/calendar")
        week = []
        mealsMovedThisWeek = 0
    }

    func persistPrefs() {
        Task {
            try? await api?.patch(
                "/api/settings",
                SettingsPatch(calendar: .init(
                    enabled: enabled,
                    leadMin: leadMin,
                    minBlockMin: minBlockMin,
                    workdaysOnly: workdaysOnly,
                    includeAllDay: includeAllDay
                ))
            )
        }
    }

    func refreshStatus() async {
        guard let status: CalendarStatusResponse = try? await api?.get("/api/calendar") else { return }
        enabled = status.enabled
        leadMin = status.leadMin
        minBlockMin = status.minBlockMin
        workdaysOnly = status.workdaysOnly
        includeAllDay = status.includeAllDay
        mealsMovedThisWeek = status.mealsMovedThisWeek
        week = status.week
    }

    func uploadBusy(now: Date = .now) async {
        guard accessGranted, enabled, let api else { return }
        uploading = true
        defer { uploading = false }
        // From the start of today, so an all-day event today isn't clipped into "busy from now".
        let from = Calendar.current.startOfDay(for: now)
        let to = from.addingTimeInterval(40 * 3600)
        let cals = calendars.filter { selectedIds.contains($0.calendarIdentifier) }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: cals.isEmpty ? nil : cals)
        let events = store.events(matching: predicate).filter(Self.countsAsBusy)
        let blocks = events.map { event in
            CalendarBusyUpload.Block(start: iso(event.startDate), end: iso(event.endDate), allDay: event.isAllDay)
        }
        do {
            try await api.put("/api/calendar/busy", CalendarBusyUpload(from: iso(from), to: iso(to), blocks: blocks))
        } catch {
            lastError = UserFacingError.message(for: error, fallback: "Couldn't update busy times.")
        }
    }

    static func isOwnCalendar(_ calendar: EKCalendar) -> Bool {
        calendar.type != .birthday && calendar.type != .subscription
    }

    /// Events marked "free", cancelled, or declined don't block a meal.
    static func countsAsBusy(_ event: EKEvent) -> Bool {
        if event.availability == .free || event.status == .canceled { return false }
        if let me = event.attendees?.first(where: \.isCurrentUser), me.participantStatus == .declined {
            return false
        }
        return true
    }

    private func persistSelection() {
        defaults.set(Array(selectedIds), forKey: Self.selectedIdsKey)
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
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
    let mealsMovedThisWeek: Int
    var week: [CalendarWeekBlock] = []
}

struct CalendarWeekBlock: Decodable, Hashable {
    let date: String
    let startMin: Int
    let endMin: Int
}
