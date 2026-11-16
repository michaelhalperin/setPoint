import SwiftUI

/// "Tell me about your week": a few plain words become planned sessions, which are shown
/// first and only added once kept. Behind the training_ai flag.
struct DescribeTrainingSheet: View {
    let earliest: Date
    let weightKg: Double
    let onAdd: ([SessionDraft]) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var working = false
    @State private var error: String?
    @State private var result: [Proposed] = []
    @State private var note: String?
    @State private var asked = false
    @FocusState private var focused: Bool

    private struct Proposed: Identifiable {
        let id = UUID()
        let title: String
        var draft: SessionDraft
    }

    private struct Response: Decodable {
        struct Session: Decodable {
            let title: String
            let kind: String
            let durationMin: Int
            let weekdays: [Int]
            let startMinute: Int
        }
        let sessions: [Session]
        let note: String?
    }

    private struct Request: Encodable { let text: String }

    private static let suggestions = [
        "Lifting Monday, Wednesday and Friday evenings, an hour",
        "Easy 5k run Saturday morning",
        "Football Tuesday at 8pm",
        "Yoga Sunday, 45 minutes",
        "Swimming three times a week",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Headline("Tell me about your week.", tail: "I’ll plan it.", size: 30)

                VStack(alignment: .leading, spacing: 10) {
                    TextField("What do you do, which days, and how long?", text: $text, axis: .vertical)
                        .lineLimit(3 ... 6)
                        .font(Typography.data(16, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .focused($focused)
                        .padding(16)
                        .glass(radius: 22, fill: Color.white.opacity(0.04))
                    FlexWrap(spacing: 6, lineSpacing: 6) {
                        ForEach(Self.suggestions, id: \.self) { line in
                            Button {
                                Haptics.select()
                                let l = L10nKey(line)
                                text = text.isEmpty ? l : text + ". " + l
                            } label: {
                                Text("+ \(L10nKey(line))")
                                    .font(Typography.data(13, weight: .regular))
                                    .foregroundStyle(Palette.inkSoft)
                                    .padding(.horizontal, 12)
                                    .frame(height: 34)
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            }
                            .buttonStyle(PressableCard())
                        }
                    }
                }

                if let error {
                    Text(verbatim: error).font(Typography.data(13)).foregroundStyle(Palette.danger)
                }

                if working {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                } else if asked, result.isEmpty, error == nil {
                    Text("I couldn’t find any training in that. Try adding the days and how long.")
                        .font(Typography.data(14)).foregroundStyle(Palette.inkSoft)
                }

                ForEach($result) { $item in
                    proposedRow($item)
                }
                if let note, !result.isEmpty {
                    Text(verbatim: note).font(Typography.data(12)).foregroundStyle(Palette.inkFaint)
                }
            }
            .padding(Space.gutter)
            .padding(.top, Space.xs)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Group {
                if result.isEmpty {
                    ActionButton(title: "Work it out", kind: .primary, busy: working) { Task { await work() } }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || working)
                        .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 ? 0.45 : 1)
                } else {
                    VStack(spacing: 8) {
                        ActionButton(title: L10n("Add \(result.count) to my plan"), kind: .primary, symbol: "plus") {
                            onAdd(result.map(\.draft))
                            dismiss()
                        }
                        ActionButton(title: "Change what I wrote", kind: .secondary) { result = []; note = nil; focused = true }
                    }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Palette.sheet)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheet)
        .presentationCornerRadius(32)
    }

    private func proposedRow(_ item: Binding<Proposed>) -> some View {
        let p = item.wrappedValue
        let d = p.draft
        let kcal = TrainMath.bump([TrainSession(id: "draft", kind: d.kind, source: "PLANNED", start: .now, durationMin: d.durationMin)], weightKg: weightKg)
        return HStack(spacing: 14) {
            Image(systemName: TrainKind.symbol(d.kind))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.hazeSoft)
                .frame(width: 44, height: 44)
                .background(Palette.haze.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: p.title).font(Typography.data(16, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(verbatim: "\(daysLine(d.repeatDays)) · \(trainClock(TrainMath.minute(d.start))) · \(d.durationMin) min")
                    .font(Typography.data(13)).foregroundStyle(Palette.inkSoft)
                if kcal > 0 {
                    Text(L10n("+\(kcal) kcal food on those days"))
                        .font(Typography.mono(10)).foregroundStyle(Palette.amber)
                }
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(Motion.settle) { result.removeAll { $0.id == p.id } }
            } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(L10n("Remove"))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 22, fill: Color.white.opacity(0.035))
    }

    private func daysLine(_ days: Set<Int>) -> String {
        var calendar = Calendar.current
        calendar.locale = AppLanguage.current.locale
        let names = calendar.shortWeekdaySymbols
        return days.sorted().map { names[($0 - 1) % 7] }.joined(separator: " ")
    }

    private func work() async {
        focused = false
        working = true
        error = nil
        defer { working = false }
        do {
            let res: Response = try await env.api.post("/api/workouts/describe", Request(text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
            result = res.sessions.map { s in
                Proposed(title: s.title, draft: SessionDraft(
                    kind: s.kind,
                    start: firstStart(weekdays: Set(s.weekdays), minute: s.startMinute),
                    durationMin: s.durationMin,
                    repeatDays: Set(s.weekdays)
                ))
            }
            note = res.note
            asked = true
        } catch {
            asked = true
            self.error = UserFacingError.message(for: error, fallback: L10n("Couldn’t work that out. Try again."))
        }
    }

    /// The next time on one of these weekdays at that time, not before the earliest plannable moment.
    private func firstStart(weekdays: Set<Int>, minute: Int) -> Date {
        let calendar = Calendar.current
        let from = max(earliest, .now)
        for offset in 0 ..< 14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: from)) else { continue }
            guard weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            let start = TrainMath.at(minute / 60, minute % 60, on: day)
            if start > from { return start }
        }
        return TrainMath.at(minute / 60, minute % 60, on: from.addingTimeInterval(86_400))
    }
}
