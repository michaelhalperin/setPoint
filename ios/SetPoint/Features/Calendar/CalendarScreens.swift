import SwiftUI

/// You → Calendar. Connected users land on the week; everyone else on connect → pick.
struct CalendarSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var picking = false

    var body: some View {
        Group {
            if env.calendar.connected {
                CalendarWeekView()
            } else {
                CalendarConnectView(onAllowed: { picking = true })
            }
        }
        .navigationDestination(isPresented: $picking) {
            CalendarPickView(onConnected: { picking = false })
        }
        .task {
            env.calendar.start()
            await env.calendar.sync()
        }
    }
}

// MARK: B0 · Connect

struct CalendarConnectView: View {
    var onAllowed: () -> Void = {}

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var asking = false

    var body: some View {
        let reconnecting = env.calendar.needsReconnect
        SettingsScreen(
            title: reconnecting ? "Reconnect calendar" : "Calendar",
            subtitle: reconnecting
                ? "Your rules are saved. iPhone just needs Calendar access again."
                : "Eat before the busy stretch."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                whatItDoes.appearIn(2)
                if !reconnecting { whatISee.appearIn(3) }
                VStack(spacing: 14) {
                    if env.calendar.accessDenied {
                        Text("Calendar access is off for SetPoint. Turn it on in Settings, then come back.")
                            .font(Typography.data(14))
                            .foregroundStyle(Palette.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        ActionButton(title: "Open Settings") { env.calendar.openSystemSettings() }
                    } else {
                        ActionButton(
                            title: reconnecting ? "Reconnect" : "Allow Calendar access",
                            busy: asking,
                            busyTitle: reconnecting ? "Reconnecting" : "Asking"
                        ) {
                            Task { await allow() }
                        }
                    }
                    Button("Not now") { dismiss() }
                        .font(Typography.data(15, weight: .bold))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    if let message = env.calendar.lastError {
                        SettingsErrorBanner(message: message)
                    }
                }
                .padding(.top, 8)
                .appearIn(4)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            env.calendar.refreshAuthorization()
        }
    }

    private func allow() async {
        asking = true
        defer { asking = false }
        if env.calendar.needsReconnect {
            // Still on in SetPoint: once iOS says yes, the week shows up by itself.
            await env.calendar.reconnect()
            return
        }
        guard await env.calendar.requestAccess() else { return }
        Task { await env.calendar.refreshPreview() }
        onAllowed()
    }

    private var whatItDoes: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                CalendarCardLabel(text: "What it does")
                Text(CalendarCopy.headline(slot: "lunch", busy: .init(startMin: 720, endMin: 930), kept: false, usualMin: 780))
                    .font(Typography.display(24))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                CalendarMoveRows(slot: "lunch", atMin: 675, usualMin: 780, kept: false, busy: .init(startMin: 720, endMin: 930))
                Text("A heads-up comes before the meeting, not after the meal is missed.")
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var whatISee: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                CalendarCardLabel(text: "What I see")
                seeRow(symbol: "checkmark", tint: Palette.positive, background: Color.white.opacity(0.06),
                       title: "When you're busy", detail: "Start and end times only")
                seeRow(symbol: "nosign", tint: Palette.amber, background: Palette.ember.opacity(0.12),
                       title: "Never titles, people or places", detail: "They stay on this phone")
            }
        }
    }

    private func seeRow(symbol: String, tint: Color, background: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(background, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typography.data(15, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: B0 · Pick calendars

struct CalendarPickView: View {
    var onConnected: () -> Void = {}

    @Environment(AppEnvironment.self) private var env
    @State private var connecting = false

    var body: some View {
        let calendar = env.calendar
        SettingsScreen(title: "Which calendars?", subtitle: "Pick the ones that make you busy.") {
            VStack(alignment: .leading, spacing: 12) {
                if !calendar.ownChoices.isEmpty {
                    Text("Yours").sectionLabelStyle().padding(.horizontal, 4)
                    choices(calendar.ownChoices).appearIn(2)
                }
                if !calendar.subscribedChoices.isEmpty {
                    Text("Subscribed · off to start").sectionLabelStyle().padding(.horizontal, 4).padding(.top, 8)
                    choices(calendar.subscribedChoices).appearIn(3)
                }
                if calendar.choices.isEmpty {
                    SettingsCard {
                        Text("No calendars on this phone yet. Add one in the Calendar app and it shows up here.")
                            .font(Typography.data(14))
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                previewCard.appearIn(4)
                CalendarLockLine().padding(.top, 2)
                ActionButton(title: "Connect", busy: connecting, busyTitle: "Connecting") {
                    Task {
                        connecting = true
                        await calendar.connect()
                        connecting = false
                        if calendar.connected { onConnected() }
                    }
                }
                .padding(.top, 6)
                if let message = calendar.lastError {
                    SettingsErrorBanner(message: message)
                }
            }
        }
        .task {
            calendar.refreshCalendars()
            await calendar.refreshPreview()
        }
    }

    private func choices(_ list: [CalendarChoice]) -> some View {
        CalendarChoicesCard(
            choices: list,
            isOn: { env.calendar.isSelected($0.id) },
            set: { choice, on in
                env.calendar.setSelected(choice.id, on, upload: false)
                Task { await env.calendar.refreshPreview() }
            }
        )
    }

    @ViewBuilder
    private var previewCard: some View {
        if let preview = env.calendar.preview {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.ember)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(preview.movedCount == 0
                        ? "Nothing moves in the next 7 days"
                        : "Next 7 days: \(preview.movedCount) \(preview.movedCount == 1 ? "meal moves" : "meals move") earlier")
                        .font(Typography.data(15, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text(preview.movedCount == 0 ? "Your meals already fit around these calendars." : preview.summary)
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Palette.ember.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.top, 8)
            .accessibilityElement(children: .combine)
        }
    }
}
