import SwiftUI

struct SettlementView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: SettlementViewModel?
    @State private var showingWeighIn = false

    init(previewModel: SettlementViewModel? = nil) {
        _model = State(initialValue: previewModel)
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("This week")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                let vm = SettlementViewModel(api: env.api, onUnauthorized: { env.auth.handleUnauthorized() })
                model = vm
                await vm.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: SettlementViewModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case let .failed(message):
            ContentUnavailableView("Couldn't load", systemImage: "chart.bar", description: Text(message))
        case let .loaded(s):
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let goal = s.weightGoal {
                        WeightGoalCard(goal: goal, busy: model.loggingWeight) { showingWeighIn = true }
                    }

                    WeekStrip(days: s.days, today: s.today)

                    Text(s.weekSummary)
                        .font(Typography.voice(18))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)

                    if s.days.isEmpty {
                        Text("Days fill in here as they settle — one row each morning.")
                            .font(Typography.data(13))
                            .foregroundStyle(Palette.inkFaint)
                            .appearIn()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(s.days.reversed().enumerated()), id: \.element.id) { index, day in
                                DayRow(day: day)
                                    .staggeredAppear(index: index)
                                if day.id != s.days.first?.id {
                                    Divider().overlay(Palette.ink.opacity(0.06))
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .refreshable { await model.load() }
            .background(Palette.background)
            .sheet(isPresented: $showingWeighIn) {
                WeighInSheet { kg in await model.logWeight(kg: kg) }
                    .presentationDetents([.height(300)])
            }
            .alert("You hit your target", isPresented: reachedBinding(model)) {
                Button("Nice") { model.reachedGoalTarget = nil }
            } message: {
                Text("You're at \(oneDp(model.reachedGoalTarget ?? 0)) kg. SetPoint switched you to maintenance — no more deficit, just keep eating enough.")
            }
        }
    }

    private func reachedBinding(_ model: SettlementViewModel) -> Binding<Bool> {
        Binding(get: { model.reachedGoalTarget != nil }, set: { if !$0 { model.reachedGoalTarget = nil } })
    }
}

private func oneDp(_ v: Double) -> String { String(format: "%.1f", v) }

/// Progress toward a weight goal (§5.1, M16) — a quiet bar, "X kg to go", a pace
/// pill, and the weigh-in prompt. Never gamified.
private struct WeightGoalCard: View {
    let goal: SettlementResponse.WeightGoal
    let busy: Bool
    let onWeighIn: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { min(1, max(0, goal.fractionComplete ?? 0)) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(headline).sectionLabelStyle()
                    Spacer()
                    if let pill = statusPill {
                        Text(pill.text)
                            .font(Typography.data(11, weight: .semibold))
                            .foregroundStyle(pill.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(pill.tint.opacity(0.14), in: Capsule())
                            .id(pill.text)
                            .transition(.opacity)
                    }
                }

                if let current = goal.currentWeightKg, let target = goal.targetWeightKg {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(oneDp(current)).font(Typography.data(30, weight: .semibold)).foregroundStyle(Palette.ink)
                            .contentTransition(.numericText(value: current))
                        Text("kg").font(Typography.data(14)).foregroundStyle(Palette.inkFaint)
                        Spacer()
                        Text("target \(oneDp(target)) kg").font(Typography.data(13)).foregroundStyle(Palette.inkFaint)
                    }
                }

                ProgressBar(fraction: fraction)

                HStack {
                    if let remaining = goal.remainingKg {
                        Text(remaining <= 0 ? "Target reached" : "\(oneDp(remaining)) kg to go")
                            .font(Typography.data(13, weight: .medium))
                            .foregroundStyle(Palette.inkSoft)
                            .contentTransition(.numericText(value: max(0, remaining)))
                    }
                    if let eta = goal.etaWeeks, eta > 0 {
                        Text("· ~\(eta) wk").font(Typography.data(13)).foregroundStyle(Palette.inkFaint)
                    }
                }

                if goal.needsWeighIn {
                    Text("No weigh-in this week — log one to keep progress honest.")
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.accent)
                }

                ActionButton(
                    title: busy ? "Saving…" : "Log weight",
                    kind: goal.needsWeighIn ? .primary : .secondary
                ) { if !busy { onWeighIn() } }
            }
        }
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: goal.currentWeightKg)
        .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion), value: goal.status)
    }

    private var headline: String {
        switch goal.goal {
        case "BULK": return "Gaining to target"
        case "DIET": return "Cutting to target"
        default: return "Weight goal"
        }
    }

    private var statusPill: (text: String, tint: Color)? {
        switch goal.status {
        case "ahead": return ("Ahead of pace", Palette.dayOnTrack)
        case "on_pace": return ("On pace", Palette.dayOnTrack)
        case "behind": return ("Behind pace", Palette.accent)
        case "reached": return ("Reached", Palette.dayOnTrack)
        default: return nil
        }
    }
}

private struct ProgressBar: View {
    let fraction: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surfaceSunk)
                Capsule().fill(Palette.accent)
                    .frame(width: max(4, geo.size.width * (filled ? fraction : 0)))
                    .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: fraction)
            }
        }
        .frame(height: 8)
        .onAppear {
            withAnimation(Motion.adaptive(Motion.gentle, reduceMotion: reduceMotion)) { filled = true }
        }
    }
}

