import SwiftUI

/// Admin → Screen previews: every screen of the app, one tap away, so the whole app can be tested
/// from one list. The sample-data screens never touch the account; the "real account" ones start
/// real flows. Plain English on purpose — it isn't part of the product.
struct AdminScreenPreviewsView: View {
    @State private var shown: StubItem?
    @State private var real: RealPreview?
    @State private var query = ""
    @State private var open: Set<String> = []

    private struct StubItem: Identifiable {
        let id: String
        let title: String
    }

    private enum RealPreview: String, Identifiable {
        case onboarding, mealConfirm, checkInToday, checkInSheet, conversation
        var id: String { rawValue }
    }

    private struct Group: Identifiable {
        let title: String
        let items: [(name: String, title: String)]
        var id: String { title }
    }

    private static let groups: [Group] = [
        Group(title: "Today", items: [
            ("home", "A check-in is waiting"), ("home-onpace", "On pace"), ("home-over", "Over target"),
            ("home-missed", "A missed meal"), ("home-snoozed", "Snoozed"), ("home-talk", "Let’s talk"),
            ("home-topup", "Top it up"), ("home-light", "A light meal"), ("home-close", "Closing the day"),
            ("home-busy", "A busy day"), ("home-training", "A training day"), ("home-appetite-low", "Low appetite"),
            ("home-appetite-ask", "Asking about appetite"), ("home-quiet", "Quiet mode"), ("home-empty", "An empty day"),
            ("home-loading", "Loading"), ("home-error", "Offline error"), ("home-stale", "Out of date"),
        ]),
        Group(title: "Check-in", items: [
            ("prescription", "Check-in sheet"), ("checkin-smaller", "Check-in sheet · drink"), ("snooze", "Snooze sheet"),
            ("refuel", "Refuel after training"), ("conversation", "Conversation"), ("conversation-resolved", "Conversation · resolved"),
        ]),
        Group(title: "Logging", items: [
            ("log-meal", "Log sheet"), ("log-typing", "Typing a meal"), ("log-working", "Working it out"),
            ("log-offline", "Saved for later (offline)"), ("log-failed", "Couldn’t log"), ("log-meal-parsing", "Reading a photo"),
            ("log-meal-result", "Photo result"), ("log-quick", "Quick log"), ("log-scan", "Scan mode"),
            ("scanner", "Barcode scanner"), ("scanner-looking", "Scanner · looking up"), ("scanner-found", "Scanner · found"),
            ("scanner-miss", "Scanner · not found"), ("scanner-label", "Scanner · label photo"),
            ("meal-detail", "Meal detail"), ("fix-meal", "Fix a meal"), ("saved-meal", "New saved meal"),
        ]),
        Group(title: "Train and Progress", items: [
            ("training", "Train"), ("settlement", "Week"), ("settlement-weigh-in", "Weigh-in"),
            ("settlement-empty", "Empty week"), ("week-one", "First week"), ("settlement-loading", "Week loading"), ("burn", "Burn"), ("burn-loading", "Burn · loading"),
        ]),
        Group(title: "You and settings", items: [
            ("settings", "You"), ("settings-loading", "You · loading"), ("settings-goal", "Edit plan"), ("settings-meal-times", "Meal times"),
            ("settings-meal-times-weekends", "Meal times · weekends"), ("settings-appetite", "Appetite"),
            ("settings-foods", "My kitchen"), ("settings-saved-meals", "My meals"), ("settings-health", "Apple Health"),
            ("settings-health-write", "Apple Health · writing"), ("settings-account", "Account"), ("settings-delete", "Delete account"),
        ]),
        Group(title: "Order and assistant", items: [
            ("order-nearby", "Order nearby"), ("assistant", "Nutrition assistant"), ("assistant-empty", "Assistant · empty"),
            ("assistant-consent", "Assistant · consent"), ("paywall", "Paywall"),
        ]),
        Group(title: "Welcome and onboarding", items: [
            ("welcome", "Welcome"), ("intro-gap", "Intro · the gap"), ("intro-plates", "Intro · plates"),
            ("intro-nudge", "Intro · nudge"), ("intro-topup", "Intro · top-up"), ("intro-close", "Intro · close"),
            ("invite", "Invite code"), ("onboarding-goal", "Goal"), ("onboarding-health", "Health"),
            ("onboarding-about", "About you"), ("onboarding-target", "Target"), ("onboarding-appetite", "Appetite"),
            ("onboarding-training", "Training"), ("onboarding-rhythm", "Meal times"), ("onboarding-restrictions", "Foods"),
            ("onboarding-safety", "Safety"), ("onboarding-building", "Building the plan"), ("onboarding-reveal", "Your plan"),
            ("onboarding-reach", "Reach"), ("onboarding-save", "Save"), ("onboarding-covered", "Covered"),
        ]),
        Group(title: "Tour and widgets", items: [
            ("tour-today", "Tour · Today"), ("tour-train", "Tour · Train"), ("tour-progress", "Tour · Progress"),
            ("tour-you", "Tour · You"), ("widgets", "Widgets"),
        ]),
    ]

