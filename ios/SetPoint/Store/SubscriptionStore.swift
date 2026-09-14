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
    /// Ties StoreKit purchases to this SetPoint account.
    var appAccountToken: String? = nil
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
    /// Free-trial eligibility per product id (StoreKit decides — a lapsed trialist isn't eligible again).
    private(set) var trialEligible: [String: Bool] = [:]

    private var appAccountToken: UUID?
    private var updatesTask: Task<Void, Never>?

    var selectedProduct: Product? { selectedYearly ? yearly : monthly }

    func isTrialEligible(_ productID: String) -> Bool { trialEligible[productID] == true }

    /// The selected product's free trial, when this user can still get it.
    var selectedTrial: Product.SubscriptionOffer? {
        guard let product = selectedProduct,
              trialEligible[product.id] == true,
              let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial
        else { return nil }
        return offer
    }

    /// Renewals, refunds and Ask to Buy approvals arrive here, even while the app was closed.
    func listenForTransactions(using api: APIClient) {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update, api: api)
            }
        }
    }

    func refresh(using api: APIClient) async {
        listenForTransactions(using: api)
        if let status: SubscriptionStatusPayload = try? await api.get("/api/subscription") {
            apply(status)
            // Renewals the server hasn't heard about yet (e.g. notifications not delivered).
            if !status.entitled || Self.expiresSoon(status.expiresAt) {
                await syncCurrentEntitlements(using: api)
            }
        }
        loaded = true
        if let products = try? await Product.products(for: SubscriptionProductID.all) {
            yearly = products.first { $0.id == SubscriptionProductID.yearly }
            monthly = products.first { $0.id == SubscriptionProductID.monthly }
            for product in products {
                if let subscription = product.subscription {
                    trialEligible[product.id] = await subscription.isEligibleForIntroOffer
                }
            }
        }
    }

    func purchase(using api: APIClient) async -> Bool {
        guard let product = selectedProduct else {
            error = "Plans aren't available right now. Try again in a moment."
            return false
        }
        purchasing = true
        error = nil
        defer { purchasing = false }
        let startsTrial = selectedTrial != nil
        do {
            var options: Set<Product.PurchaseOption> = []
            if let token = appAccountToken { options.insert(.appAccountToken(token)) }
            let result = try await product.purchase(options: options)
            switch result {
            case let .success(verification):
                let ok = try await verifyAndFinish(verification, api: api)
                if ok, startsTrial { await Self.scheduleTrialReminder(trialDays: Self.days(in: selectedTrial?.period)) }
                return ok
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            self.error = UserFacingError.message(for: error, fallback: "Couldn't complete the purchase.")
            return false
        }
    }

    func restore(using api: APIClient) async {
        error = nil
        do {
            try await AppStore.sync()
            await syncCurrentEntitlements(using: api)
            await refresh(using: api)
            if !entitled { error = "No active subscription found for this Apple ID." }
        } catch {
            self.error = UserFacingError.message(for: error, fallback: "Couldn't restore.")
        }
    }

    // MARK: - Private

    private func apply(_ status: SubscriptionStatusPayload) {
        entitled = status.entitled
        if let raw = status.appAccountToken, let token = UUID(uuidString: raw) {
            appAccountToken = token
        }
    }

    private func syncCurrentEntitlements(using api: APIClient) async {
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  SubscriptionProductID.all.contains(transaction.productID)
            else { continue }
            _ = try? await verifyAndFinish(result, api: api)
        }
    }

    private func handle(_ update: VerificationResult<Transaction>, api: APIClient) async {
        guard case let .verified(transaction) = update,
              SubscriptionProductID.all.contains(transaction.productID)
        else { return }
        _ = try? await verifyAndFinish(update, api: api)
    }

    /// The server verifies Apple's signature and stores the subscription; only then is the transaction finished.
    private func verifyAndFinish(_ verification: VerificationResult<Transaction>, api: APIClient) async throws -> Bool {
        guard case let .verified(transaction) = verification else {
            error = "The App Store couldn't confirm this purchase."
            return false
        }
        let status: SubscriptionStatusPayload = try await api.post(
            "/api/subscription/verify",
            SubscriptionVerifyRequest(transactionJws: verification.jwsRepresentation)
        )
        apply(status)
        await transaction.finish()
        return status.entitled
    }

    private static func expiresSoon(_ iso: String?) -> Bool {
        guard let iso, let date = ISO8601DateFormatter.withFractionalSeconds.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso)
        else { return true }
        return date.timeIntervalSinceNow < 86_400
    }

    private static func days(in period: Product.SubscriptionPeriod?) -> Int {
        guard let period else { return 7 }
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return 7
        }
    }

    static func scheduleTrialReminder(trialDays: Int) async {
        guard trialDays >= 3 else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Two days left on your trial"
        content.body = "SetPoint bills on day \(trialDays) unless you cancel in Apple ID settings."
        content.sound = .default
        let fire = Calendar.current.date(byAdding: .day, value: trialDays - 2, to: Date()) ?? Date()
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: fire)
        comps.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "setpoint.trial.reminder", content: content, trigger: trigger)
        try? await center.add(request)
    }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
