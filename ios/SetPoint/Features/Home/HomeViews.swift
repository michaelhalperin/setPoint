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
        let _: LogMealResponse = try await api.logMeal(
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
    @State private var selected = 0
    private let now = Date.now

    static func height(for choiceCount: Int) -> CGFloat {
        CGFloat(choiceCount > 2 ? 520 : 470)
    }

    private var choice: CheckInActions.SnoozeChoice? {
        choices.indices.contains(selected) ? choices[selected] : choices.first
    }

    private func clock(_ minutes: Int) -> String {
        now.addingTimeInterval(TimeInterval(minutes * 60)).formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Headline("Back at \(clock(choice?.minutes ?? 60)).", tail: "I’ll stay quiet till then.", size: 32)
                .contentTransition(.numericText())

            track

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Array(choices.enumerated()), id: \.element.id) { index, item in
                    let on = index == selected
                    Button {
                        Haptics.select()
                        withAnimation(Motion.settle) { selected = index }
                    } label: {
                        HStack {
                            Text(item.title)
                                .font(Typography.data(14, weight: on ? .medium : .regular))
                            Spacer(minLength: 4)
                            Text(clock(item.minutes))
                                .font(Typography.mono(11))
                                .opacity(0.7)
                        }
                        .foregroundStyle(on ? Palette.onBone : Palette.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .background(on ? Palette.ink : Color.white.opacity(0.05), in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? Palette.ink : Color.white.opacity(0.10)))
                    }
                    .buttonStyle(PressableCard())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }

            VStack(spacing: 4) {
                Button {
                    guard let choice else { return }
                    Haptics.select()
                    onPick(choice.minutes)
                    dismiss()
                } label: {
                    HStack {
                        Text(L10n("Snooze until \(clock(choice?.minutes ?? 60))"))
                            .font(Typography.data(16, weight: .medium))
                        Spacer()
                        Image(systemName: "zzz")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0F0E2A))
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(RadialGradient(colors: [Color(hex: 0xEEF2FF), Palette.haze], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 26)))
                    }
                    .foregroundStyle(Palette.onBone)
                    .padding(.leading, 24)
                    .padding(.trailing, 8)
                    .frame(height: 58)
                    .background(Palette.ink, in: Capsule())
                }
                .buttonStyle(PressableCard())
                Button("Cancel") { dismiss() }
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.lg)
        .padding(.bottom, Space.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) {
            AmbientGlow(tone: .haze, strength: 0.6, height: 300).offset(y: -100)
        }
    }

    /// From now to the furthest choice; a haze bar grows to the one picked.
    private var track: some View {
        let maxMin = max(60, choices.map(\.minutes).max() ?? 60)
        return GeometryReader { geo in
            let w = geo.size.width
            let x = { (m: Int) in CGFloat(m) / CGFloat(maxMin) * (w - 12) + 6 }
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.white.opacity(0.08)).frame(height: 2).offset(y: 23)
                Capsule()
                    .fill(LinearGradient(colors: [Palette.haze.opacity(0.15), Palette.haze.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: x(choice?.minutes ?? 60), height: 4)
                    .shadow(color: Palette.haze.opacity(0.6), radius: 8)
                    .offset(y: 22)
                ForEach(choices) { item in
                    Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                        .position(x: x(item.minutes), y: 24)
                }
                Circle().fill(Palette.ember).frame(width: 10, height: 10)
                    .shadow(color: Palette.ember, radius: 6)
                    .position(x: 6, y: 24)
                EmberDot(size: 22, haze: true)
                    .position(x: x(choice?.minutes ?? 60), y: 24)
                Text(L10n("NOW \(now.formatted(date: .omitted, time: .shortened))"))
                    .font(Typography.mono(10))
                    .foregroundStyle(Palette.amber)
                    .position(x: 40, y: 50)
            }
            .animation(Motion.settle, value: selected)
        }
        .frame(height: 60)
        .accessibilityHidden(true)
    }
}
