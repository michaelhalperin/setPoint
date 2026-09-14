import Foundation
import Observation
import StoreKit
import UserNotifications

enum SubscriptionProductID {
    static let yearly = "setpoint.yearly"
    static let monthly = "setpoint.monthly"
    static var all: [String] { [yearly, monthly] }
}

struct SubscriptionStatusPayload: Decodable, Equatable {
    let entitled: Bool
    var status: String? = nil
    var expiresAt: String? = nil
    var productId: String? = nil
}

struct SubscriptionVerifyRequest: Encodable {
    let transactionJws: String
}

@MainActor
@Observable
final class SubscriptionStore {
    var entitled = true
    var loaded = false
    var purchasing = false
    var error: String?
    var selectedYearly = true
    var yearly: Product?
    var monthly: Product?

    func refresh(using api: APIClient) async {
        if let status: SubscriptionStatusPayload = try? await api.get("/api/subscription") {
            entitled = status.entitled
        }
        loaded = true
        if let products = try? await Product.products(for: SubscriptionProductID.all) {
            yearly = products.first { $0.id == SubscriptionProductID.yearly }
            monthly = products.first { $0.id == SubscriptionProductID.monthly }
        }
    }

    func purchase(using api: APIClient) async -> Bool {
        guard let product = selectedYearly ? yearly : monthly else {
            error = "Products aren't available yet."
            return false
        }
        purchasing = true
        error = nil
        defer { purchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case let .success(verification):
                let jws = verification.jwsRepresentation
                let status: SubscriptionStatusPayload = try await api.post(
                    "/api/subscription/verify",
                    SubscriptionVerifyRequest(transactionJws: jws)
                )
                entitled = status.entitled
                if selectedYearly { await Self.scheduleTrialDay5Reminder() }
                return status.entitled
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            self.error = UserFacingError.message(for: error, fallback: "Couldn't start the trial.")
            return false
        }
    }

    func restore(using api: APIClient) async {
        do {
            try await AppStore.sync()
            for await result in Transaction.currentEntitlements {
                let jws = result.jwsRepresentation
                if let status: SubscriptionStatusPayload = try? await api.post(
                    "/api/subscription/verify",
                    SubscriptionVerifyRequest(transactionJws: jws)
                ) {
                    entitled = status.entitled
                    if status.entitled { return }
                }
            }
            await refresh(using: api)
        } catch {
            self.error = UserFacingError.message(for: error, fallback: "Couldn't restore.")
        }
    }

    static func scheduleTrialDay5Reminder() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Two days left on your trial"
        content.body = "SetPoint bills on day 7 unless you cancel in Apple ID settings."
        content.sound = .default
        let fire = Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date()
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: fire)
        comps.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "setpoint.trial.day5", content: content, trigger: trigger)
        try? await center.add(request)
    }
}
