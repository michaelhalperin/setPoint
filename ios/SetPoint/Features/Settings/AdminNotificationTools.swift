import SwiftUI
import UserNotifications

/// Admin only: sends each kind of check-in notification to this account's own
/// devices and shows what the server and this phone know about push. Plain
/// English on purpose — it isn't part of the product, so it isn't translated.
struct AdminNotificationTools: View {
    @Environment(AppEnvironment.self) private var env
    @State private var info: Info?
    @State private var sending: String?
    @State private var result: String?
    @State private var permission = "…"

    private struct Info: Decodable {
        struct Kind: Decodable, Identifiable {
            let kind: String
            let label: String
            var id: String { kind }
        }
        struct Token: Decodable {
            let environment: String
            let lastSeenAt: String
        }
        let kinds: [Kind]
        let tokens: [Token]
    }

    private struct Sent: Decodable {
        let sent: Int
        let attempted: Int
        var failed: Int? = nil
        let error: String?
        var removed: Int? = nil
        let tokens: [Info.Token]
    }

    private struct TestBody: Encodable { let kind: String }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(verbatim: "Admin · Notifications")
                .sectionLabelStyle()
                .padding(.top, Space.sm)

            VStack(alignment: .leading, spacing: 6) {
                statusLine("iPhone permission", permission)
                statusLine("iOS gave this phone a token", env.push.hasDeviceToken ? "yes" : "no")
                statusLine("Server has tokens", info.map(tokenSummary) ?? "…")
                Text(verbatim: "TestFlight and App Store builds must show “production”. A “sandbox” token only works for Xcode builds.")
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(radius: Radius.lg)

            Button {
                Task {
                    await env.push.reregister()
                    await reload()
                    result = env.push.hasDeviceToken ? "Asked iOS for a token and sent it to the server." : "iOS did not give a token — check the permission above."
                }
            } label: {
                DestinationRow(title: "Re-register this iPhone", subtitle: "Gets a fresh token and sends it to the server")
            }
            .buttonStyle(PressableCard())

            if let info {
                ForEach(info.kinds) { kind in
                    Button {
                        Task { await send(kind) }
                    } label: {
                        DestinationRow(
                            title: kind.label,
                            subtitle: sending == kind.kind ? "Sending…" : "Send this notification to my devices"
                        )
                    }
                    .buttonStyle(PressableCard())
                    .disabled(sending != nil)
                }
            }

            if let result {
                Text(verbatim: result)
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        .task {
            await refreshPermission()
            await reload()
        }
    }

    private func statusLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: title).font(Typography.data(14)).foregroundStyle(Palette.inkSoft)
            Spacer(minLength: 8)
            Text(verbatim: value).font(Typography.mono(12)).foregroundStyle(Palette.ink)
        }
    }

    private func tokenSummary(_ info: Info) -> String {
        guard !info.tokens.isEmpty else { return "none" }
        let production = info.tokens.filter { $0.environment == "production" }.count
        let sandbox = info.tokens.count - production
        return "\(production) production · \(sandbox) sandbox"
    }

    private func refreshPermission() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .authorized: permission = "allowed"
        case .denied: permission = "denied"
        case .provisional: permission = "provisional"
        case .ephemeral: permission = "ephemeral"
        case .notDetermined: permission = "not asked"
        @unknown default: permission = "unknown"
        }
    }

    private func reload() async {
        info = try? await env.api.get("/api/push-tokens/test")
    }

    private func send(_ kind: Info.Kind) async {
        sending = kind.kind
        defer { sending = nil }
        do {
            let sent: Sent = try await env.api.post("/api/push-tokens/test", TestBody(kind: kind.kind))
            if let error = sent.error {
                result = error == "no_push_token"
                    ? "\(kind.label): the server has no token for this account, so nothing was sent."
                    : "\(kind.label): \(sent.sent) of \(sent.attempted) accepted by Apple — \(error)."
            } else {
                result = "\(kind.label): \(sent.sent) of \(sent.attempted) accepted by Apple. If nothing arrives, the token is for the wrong environment."
            }
            if let removed = sent.removed, removed > 0 { result? += " Removed \(removed) dead token(s)." }
            await reload()
        } catch {
            result = "\(kind.label): couldn’t reach the server (\(error.localizedDescription))."
        }
    }
}
