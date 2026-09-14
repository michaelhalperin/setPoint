import StoreKit
import SwiftUI

struct PaywallView: View {
    var onFinished: () -> Void = {}
    var onSkip: () -> Void = {}

    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    private var store: SubscriptionStore { env.subscription }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Stay covered.")
                    .font(Typography.display(40))
                    .foregroundStyle(Palette.background)
                Text("Check-ins, calendar, training and appetite.")
                    .font(Typography.data(16, weight: .semibold))
                    .foregroundStyle(Palette.onAccentVoice)
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.accent)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    feature(symbol: "bell.fill", title: "Check-ins when a meal slips")
                    feature(symbol: "calendar", title: "Eat before you're busy")
                    feature(symbol: "dumbbell.fill", title: "Fuel around training")

                    HStack(spacing: Space.sm) {
                        planCard(
                            title: "Yearly",
                            price: priceLine(store.yearly, unit: "year"),
                            badge: trialBadge(store.yearly),
                            selected: store.selectedYearly
                        ) { store.selectedYearly = true }
                        planCard(
                            title: "Monthly",
                            price: priceLine(store.monthly, unit: "month"),
                            badge: trialBadge(store.monthly),
                            selected: !store.selectedYearly
                        ) { store.selectedYearly = false }
                    }

                    // The trial timeline only when the selected plan really starts one for this Apple ID.
                    if let days = trialDays {
                        VStack(alignment: .leading, spacing: 8) {
                            timelineRow("Today", "Trial starts")
                            if days >= 3 { timelineRow("Day \(days - 2)", "Reminder") }
                            timelineRow("Day \(days)", "Billed")
                        }
                        .padding(16)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    if let error = store.error {
                        Text(error)
                            .font(Typography.data(13, weight: .semibold))
                            .foregroundStyle(Palette.accentDeep)
                    }

                    ActionButton(
                        title: purchaseTitle,
                        busy: store.purchasing,
                        busyTitle: "Starting"
                    ) {
                        Task {
                            if await store.purchase(using: env.api) {
                                onFinished()
                                dismiss()
                            }
                        }
                    }
                    .disabled(store.selectedProduct == nil)

                    Text(renewalDisclosure)
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button("Restore") {
                            Task { await store.restore(using: env.api) }
                        }
                        Spacer()
                        Button("Terms") {
                            openURL(APIConfig.baseURL.appending(path: "terms"))
                        }
                        Spacer()
                        Button("Privacy") {
                            openURL(APIConfig.baseURL.appending(path: "privacy"))
                        }
                        Spacer()
                        Button("Not now") {
                            onSkip()
                            dismiss()
                        }
                    }
                    .font(Typography.data(14, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.bottom, Space.lg)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.md)
            }
            .background(Palette.background)
        }
        .background(Palette.background.ignoresSafeArea())
        .task { await store.refresh(using: env.api) }
    }

    private var trialDays: Int? {
        guard let period = store.selectedTrial?.period else { return nil }
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return nil
        }
    }

    private var purchaseTitle: String {
        if let days = trialDays { return "Start \(days)-day free trial" }
        guard let product = store.selectedProduct else { return "Subscribe" }
        return "Subscribe for \(product.displayPrice)"
    }

    private var renewalDisclosure: String {
        guard let product = store.selectedProduct else {
            return "Plans load from the App Store. Check your connection and try again."
        }
        let unit = store.selectedYearly ? "year" : "month"
        let start = trialDays.map { "After the \($0)-day free trial, " } ?? ""
        return "\(start)\(product.displayPrice) per \(unit), charged to your Apple ID. Renews automatically unless cancelled at least 24 hours before the period ends. Manage or cancel in Apple ID settings."
    }

    private func priceLine(_ product: Product?, unit: String) -> String {
        guard let product else { return "—" }
        return "\(product.displayPrice)/\(unit)"
    }

    private func trialBadge(_ product: Product?) -> String? {
        guard let product,
              let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial,
              store.isTrialEligible(product.id)
        else { return nil }
        let days = offer.period.unit == .week ? offer.period.value * 7 : offer.period.value
        return offer.period.unit == .day || offer.period.unit == .week ? "\(days) DAYS FREE" : "FREE TRIAL"
    }

    private func feature(symbol: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 28)
            Text(title)
                .font(Typography.data(16, weight: .semibold))
                .foregroundStyle(Palette.ink)
        }
    }

    private func planCard(title: String, price: String, badge: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                if let badge {
                    Text(badge)
                        .font(Typography.data(10, weight: .heavy))
                        .foregroundStyle(Palette.background)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Palette.accent, in: Capsule())
                }
                Text(title)
                    .font(Typography.data(16, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text(price)
                    .font(Typography.data(20, weight: .bold))
                    .foregroundStyle(Palette.ink)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(selected ? Palette.accent : Palette.hairline, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func timelineRow(_ day: String, _ label: String) -> some View {
        HStack {
            Text(day)
                .font(Typography.data(14, weight: .bold))
                .foregroundStyle(Palette.ink)
            Spacer()
            Text(label)
                .font(Typography.data(14))
                .foregroundStyle(Palette.inkSoft)
        }
    }
}
