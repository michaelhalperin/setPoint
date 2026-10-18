import SwiftUI

// MARK: Calendars

/// Which calendars make you busy. Changes recalculate the week live; disconnect lives here.
struct CalendarsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDisconnect = false
    @State private var refusedId: String?

    var body: some View {
        let calendar = env.calendar
        let onCount = calendar.selectedChoices.count
        SettingsScreen(title: "Calendars", subtitle: "Pick the ones that make you busy.") {
            VStack(alignment: .leading, spacing: 12) {
                CalendarImpactCard(week: calendar.week, refreshing: calendar.refreshing)
                    .appearIn(2)

                if !calendar.ownChoices.isEmpty {
                    sectionHeader("Yours", trailing: "\(onCount) on")
                        .padding(.top, 8)
                    choices(calendar.ownChoices).appearIn(3)
                }
                if refusedId != nil {
                    Text("Keep at least one calendar on — or disconnect below.")
                        .font(Typography.data(13, weight: .semibold))
                        .foregroundStyle(Palette.accentDeep)
                        .padding(.horizontal, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if !calendar.subscribedChoices.isEmpty {
                    sectionHeader("Subscribed", trailing: "Holidays, birthdays, sports")
                        .padding(.top, 8)
                    choices(calendar.subscribedChoices).appearIn(4)
                    Text("Usually not your own time, so they start off.")
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.horizontal, 4)
                }
                if calendar.choices.isEmpty {
                    SettingsCard {
                        Text("No calendars on this phone yet. Add one in the Calendar app and it shows up here.")
                            .font(Typography.data(14))
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                CalendarLockLine().padding(.top, 8)

                Button("Disconnect calendar") { confirmDisconnect = true }
                    .font(Typography.data(15, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .buttonStyle(.plain)
            }
            .animation(.snappy, value: refusedId)
        }
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

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title).sectionLabelStyle()
            Spacer()
            Text(trailing)
                .font(Typography.data(12))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(.horizontal, 4)
    }

    private func choices(_ list: [CalendarChoice]) -> some View {
        CalendarChoicesCard(
            choices: list,
            isOn: { env.calendar.isSelected($0.id) },
            set: { choice, on in
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
        )
    }
}
