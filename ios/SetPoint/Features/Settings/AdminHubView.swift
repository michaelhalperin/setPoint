import SwiftUI

/// Admin only (accounts whose role is ADMIN): one place to check and test the app.
/// Plain English on purpose, like the notification tools — it isn't part of the product.
struct AdminHubView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var status: AdminStatus?
    @State private var error: String?

    var body: some View {
        InnerScreen(spacing: 12, onRefresh: { await load() }) {
            ScreenHeader(label: "Admin")

            if let status {
                overview(status)
            }
            if let error {
                Text(verbatim: error)
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.danger)
            }

            link("People", "Who is in, their role and group, let someone in") { AdminPeopleView() }
            link("Feature flags", "Turn features on or off, or for a group") { AdminFlagsView() }
            link("Live Activity", "Show the lock screen card and Dynamic Island now") { AdminLiveActivityView() }
            link("Notifications", "Send every kind of notification to your phone") {
                InnerScreen(spacing: 12) {
                    ScreenHeader(label: "Notifications")
                    AdminNotificationTools()
                }
            }
            link("Tour and onboarding", "Replay what new people see") {
                InnerScreen(spacing: 12) {
                    ScreenHeader(label: "Tour and onboarding")
                    adminAction("Show tour as first run", "Resets the “seen” flag and starts with the opening prompt") {
                        env.tour.showAsFirstRun(from: .you)
                    }
                    adminAction("Replay the tour", "From the You screen") {
                        env.tour.replay(from: .you)
                    }
                }
            }
            link("Screen previews", "Open any screen with sample data, or start real flows, to test the whole app") { AdminScreenPreviewsView() }
            Text(verbatim: "Invites, emails and the full numbers are on the web admin page.")
                .font(Typography.data(12))
                .foregroundStyle(Palette.inkFaint)
                .padding(.horizontal, 4)
        }
        .task { await load() }
    }

    private func overview(_ s: AdminStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Environment", s.environment)
            row("People", "\(s.users.total) · \(s.users.onboarded) onboarded · \(s.users.pending) waiting")
            row("Invite only", s.switches.inviteOnly ? "on" : "off")
            row("Subscription gate", s.switches.subscriptionGate ? "on" : "off")
            row("AI key set", s.switches.aiConfigured ? "yes" : "no")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: Radius.lg)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: title).font(Typography.data(14)).foregroundStyle(Palette.inkSoft)
            Spacer(minLength: 8)
            Text(verbatim: value).font(Typography.mono(12)).foregroundStyle(Palette.ink)
        }
    }

    private func link<D: View>(_ title: String, _ subtitle: String, @ViewBuilder _ destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination) {
            adminRow(title, subtitle)
        }
        .buttonStyle(PressableCard())
    }

    private func adminAction(_ title: String, _ subtitle: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { adminRow(title, subtitle) }
            .buttonStyle(PressableCard())
    }

    private func adminRow(_ title: String, _ subtitle: String) -> some View {
        HStack(spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title).font(Typography.data(17, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(verbatim: subtitle).font(Typography.data(13)).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkFaint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 22, fill: Color.white.opacity(0.035))
    }

    private func load() async {
        do {
            status = try await env.api.get("/api/admin/status")
            error = nil
        } catch {
            self.error = "Couldn’t load the admin numbers (\(error.localizedDescription))."
        }
    }
}

struct AdminStatus: Decodable {
    struct Switches: Decodable {
        let inviteOnly: Bool
        let subscriptionGate: Bool
        let aiConfigured: Bool
    }
    struct Users: Decodable {
        let total: Int
        let pending: Int
        let onboarded: Int
    }
    let environment: String
    let switches: Switches
    let users: Users
}

// MARK: - People

private struct AdminUser: Decodable, Identifiable {
    struct Onboarding: Decodable { let completedAt: String? }
    struct Count: Decodable { let meals: Int }
    let id: String
    let email: String?
    var role: String
    let group: String?
    var accessGrantedAt: String?
    let onboarding: Onboarding?
    let _count: Count?
}

