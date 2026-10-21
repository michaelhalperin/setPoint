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
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                ZStack {
                    ZStack {
                        RadialGradient(colors: [Palette.ember.opacity(0.4), .clear], center: UnitPoint(x: 0.35, y: 0.5), startRadius: 0, endRadius: 200)
                        RadialGradient(colors: [Palette.haze.opacity(0.4), .clear], center: UnitPoint(x: 0.7, y: 0.45), startRadius: 0, endRadius: 200)
                    }
                    .blur(radius: 30)
                    FuelOrb(size: 130, glow: 0.5).offset(x: -45, y: -12)
                    FuelOrb(size: 120, glow: 0.5, haze: true).offset(x: 45, y: 14).blendMode(.screen)
                }
                .frame(height: 230)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    RoundIconButton("xmark", label: "Close") {
                        onSkip()
                        dismiss()
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("SetPoint Pro").sectionLabelStyle()
                    Headline("Fuel the training.", tail: "Meal check-ins stay free.", size: 40)
                }
                .appearIn(0, rise: 16)

                VStack(alignment: .leading, spacing: 12) {
                    feature(symbol: "bolt.heart.fill", title: "Refuel check-ins after every workout")
                    feature(symbol: "dumbbell.fill", title: "More food on training days")
                    feature(symbol: "calendar", title: "Eat before you’re busy")
                }
                .appearIn(1, rise: 16)

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
                    .glass(radius: 20)
                }

                if let error = store.error {
                    Text(error)
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.danger)
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
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
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
        if let days = trialDays { return L10n( "Start \(days)-day free trial") }
        guard let product = store.selectedProduct else { return L10n( "Subscribe") }
        return L10n( "Subscribe for \(product.displayPrice)")
    }

    private var renewalDisclosure: String {
        guard let product = store.selectedProduct else {
            return L10n( "Plans load from the App Store. Check your connection and try again.")
        }
        let unit = store.selectedYearly ? "year" : "month"
        let start = trialDays.map { "After the \($0)-day free trial, " } ?? ""
        return L10n( "\(start)\(product.displayPrice) per \(unit), charged to your Apple ID. Renews automatically unless cancelled at least 24 hours before the period ends. Manage or cancel in Apple ID settings.")
    }

    private func priceLine(_ product: Product?, unit: String) -> String {
        guard let product else { return L10n( "…") }
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
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Palette.hazeSoft)
                .frame(width: 28)
            Text(title)
                .font(Typography.data(15, weight: .regular))
                .foregroundStyle(Palette.ink)
        }
    }

    private func planCard(title: String, price: String, badge: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Typography.data(15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(price)
                    .font(Typography.mono(13))
                    .foregroundStyle(Palette.inkSoft)
                Text(badge ?? " ")
                    .font(Typography.data(11, weight: .regular))
                    .foregroundStyle(Palette.amber)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(
                radius: 20,
                fill: selected ? Color.white.opacity(0.09) : Palette.glass,
                stroke: selected ? Color.white.opacity(0.4) : Palette.hairline
            )
        }
        .buttonStyle(.plain)
    }

    private func timelineRow(_ day: String, _ label: String) -> some View {
        HStack {
            Text(day)
                .font(Typography.mono(13))
                .foregroundStyle(Palette.ink)
            Spacer()
            Text(label)
                .font(Typography.data(14))
                .foregroundStyle(Palette.inkSoft)
        }
    }
}