private struct WeighInSheet: View {
    /// Returns whether the weigh-in saved — on success the sheet shows a brief
    /// "Saved" beat, then dismisses itself.
    let onSubmit: (Double) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = ""
    @State private var phase: Phase = .idle
    @FocusState private var focused: Bool

    private enum Phase { case idle, saving, saved }

    private var value: Double? {
        let v = Double(text.replacingOccurrences(of: ",", with: "."))
        return (v ?? 0) >= 25 && (v ?? 0) <= 400 ? v : nil
    }

    private var buttonTitle: String {
        switch phase {
        case .idle: return "Save"
        case .saving: return "Saving…"
        case .saved: return "✓ Saved"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Today's weight")
                .font(Typography.voice(22))
                .foregroundStyle(Palette.ink)

            HStack {
                TextField("—", text: $text)
                    .keyboardType(.decimalPad)
                    .font(Typography.data(22, weight: .semibold))
                    .focused($focused)
                    .disabled(phase != .idle)
                Text("kg").font(Typography.data(15)).foregroundStyle(Palette.inkFaint)
            }
            .padding(14)
            .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            ActionButton(title: buttonTitle) { save() }
                .opacity(value == nil && phase == .idle ? 0.5 : 1)
                .disabled(value == nil || phase != .idle)
                .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: phase)

            Text("Best first thing in the morning, before eating.")
                .font(Typography.data(12))
                .foregroundStyle(Palette.inkFaint)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.background)
        .onAppear { focused = true }
    }

    private func save() {
        guard phase == .idle, let value else { return }
        focused = false
        Task {
            phase = .saving
            let ok = await onSubmit(value)
            guard ok else { phase = .idle; return }
            phase = .saved
            Haptics.landed()
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 480))
            dismiss()
        }
    }
}

/// The 7-day trend — one bar per day, height = kcal vs target, coloured by
/// outcome (§5.7). Bars enter with a small per-index stagger (§5a).
private struct WeekStrip: View {
    let days: [SettlementResponse.Day]
    let today: SettlementResponse.Today

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    private struct Bar: Identifiable {
        let id: String
        let ratio: Double
        let kind: String
        let label: String
        let isToday: Bool
    }

    private var bars: [Bar] {
        let target = Double(max(1, today.kcalTarget))
        let past = days.map {
            Bar(id: $0.id, ratio: Double($0.kcalConsumed) / target, kind: $0.kind, label: dayLabel($0.date), isToday: false)
        }
        let now = Bar(
            id: today.date, ratio: Double(today.kcalConsumed) / target, kind: today.kind,
            label: "Today", isToday: true
        )
        return (past + [now]).suffix(7)
    }

    private let maxBarHeight: CGFloat = 96

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        Color.clear.frame(height: maxBarHeight)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Palette.day(bar.kind))
                            .opacity(bar.isToday ? 0.55 : 1)
                            .frame(height: grown ? barHeight(bar.ratio) : 3)
                            .firstAppearPulse(bar.isToday)
                    }
                    .frame(height: maxBarHeight)
                    .animation(
                        Motion.adaptive(Motion.gentle, reduceMotion: reduceMotion)
                            .delay(reduceMotion ? 0 : Double(index) * 0.04),
                        value: grown
                    )
                    // A later refresh re-flows the bars from their current
                    // height to the new one, rather than collapsing and regrowing.
                    .animation(Motion.adaptive(Motion.gentle, reduceMotion: reduceMotion), value: bar.ratio)

                    Text(bar.label)
                        .font(Typography.data(10, weight: .medium))
                        .foregroundStyle(bar.isToday ? Palette.ink : Palette.inkFaint)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { grown = true }
    }

    private func barHeight(_ ratio: Double) -> CGFloat {
        let clamped = min(1.0, max(0.04, ratio))
        return CGFloat(clamped) * maxBarHeight
    }

    private func dayLabel(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.dateOnly.date(from: iso + "T00:00:00Z") else { return "" }
        let f = DateFormatter()
        f.dateFormat = "EEEEE" // single-letter weekday
        return f.string(from: date)
    }
}

private struct DayRow: View {
    let day: SettlementResponse.Day

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Palette.day(day.kind)).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(fullDate(day.date))
                        .font(Typography.data(14, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(day.kcalConsumed) / \(day.kcalTarget)")
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkFaint)
                }
                if let line = day.summaryLine {
                    Text(line)
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func fullDate(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.dateOnly.date(from: iso + "T00:00:00Z") else { return iso }
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }
}

private extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

private struct StaggeredAppear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .onAppear {
                withAnimation(
                    Motion.adaptive(Motion.gentle, reduceMotion: reduceMotion)
                        .delay(reduceMotion ? 0 : Double(index) * 0.04)
                ) { shown = true }
            }
    }
}

private extension View {
    func staggeredAppear(index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
}

#if DEBUG
#Preview {
    NavigationStack { SettlementView() }
        .environment(AppEnvironment.preview())
}
#endif