private struct AdminUsers: Decodable { let users: [AdminUser] }
private struct AdminUserOne: Decodable { let user: AdminUser }
private struct UserPatch: Encodable {
    var role: String?
    var access: Bool?
}

struct AdminPeopleView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var users: [AdminUser] = []
    @State private var loaded = false
    @State private var query = ""
    @State private var error: String?
    @State private var note: String?

    var body: some View {
        InnerScreen(spacing: 10, onRefresh: { await load() }) {
            ScreenHeader(label: "People")
            TextField("Search by email", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(Typography.data(15))
                .padding(14)
                .glass(radius: 18, fill: Color.white.opacity(0.035))
                .onSubmit { Task { await load() } }
            if let note { Text(verbatim: note).font(Typography.data(13)).foregroundStyle(Palette.inkSoft) }
            if let error { Text(verbatim: error).font(Typography.data(13)).foregroundStyle(Palette.danger) }
            if !loaded {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
            }
            ForEach($users) { $user in
                card($user)
            }
        }
        .task { await load() }
    }

    private func card(_ user: Binding<AdminUser>) -> some View {
        let u = user.wrappedValue
        return VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: u.email ?? "no email").font(Typography.data(16, weight: .semibold)).foregroundStyle(Palette.ink)
                .lineLimit(1)
            Text(verbatim: "\(u.role)\(u.group.map { " · \($0)" } ?? "") · \(u._count?.meals ?? 0) meals · \(u.onboarding?.completedAt != nil ? "onboarded" : "not onboarded")\(u.accessGrantedAt == nil ? " · waiting" : "")")
                .font(Typography.mono(11)).foregroundStyle(Palette.inkSoft)
            HStack(spacing: 8) {
                ForEach(["USER", "TRAINER", "ADMIN"], id: \.self) { role in
                    Button { Task { await set(user, UserPatch(role: role)) } } label: {
                        Text(verbatim: role)
                            .font(Typography.mono(10))
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(u.role == role ? Palette.ember.opacity(0.28) : Color.white.opacity(0.06), in: Capsule())
                            .foregroundStyle(u.role == role ? Palette.amber : Palette.inkSoft)
                    }
                    .buttonStyle(.plain)
                }
                if u.accessGrantedAt == nil {
                    Button { Task { await set(user, UserPatch(access: true)) } } label: {
                        Text(verbatim: "LET IN")
                            .font(Typography.mono(10))
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(Palette.ember.opacity(0.28), in: Capsule())
                            .foregroundStyle(Palette.amber)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 22, fill: Color.white.opacity(0.035))
    }

    private func load() async {
        do {
            let q = query.trimmingCharacters(in: .whitespaces)
            let res: AdminUsers = try await env.api.get("/api/admin/users", query: q.isEmpty ? [:] : ["q": q])
            users = res.users
            error = nil
        } catch {
            self.error = "Couldn’t load people (\(error.localizedDescription))."
        }
        loaded = true
    }

    private func set(_ user: Binding<AdminUser>, _ patch: UserPatch) async {
        do {
            let res: AdminUserOne = try await env.api.patch("/api/admin/users/\(user.wrappedValue.id)", patch)
            user.wrappedValue = res.user
            note = "Saved."
        } catch {
            note = "Couldn’t save (\(error.localizedDescription))."
        }
    }
}

// MARK: - Flags

private struct AdminFlag: Decodable, Identifiable {
    struct Override: Decodable {
        let enabled: Bool
        var groups: [String]? = nil
        var roles: [String]? = nil
        var userIds: [String]? = nil

        /// Only some groups, roles or people have it.
        var limited: Bool { !enabled && !((groups ?? []).isEmpty && (roles ?? []).isEmpty && (userIds ?? []).isEmpty) }
    }
    let key: String
    let note: String?
    /// What it is without an override.
    var `default`: Bool? = nil
    var override: Override?
    var id: String { key }

    /// On for everyone right now.
    var isOn: Bool { override?.enabled ?? `default` ?? false }

    var status: String {
        guard let override else { return `default` == true ? "on by default" : "off by default" }
        if override.limited { return "overridden · only some people" }
        return override.enabled ? "overridden · on for everyone" : "overridden · off for everyone"
    }
}

private struct AdminFlags: Decodable { let flags: [AdminFlag] }
private struct FlagPatch: Encodable { let enabled: Bool }

struct AdminFlagsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var flags: [AdminFlag] = []
    @State private var note: String?

    var body: some View {
        InnerScreen(spacing: 10, onRefresh: { await load() }) {
            ScreenHeader(label: "Feature flags")
            if let note { Text(verbatim: note).font(Typography.data(13)).foregroundStyle(Palette.inkSoft) }
            ForEach(flags) { flag in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: flag.key).font(Typography.data(16, weight: .semibold)).foregroundStyle(Palette.ink)
                        Text(verbatim: flag.status)
                            .font(Typography.mono(10)).foregroundStyle(Palette.inkFaint)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { flag.isOn },
                        set: { value in Task { await set(flag.key, value) } }
                    ))
                    .labelsHidden()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(radius: 22, fill: Color.white.opacity(0.035))
            }
            Text(verbatim: "Switches here turn a flag on for everyone. Groups and single people are set on the web admin page.")
                .font(Typography.data(12)).foregroundStyle(Palette.inkFaint)
        }
        .task { await load() }
    }

    private func load() async {
        if let res: AdminFlags = try? await env.api.get("/api/admin/flags") { flags = res.flags }
    }

    /// The switch moves at once; the save happens behind it and undoes the move only if it fails.
    private func set(_ key: String, _ on: Bool) async {
        guard let index = flags.firstIndex(where: { $0.key == key }) else { return }
        let before = flags[index].override
        withAnimation(Motion.snappy) { flags[index].override = .init(enabled: on) }
        UISelectionFeedbackGenerator().selectionChanged()
        do {
            try await env.api.put("/api/admin/flags/\(key)", FlagPatch(enabled: on))
            note = "\(key) is now \(on ? "on" : "off") for everyone."
            Task { await env.flags.refresh(using: env.api) }
        } catch {
            if let i = flags.firstIndex(where: { $0.key == key }) {
                withAnimation(Motion.snappy) { flags[i].override = before }
            }
            note = "Couldn’t save \(key) (\(error.localizedDescription)). It was put back."
        }
    }
}

