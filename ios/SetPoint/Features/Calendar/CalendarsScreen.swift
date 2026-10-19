import SwiftUI

// MARK: Calendars

/// Which calendars make you busy, as lit tiles. Changes recalculate the week live;
/// disconnect lives here.
struct CalendarsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDisconnect = false
    @State private var refusedId: String?

    var body: some View {
        let calendar = env.calendar
        InnerScreen(glow: .haze, spacing: 14) {
            ScreenHeader(label: "Calendars") {
                Text("SYNCED")
                    .font(Typography.mono(10))
                    .foregroundStyle(Palette.positive)
            }

            Headline("Your calendars.", tail: "Lit ones can move a meal.", size: 36)
                .appearIn(0, rise: 16)

            if !calendar.ownChoices.isEmpty {
                CalendarTiles(choices: calendar.ownChoices, isOn: { calendar.isSelected($0.id) }, set: set)
                    .appearIn(1, rise: 14)
            }
            if refusedId != nil {
                Text("Keep at least one calendar on — or disconnect below.")
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.amber)
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if !calendar.subscribedChoices.isEmpty {
                HStack {
                    Text("Subscribed").sectionLabelStyle()
                    Spacer()
                    Text("Holidays, birthdays, sports")
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

            CalendarMovedStrip(week: calendar.week, refreshing: calendar.refreshing)
                .appearIn(3)

            CalendarLockLine()

            Button("Disconnect calendar") { confirmDisconnect = true }
                .font(Typography.data(15, weight: .regular))
                .foregroundStyle(Palette.danger)
                .frame(maxWidth: .infinity, minHeight: 48)
                .buttonStyle(.plain)
        }
        .animation(.snappy, value: refusedId)
        .confirmationDialog("Disconnect calendar?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                Task {
                    await env.calendar.disconnect()
                    dismiss()
                }
            }
        } message: {
            Text("Meals go back to their usual times and busy times are deleted from SetPoint.")
        }
        .task { env.calendar.refreshCalendars() }
    }

    private func set(_ choice: CalendarChoice, _ on: Bool) {
        if env.calendar.setSelected(choice.id, on) {
            refusedId = nil
        } else {
            Haptics.nudge()
            refusedId = choice.id
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                if refusedId == choice.id { refusedId = nil }
            }
        }
    }
}
