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
        InnerScreen(glow: .mixed, spacing: 16) {
            ScreenHeader(label: reconnecting ? "Reconnect" : "Calendar · Pro")

            Headline(
                reconnecting ? "Your rules are saved." : "Eat before you’re busy.",
                tail: reconnecting ? "iPhone just needs Calendar access again." : nil,
                size: 42
            )
            .appearIn(0, rise: 16)

            CalendarMoveScene()
                .frame(height: 250)
                .glass(radius: 26)
                .appearIn(1, rise: 14)

            if !reconnecting {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("I see", systemImage: "checkmark")
                            .labelStyle(SeeLabelStyle(tint: Palette.positive))
                        Text("12:00–15:30")
                            .font(Typography.mono(17))
                            .foregroundStyle(Palette.ink)
                        Text("When you’re busy")
                            .font(Typography.data(12, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .glass(radius: 20)
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Never", systemImage: "xmark")
                            .labelStyle(SeeLabelStyle(tint: Palette.inkFaint))
                        VStack(alignment: .leading, spacing: 5) {
                            Capsule().fill(Color.white.opacity(0.14)).frame(height: 7)
                            Capsule().fill(Color.white.opacity(0.09)).frame(width: 70, height: 7)
                        }
                        .padding(.vertical, 3)
                        .accessibilityHidden(true)
                        Text("Titles, people, places")
                            .font(Typography.data(12, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                }
                .fixedSize(horizontal: false, vertical: true)
                .appearIn(2)
            }

            VStack(spacing: 6) {
                if env.calendar.accessDenied {
                    Text("Calendar access is off for SetPoint. Turn it on in Settings, then come back.")
                        .font(Typography.data(14))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    ActionButton(title: "Open Settings") { env.calendar.openSystemSettings() }
                } else {
                    ActionButton(
                        title: reconnecting ? "Reconnect" : "Allow calendar access",
                        busy: asking,
                        busyTitle: reconnecting ? "Reconnecting" : "Asking"
                    ) {
                        Task { await allow() }
                    }
                }
                Button("Not now") { dismiss() }
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 44)
                if let message = env.calendar.lastError {
                    SettingsErrorBanner(message: message)
                }
            }
            .padding(.top, 6)
            .appearIn(3)
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
}

private struct SeeLabelStyle: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 10, weight: .heavy)).foregroundStyle(tint)
            configuration.title.sectionLabelStyle(tint)
        }
    }
}

/// A busy block arrives and lunch lifts out of it, from 13:00 to 11:15.
struct CalendarMoveScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lifted = false

    private let hourHeight: CGFloat = 50
    private func y(_ m: Int) -> CGFloat { 20 + CGFloat(m - 660) / 60 * hourHeight }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach([660, 720, 780, 840, 900], id: \.self) { m in
                    Rectangle().fill(Color.white.opacity(0.06)).frame(width: w - 30, height: 1)
                        .offset(x: 14, y: y(m))
                    Text(CalendarClock.hm(m))
                        .font(Typography.mono(10))
                        .foregroundStyle(Palette.inkFaint)
                        .padding(.trailing, 4)
                        .background(Color(hex: 0x111114))
                        .offset(x: 14, y: y(m) - 7)
                }
                BusyBlock(color: Palette.haze, radius: 14)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Busy").font(Typography.data(13, weight: .regular)).foregroundStyle(Palette.ink)
                            Text("12:00–15:30").font(Typography.mono(10)).foregroundStyle(Palette.inkFaint)
                        }
                        .padding(10)
                    }
                    .frame(width: w - 166, height: 200)
                    .offset(x: 150, y: y(720))

                GhostRing(size: 16).offset(x: 58, y: y(780) - 8)
                Text("usual")
                    .font(Typography.data(11, weight: .regular))
                    .foregroundStyle(Palette.inkFaint)
                    .offset(x: 82, y: y(780) - 7)
                    .opacity(lifted ? 1 : 0)
                Rectangle().fill(Palette.amber.opacity(0.55)).frame(width: 1.5, height: y(780) - y(675) - 14)
                    .offset(x: 65.5, y: y(675) + 13)
                    .opacity(lifted ? 1 : 0)
                EmberDot(size: 26)
                    .offset(x: 53, y: (lifted ? y(675) : y(780)) - 13)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Lunch").font(Typography.data(14, weight: .regular)).foregroundStyle(Palette.amber)
                    Text("11:15").font(Typography.mono(11)).foregroundStyle(Color(hex: 0xFDE6CF))
                }
                .offset(x: 90, y: y(675) - 16)
                .opacity(lifted ? 1 : 0)
            }
        }
        .clipped()
        .onAppear {
            if reduceMotion { lifted = true; return }
            withAnimation(.spring(response: 1.1, dampingFraction: 0.85).delay(0.7)) { lifted = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Lunch moves from 13:00 to 11:15 because you're busy from 12:00")
    }
}

// MARK: B0 · Pick calendars

struct CalendarPickView: View {
    var onConnected: () -> Void = {}

    @Environment(AppEnvironment.self) private var env
    @State private var connecting = false

    var body: some View {
        let calendar = env.calendar
        InnerScreen(glow: .haze, spacing: 14) {
            ScreenHeader(label: "Calendars")

            Headline("Which ones make you busy?", tail: "Light them up.", size: 36)
                .appearIn(0, rise: 16)

            if !calendar.ownChoices.isEmpty {
                CalendarTiles(choices: calendar.ownChoices, isOn: { calendar.isSelected($0.id) }, set: set)
                    .appearIn(1, rise: 14)
            }
            if !calendar.subscribedChoices.isEmpty {
                HStack {
                    Text("Subscribed").sectionLabelStyle()
                    Spacer()
                    Text("Rarely your time · off to start")
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.inkFaint)
                }
                .padding(.horizontal, 4)
                CalendarTiles(choices: calendar.subscribedChoices, columns: 2, compact: true, isOn: { calendar.isSelected($0.id) }, set: set)
                    .appearIn(2)
            }
            if calendar.choices.isEmpty {
                Text("No calendars on this phone yet. Add one in the Calendar app and it shows up here.")
                    .font(Typography.data(14))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(16)
                    .glass(radius: 22)
            }

            if let preview = calendar.preview {
                previewStrip(preview).appearIn(3)
            }

            CalendarLockLine()

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
        .task {
            calendar.refreshCalendars()
            await calendar.refreshPreview()
        }
    }

    private func set(_ choice: CalendarChoice, _ on: Bool) {
        env.calendar.setSelected(choice.id, on, upload: false)
        Task { await env.calendar.refreshPreview() }
    }

    private func previewStrip(_ preview: CalendarPreviewResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Next 7 days, I’d move")
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("\(preview.movedCount) \(preview.movedCount == 1 ? "meal" : "meals")")
                    .font(Typography.mono(12))
                    .foregroundStyle(Palette.amber)
            }
            Text(preview.movedCount == 0
                 ? "Your meals already fit around these calendars."
                 : preview.moved.map { "\(CalendarDates.shortWeekday($0.weekday))\u{00A0}\($0.slot)\u{00A0}\(CalendarClock.hm($0.atMin))" }.joined(separator: " · "))
                .font(Typography.mono(11))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glass(radius: 22, fill: Palette.ember.opacity(0.06), stroke: Color(hex: 0xFF8A50, opacity: 0.25))
        .accessibilityElement(children: .combine)
    }
}