/// Starts a sample Live Activity so the card can be checked without waiting for a late meal.
struct AdminLiveActivityView: View {
    @State private var result: String?

    var body: some View {
        InnerScreen(spacing: 12) {
            ScreenHeader(label: "Live Activity")
            Text(verbatim: "Starts a sample card. Lock the phone to see it on the lock screen, or press Home to see the Dynamic Island. Live Activities must be allowed in iPhone Settings → SetPoint.")
                .font(Typography.data(13))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if let result {
                Text(verbatim: result).font(Typography.data(13)).foregroundStyle(Palette.amber)
            }
            action("Meal is late", "Ember card: Lunch, 700 kcal") { start(refuel: false) }
            action("Refuel after training", "Indigo card: 450 kcal") { start(refuel: true) }
            action("End it", "Removes the sample card") {
                LiveActivityController.shared.end()
                result = "Ended."
            }
        }
    }

    private func start(refuel: Bool) {
        result = LiveActivityController.shared.startTest(refuel: refuel) ?? "Started."
    }

    private func action(_ title: String, _ subtitle: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: title).font(Typography.data(17, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text(verbatim: subtitle).font(Typography.data(13)).foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(radius: 22, fill: Color.white.opacity(0.035))
        }
        .buttonStyle(PressableCard())
    }
}
