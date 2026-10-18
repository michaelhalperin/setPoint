import SwiftUI

/// The check-in answers, shared by the Today takeover and the full check-in.
enum CheckInActions {
    struct SnoozeChoice: Identifiable, Equatable {
        let title: String
        let minutes: Int
        var id: String { title }
    }

    /// Snooze lengths to offer. "After <next meal time>" only when that's far
    /// enough away to mean something; the backend caps a snooze at 6 hours.
    static func snoozeChoices(nextMealMinutes: Int?, now: Date = .now) -> [SnoozeChoice] {
        var choices = [SnoozeChoice(title: "1 hour", minutes: 60), SnoozeChoice(title: "2 hours", minutes: 120)]
        if let minutes = nextMealMinutes, minutes >= 45 {
            let capped = min(minutes, 360)
            let at = now.addingTimeInterval(TimeInterval(capped * 60))
            choices.append(SnoozeChoice(title: "After \(at.formatted(date: .omitted, time: .shortened))", minutes: capped))
        }
        return choices
    }

    /// "I ate this" — logs the prescription's totals and answers the check-in.
    static func eat(prescriptionID: String, api: APIClient) async throws {
        let _: LogMealResponse = try await api.post(
            "/api/meals",
            LogMealRequest(text: nil, macros: nil, prescriptionId: prescriptionID)
        )
    }

    /// "I already ate" — closes the check-in without logging; not a miss.
    static func alreadyAte(checkInID: String, api: APIClient) async throws {
        try await api.post("/api/checkins/\(checkInID)/dismiss")
    }

    static func cover(checkInID: String, api: APIClient) async throws {
        try await api.post("/api/checkins/\(checkInID)/cover")
    }

    static func snooze(checkInID: String, minutes: Int?, api: APIClient) async throws {
        if let minutes {
            try await api.post("/api/checkins/\(checkInID)/defer", SnoozeBody(minutes: min(max(minutes, 15), 360)))
        } else {
            try await api.post("/api/checkins/\(checkInID)/defer")
        }
    }

    private struct SnoozeBody: Encodable {
        let minutes: Int
    }
}

/// Compact sheet for picking how long to snooze a check-in.
struct SnoozeSheet: View {
    let choices: [CheckInActions.SnoozeChoice]
    let onPick: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    static func height(for choiceCount: Int) -> CGFloat {
        148 + CGFloat(max(choiceCount, 1)) * 68 + 72
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Snooze")
                    .font(Typography.display(28))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("I’ll ask again later.")
                    .font(Typography.data(15))
                    .foregroundStyle(Palette.inkSoft)
            }

            VStack(spacing: 10) {
                ForEach(choices) { choice in
                    Button {
                        onPick(choice.minutes)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "zzz")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Palette.accent)
                                .frame(width: 36, height: 36)
                                .background(Palette.accentTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(choice.title)
                                .font(Typography.data(17, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressableCard())
                }
            }

            ActionButton(title: "Cancel", kind: .secondary) { dismiss() }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.lg)
        .padding(.bottom, Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.background.ignoresSafeArea())
    }
}
