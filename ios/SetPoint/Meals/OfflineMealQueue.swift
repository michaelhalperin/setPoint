import Foundation

/// Text meals that couldn't reach the API because there was no connection.
/// A missing log makes a meal look skipped and fires a false check-in, so they
/// wait here and go out on the next load — with the time they were eaten and
/// the same client id, so a request that did land isn't stored twice.
enum OfflineMealQueue {
    struct Item: Codable, Identifiable, Equatable {
        /// Sent as `clientId`; the server returns the existing meal on a repeat.
        var id: String
        var text: String
        /// When the meal was eaten — never the time it finally uploads.
        var loggedAt: Date
    }

    private static let key = "com.setpoint.app.offlineMeals.v2"

    /// Errors that mean "no connection", not "the server said no".
    static func isOffline(_ error: Error) -> Bool {
        guard case let APIError.transport(underlying) = error,
              let urlError = underlying as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
             .callIsActive, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    static func all(in store: UserDefaults = .standard) -> [Item] {
        guard let data = store.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: data)) ?? []
    }

    static func enqueue(_ item: Item, in store: UserDefaults = .standard) {
        var items = all(in: store)
        items.removeAll { $0.id == item.id }
        items.append(item)
        save(items, in: store)
    }

    static func clear(in store: UserDefaults = .standard) {
        store.removeObject(forKey: key)
        store.removeObject(forKey: "com.setpoint.app.offlineMeals") // v1 format
    }

    /// Sends queued meals oldest first. Stops at the first connection or server
    /// problem (keeps the rest for later); drops a meal the server rejects
    /// outright so one bad entry can't block the queue forever. Returns how
    /// many were delivered.
    @discardableResult
    static func flush(using api: APIClient, store: UserDefaults = .standard) async -> Int {
        var delivered = 0
        for item in all(in: store).sorted(by: { $0.loggedAt < $1.loggedAt }) {
            do {
                let _: LogMealResponse = try await api.post("/api/meals", request(for: item))
                remove(id: item.id, in: store)
                delivered += 1
            } catch let APIError.http(status, _) where (400 ..< 500).contains(status)
                && ![408, 409, 429].contains(status) {
                remove(id: item.id, in: store)
            } catch {
                break
            }
        }
        return delivered
    }

    static func request(for item: Item) -> LogMealRequest {
        LogMealRequest(
            text: item.text,
            loggedAt: ISO8601DateFormatter().string(from: item.loggedAt),
            clientId: item.id
        )
    }

    private static func remove(id: String, in store: UserDefaults) {
        save(all(in: store).filter { $0.id != id }, in: store)
    }

    private static func save(_ items: [Item], in store: UserDefaults) {
        if let data = try? JSONEncoder().encode(items) {
            store.set(data, forKey: key)
        }
    }
}