    var body: some View {
        InnerScreen(spacing: 12) {
            ScreenHeader(label: "Screen previews")

            Text(verbatim: "The first section starts real flows on your account. Every group below uses sample data and changes nothing. Close a preview with the button at the top.")
                .font(Typography.data(13))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Search screens", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(Typography.data(15))
                .padding(14)
                .glass(radius: 18, fill: Color.white.opacity(0.035))

            if query.isEmpty {
                realSection
            }

            ForEach(Self.groups) { group in
                section(group)
            }
        }
        .fullScreenCover(item: $shown) { item in
            AdminStubHost(name: item.id, title: item.title)
        }
        .fullScreenCover(item: $real) { item in
            switch item {
            case .onboarding: DevOnboardingPreview()
            case .mealConfirm: DevMealConfirmPreview()
            case .checkInToday: DevCheckInTodayPreview()
            case .checkInSheet: DevCheckInPreview()
            case .conversation: DevConversationPreview()
            }
        }
    }

    private var realSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "With your real account").sectionLabelStyle().padding(.top, 6)
            realRow("Onboarding", "Walk through the real flow", .onboarding)
            realRow("Meal confirm", "Demo data", .mealConfirm)
            realRow("Check-in on Today", "Starts a real check-in", .checkInToday)
            realRow("Check-in sheet", "Starts a real check-in", .checkInSheet)
            realRow("Let’s talk", "Starts a real conversation", .conversation)
        }
    }

    private func realRow(_ title: String, _ subtitle: String, _ item: RealPreview) -> some View {
        Button { real = item } label: { row(title, subtitle) }
            .buttonStyle(PressableCard())
    }

    @ViewBuilder
    private func section(_ group: Group) -> some View {
        let items = group.items.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || group.title.localizedCaseInsensitiveContains(query) }
        if !items.isEmpty {
            let expanded = !query.isEmpty || open.contains(group.title)
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(Motion.settle) {
                        if open.contains(group.title) { open.remove(group.title) } else { open.insert(group.title) }
                    }
                } label: {
                    HStack {
                        Text(verbatim: group.title).font(Typography.data(17, weight: .semibold)).foregroundStyle(Palette.ink)
                        Text(verbatim: "\(items.count)").font(Typography.mono(11)).foregroundStyle(Palette.inkFaint)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass(radius: 22, fill: Color.white.opacity(0.035))
                }
                .buttonStyle(PressableCard())

                if expanded {
                    VStack(spacing: 6) {
                        ForEach(items, id: \.name) { item in
                            Button { shown = StubItem(id: item.name, title: item.title) } label: {
                                HStack {
                                    Text(verbatim: item.title).font(Typography.data(15)).foregroundStyle(Palette.ink)
                                    Spacer(minLength: 8)
                                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 48)
                                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(PressableCard())
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private func row(_ title: String, _ subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title).font(Typography.data(17, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(verbatim: subtitle).font(Typography.data(13)).foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 22, fill: Color.white.opacity(0.035))
    }
}

/// One sample-data screen, full screen, with a way out.
private struct AdminStubHost: View {
    let name: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            if let stub = DebugPreviewStub.named(name) {
                stub.view
            } else {
                Text(verbatim: "No preview for “\(name)”.").foregroundStyle(Palette.inkSoft)
            }
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        Text(verbatim: title).font(Typography.data(12, weight: .medium)).lineLimit(1)
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18)))
                }
                .accessibilityLabel("Close preview")
                Spacer()
            }
            .padding(.leading, 12)
            .padding(.top, 6)
            .zIndex(10)
        }
        .background(Palette.background.ignoresSafeArea())
    }
}
