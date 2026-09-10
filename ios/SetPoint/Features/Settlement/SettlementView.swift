import SwiftUI

struct SettlementView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: SettlementViewModel?
    @State private var showingWeighIn = false
    @State private var selectedStation: WeekStation?

    init(previewModel: SettlementViewModel? = nil) {
        _model = State(initialValue: previewModel)
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                SettlementSkeletonView()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.visible, for: .tabBar)
        .task {
            if model == nil {
                let vm = SettlementViewModel(api: env.api, onUnauthorized: { env.auth.handleUnauthorized() })
                model = vm
                await vm.load()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let model else { return }
            if case .loaded = model.phase {
                Task { await model.load() }
            }
        }
        .onChange(of: env.changes.mealRevision) { _, _ in
            guard let model else { return }
            Task { await model.load() }
        }
    }

    @ViewBuilder
    private func content(_ model: SettlementViewModel) -> some View {
        switch model.phase {
        case .loading:
            SettlementSkeletonView()
        case let .failed(message):
            RetryState(message: message) { Task { await model.load() } }
        case let .loaded(s):
            loaded(s, model: model)
        }
    }

    private func loaded(_ s: SettlementResponse, model: SettlementViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Week")
                        .font(Typography.display(34))
                        .foregroundStyle(Palette.ink)
                    Text("Your recent pattern.")
                        .font(Typography.voice(17))
                        .foregroundStyle(Palette.inkSoft)
                }
                    .appearIn(0)

                if let goal = s.weightGoal {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Weight").sectionLabelStyle()

                        if goal.needsWeighIn {
                            WeeklyWeighInPrompt(goal: goal, busy: model.loggingWeight) {
                                showingWeighIn = true
                            }
                        } else {
                            Card(tint: Palette.surfaceRaised, elevation: .floating, padding: Space.md) {
                                WeightDestination(
                                    goal: goal,
                                    showLogLink: true,
                                    busy: model.loggingWeight
                                ) { showingWeighIn = true }
                            }
                        }
                    }
                    .appearIn(1)
                }

                WeekReviewSummary(days: s.days, summary: s.weekSummary)
                    .appearIn(2)

                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Days").sectionLabelStyle()

                    WeekPattern(stations: s.weekStations) { selectedStation = $0 }
                }
                .appearIn(3)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await model.load() }
        .background(Palette.background.ignoresSafeArea())
        .sheet(item: $selectedStation) { station in
            DayMealsSheet(station: station, model: model)
        }
        .sheet(isPresented: $showingWeighIn) {
            WeighInSheet { kg in await model.logWeight(kg: kg) }
                .presentationDetents([.height(300)])
        }
        .alert("Target reached", isPresented: reachedBinding(model)) {
            Button("OK") { model.reachedGoalTarget = nil }
        } message: {
            Text("\(oneDp(model.reachedGoalTarget ?? 0)) kg reached. Maintenance is now active.")
        }
    }

    private func reachedBinding(_ model: SettlementViewModel) -> Binding<Bool> {
        Binding(get: { model.reachedGoalTarget != nil }, set: { if !$0 { model.reachedGoalTarget = nil } })
    }
}

private struct SettlementSkeletonView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    SkeletonBlock(width: 164, height: 36, radius: 10)
                    SkeletonBlock(width: 236, height: 17)
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    SkeletonBlock(width: 108, height: 13)
                    SkeletonCard(height: 104) {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SkeletonBlock(width: 210, height: 28)
                            SkeletonBlock(width: 166, height: 12)
                            SkeletonBlock(width: 248, height: 6, radius: 3)
                        }
                    }
                }

                SkeletonCard(height: 218) {
                    VStack(alignment: .leading, spacing: Space.md) {
                        HStack {
                            SkeletonBlock(width: 98, height: 12)
                            Spacer()
                            SkeletonBlock(width: 62, height: 25, radius: Radius.pill)
                        }
                        VStack(alignment: .leading, spacing: Space.xs) {
                            SkeletonBlock(width: 248, height: 21)
                            SkeletonBlock(width: 214, height: 21)
                        }
                        Spacer()
                        HStack(spacing: 3) {
                            ForEach(0..<6, id: \.self) { _ in
                                SkeletonBlock(height: 8, radius: 4)
                            }
                        }
                        HStack {
                            SkeletonBlock(width: 82, height: 12)
                            Spacer()
                            SkeletonBlock(width: 72, height: 12)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    SkeletonBlock(width: 94, height: 13)
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(0..<7, id: \.self) { index in
                            VStack(spacing: Space.xs) {
                                SkeletonBlock(width: 28, height: 28, radius: 14)
                                SkeletonBlock(width: 22, height: 9)
                                SkeletonBlock(width: 3, height: index.isMultiple(of: 2) ? 62 : 44, radius: 2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, Space.sm)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xl)
        }
        .background(Palette.background.ignoresSafeArea())
        .scrollDisabled(true)
        .skeletonLoading()
    }
}

private func oneDp(_ v: Double) -> String { String(format: "%.1f", v) }

/// The weekly verdict: manager interpretation first, with only the counts needed
/// to verify it.
private struct WeekReviewSummary: View {
    let days: [SettlementResponse.Day]
    let summary: String

    private var onTrack: Int { days.filter { $0.kind == "ON_TRACK" }.count }
    private var under: Int { days.filter { $0.kind == "UNDER" }.count }
    private var over: Int { days.filter { $0.kind == "OVER" }.count }
    private var unlogged: Int { days.filter { $0.kind == "MISSED" }.count }

    var body: some View {
        Card(tint: Palette.surfaceRaised, elevation: .floating, padding: Space.md) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack {
                    Label(
                        days.isEmpty ? "FIRST WEEK" : "THIS WEEK",
                        systemImage: "quote.bubble.fill"
                    )
                    .font(Typography.data(11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Palette.inkSoft)

                    Spacer()

                    if !days.isEmpty {
                        Text("\(days.count) \(days.count == 1 ? "day" : "days")")
                            .font(Typography.data(11, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Palette.surfaceSunk, in: Capsule())
                    }
                }

                Text(summary)
                    .font(Typography.voice(22))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !days.isEmpty {
                    Divider().overlay(Palette.hairline)

                    VStack(alignment: .leading, spacing: Space.sm) {
                        HStack(spacing: 3) {
                            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Palette.day(day.kind))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 8)
                        .accessibilityHidden(true)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading),
                            ],
                            alignment: .leading,
                            spacing: 9
                        ) {
                            metric("On target", onTrack, Palette.dayOnTrack)
                            metric("Under", under, Palette.dayUnder)
                            metric("Over", over, Palette.dayOver)
                            metric("Unlogged", unlogged, Palette.dayMissed)
                        }
                    }
                }
            }
        }
    }

    private func metric(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(value)")
                .font(Typography.data(13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
            Text(label)
                .font(Typography.data(12))
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label.lowercased()) days")
    }
}

/// The week at a glance. Selecting a bar focuses one day; meal details stay one
/// deliberate step deeper instead of making every day a full card.
private struct WeekPattern: View {
    let stations: [WeekStation]
    let onOpen: (WeekStation) -> Void
    @State private var selectedID: String?
    @State private var showingHint = false

    private var focused: WeekStation? {
        if let selectedID, let selected = stations.first(where: { $0.id == selectedID }) {
            return selected
        }
        return stations.first(where: \.isToday)
            ?? stations.last
    }

    var body: some View {
        VStack(spacing: Space.sm) {
            Card(tint: Palette.surfaceRaised, padding: 14) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(alignment: .bottom, spacing: 7) {
                        ForEach(stations) { station in
                            dayBar(station)
                        }
                    }
                    .frame(height: 104, alignment: .bottom)

                    Button {
                        withAnimation(Motion.snappy) {
                            showingHint.toggle()
                        }
                    } label: {
                        Label(
                            showingHint ? "Hide" : "Chart help",
                            systemImage: showingHint ? "xmark.circle" : "questionmark.circle"
                        )
                        .font(Typography.data(11, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                    }
                    .buttonStyle(.plain)

                    if showingHint {
                        Text("Height = intake vs target.")
                            .font(Typography.data(11))
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }

            if let focused {
                focusedDay(focused)
                    .id(focused.id)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Motion.settle, value: selectedID)
    }

    private func dayBar(_ station: WeekStation) -> some View {
        Button {
            selectedID = station.id
        } label: {
            VStack(spacing: 7) {
                Spacer(minLength: 0)

                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(Palette.surfaceSunk)
                        .frame(width: 18, height: 70)
                    Capsule()
                        .fill(Palette.day(station.kind).opacity(station.isToday ? 0.65 : 1))
                        .frame(width: 18, height: barHeight(station))
                }

                Text(shortDay(station))
                    .font(Typography.data(10, weight: focused?.id == station.id ? .bold : .medium))
                    .foregroundStyle(focused?.id == station.id ? Palette.ink : Palette.inkFaint)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                focused?.id == station.id ? Palette.accentTint : Color.clear,
                in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(station))
        .accessibilityAddTraits(focused?.id == station.id ? .isSelected : [])
    }

    private func focusedDay(_ station: WeekStation) -> some View {
        Card(
            tint: station.isToday ? Palette.accentTint : Palette.surface,
            elevation: .resting,
            padding: Space.md
        ) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(station.title)
                        .font(Typography.data(16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(station.isToday ? "Live" : station.kindLabel)
                        .font(Typography.data(11, weight: .semibold))
                        .foregroundStyle(station.isToday ? Palette.accent : Palette.day(station.kind))
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(station.kcalConsumed)")
                        .font(Typography.data(25, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                    Text("of \(station.kcalTarget) kcal")
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkFaint)
                        .monospacedDigit()
                }

                DayFill(fraction: station.fill, kind: station.kind, isToday: station.isToday)

                if let line = station.summaryLine {
                    Text(line)
                        .font(Typography.voice(16))
                        .foregroundStyle(Palette.inkSoft)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    onOpen(station)
                } label: {
                    HStack {
                        Text("Meals")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    private func barHeight(_ station: WeekStation) -> CGFloat {
        guard station.kcalConsumed > 0 else { return 6 }
        let ratio = Double(station.kcalConsumed) / Double(max(station.kcalTarget, 1))
        return max(8, 70 * min(1, ratio / 1.15))
    }

    private func shortDay(_ station: WeekStation) -> String {
        if station.isToday { return "Now" }
        guard let date = WeekStation.parse(station.date) else { return String(station.title.prefix(2)) }
        let formatter = DateFormatter()
        formatter.dateFormat = "EE"
        return formatter.string(from: date)
    }

    private func accessibilityLabel(_ station: WeekStation) -> String {
        var parts = [station.accessibilityTitle]
        if !station.isToday { parts.append(station.kindLabel) }
        parts.append("\(station.kcalConsumed) of \(station.kcalTarget) kcal")
        if let line = station.summaryLine { parts.append(line) }
        return parts.joined(separator: ", ")
    }
}

private struct DayFill: View {
    let fraction: Double
    let kind: String
    let isToday: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surfaceSunk)
                Capsule()
                    .fill(Palette.day(kind).opacity(isToday ? 0.55 : 1))
                    .frame(width: barWidth(in: geo.size.width))
            }
        }
        .frame(height: 5)
        .onAppear {
            withAnimation(Motion.adaptive(Motion.gentle, reduceMotion: reduceMotion)) { filled = true }
        }
        .animation(Motion.adaptive(Motion.gentle, reduceMotion: reduceMotion), value: fraction)
        .accessibilityHidden(true)
    }

    private func barWidth(in total: CGFloat) -> CGFloat {
        guard filled, fraction > 0 else { return 0 }
        return max(4, total * fraction)
    }
}

/// The recurring action on Week, kept in the same prominent progress block as
/// the weight destination it refreshes.
private struct WeeklyWeighInPrompt: View {
    let goal: SettlementResponse.WeightGoal
    let busy: Bool
    let onWeighIn: () -> Void

    var body: some View {
        Card(tint: Palette.accentTint, elevation: .floating, padding: Space.md) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack {
                Label("WEIGH-IN", systemImage: "scalemass.fill")
                        .font(Typography.data(11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Palette.accentDeep)
                    Spacer()
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 8, height: 8)
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Weekly weight")
                        .font(Typography.voice(22))
                        .foregroundStyle(Palette.ink)
                    Text(weightContext)
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ActionButton(title: busy ? "Saving…" : "Log weight") {
                    if !busy { onWeighIn() }
                }
                .disabled(busy)
            }
        }
    }

    private var weightContext: String {
        if let current = goal.currentWeightKg, let target = goal.targetWeightKg {
            return "\(oneDp(current)) kg → \(oneDp(target)) kg"
        }
        return "Update your progress."
    }
}

/// Longitudinal goal progress shown before the week-level intake evidence.
private struct WeightDestination: View {
    let goal: SettlementResponse.WeightGoal
    let showLogLink: Bool
    let busy: Bool
    let onWeighIn: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { min(1, max(0, goal.fractionComplete ?? 0)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Label(goalLabel.uppercased(), systemImage: "scalemass.fill")
                    .font(Typography.data(11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Palette.inkSoft)

                Spacer()

                if let status = statusLabel {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusTint)
                            .frame(width: 7, height: 7)
                        Text(status)
                    }
                    .font(Typography.data(11, weight: .semibold))
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusTint.opacity(0.1), in: Capsule())
                }
            }

            HStack(alignment: .lastTextBaseline) {
                if let current = goal.currentWeightKg {
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text(oneDp(current))
                            .font(Typography.data(42, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.numericText(value: current))
                            .monospacedDigit()
                        Text("kg")
                            .font(Typography.data(15))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Current weight, \(oneDp(current)) kilograms")
                } else {
                    Text(headline)
                        .font(Typography.voice(22))
                        .foregroundStyle(Palette.ink)
                }

                Spacer(minLength: Space.sm)

                if let remaining = goal.remainingKg {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(remaining <= 0 ? "GOAL" : "TO GO")
                            .font(Typography.data(10, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Palette.inkFaint)
                        Text(remaining <= 0 ? "Reached" : "\(oneDp(remaining)) kg")
                            .font(Typography.data(15, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                            .contentTransition(.numericText(value: max(0, remaining)))
                    }
                }
            }

            VStack(spacing: Space.xs) {
                ProgressBar(fraction: fraction)

                HStack {
                    Text(startLabel)
                    Spacer()
                    Text(progressLabel)
                    Spacer()
                    Text(targetLabel)
                }
                .font(Typography.data(11))
                .foregroundStyle(Palette.inkFaint)
            }

            Divider().overlay(Palette.hairline)

            HStack(spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(changeLabel)
                        .font(Typography.data(13, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    if let eta = etaLabel {
                        Text(eta)
                            .font(Typography.data(11))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }

                Spacer()

                if showLogLink {
                    Button {
                        if !busy { onWeighIn() }
                    } label: {
                        Label(busy ? "Saving…" : "Log weight", systemImage: "plus")
                            .font(Typography.data(13, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Palette.surfaceSunk, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: goal.currentWeightKg)
        .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion), value: goal.status)
    }

    private var goalLabel: String {
        switch goal.goal {
        case "BULK": return "Gain"
        case "DIET": return "Cut"
        default: return "Weight"
        }
    }

    private var headline: String {
        switch goal.goal {
        case "BULK":
            if let target = goal.targetWeightKg { return "→ \(oneDp(target)) kg" }
            return "→ target"
        case "DIET":
            if let target = goal.targetWeightKg { return "→ \(oneDp(target)) kg" }
            return "→ target"
        default: return "Weight goal"
        }
    }

    private var statusLabel: String? {
        switch goal.status {
        case "ahead": return "Ahead"
        case "on_pace": return "On pace"
        case "behind": return "Behind"
        case "reached": return "Reached"
        default: return nil
        }
    }

    private var startLabel: String {
        guard let start = goal.startWeightKg else { return "Start" }
        return "Start \(oneDp(start))"
    }

    private var targetLabel: String {
        guard let target = goal.targetWeightKg else { return "Target" }
        return "Target \(oneDp(target))"
    }

    private var progressLabel: String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private var changeLabel: String {
        guard let changed = goal.changedKg, changed > 0 else { return "Starting point" }
        switch goal.goal {
        case "BULK": return "+\(oneDp(changed)) kg"
        case "DIET": return "−\(oneDp(changed)) kg"
        default: return "±\(oneDp(changed)) kg"
        }
    }

    private var etaLabel: String? {
        guard let weeks = goal.etaWeeks, weeks > 0, goal.status != "reached" else { return nil }
        return weeks == 1 ? "~1 week" : "~\(weeks) weeks"
    }

    private var statusTint: Color {
        switch goal.status {
        case "behind": return Palette.accent
        case "ahead", "on_pace", "reached": return Palette.dayOnTrack
        default: return Palette.inkFaint
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
                    .frame(width: barWidth(in: geo.size.width))
                    .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: fraction)
            }
        }
        .frame(height: 8)
        .onAppear {
            withAnimation(Motion.adaptive(Motion.gentle, reduceMotion: reduceMotion)) { filled = true }
        }
        .accessibilityHidden(true)
    }

    private func barWidth(in total: CGFloat) -> CGFloat {
        guard filled, fraction > 0 else { return 0 }
        return max(4, total * fraction)
    }
}

private struct WeighInBar: View {
    let busy: Bool
    let onWeighIn: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("No weigh-in this week")
                    .font(Typography.data(14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Update progress.")
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 8)
            PillButton(title: busy ? "Saving…" : "Log weight") {
                if !busy { onWeighIn() }
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background {
            Palette.background
                .overlay(alignment: .top) {
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }
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
            Text("Weight")
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

            Text("Best before breakfast.")
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

private struct DayMealsSheet: View {
    let station: WeekStation
    let model: SettlementViewModel

    @State private var meals: [MealSummary] = []
    @State private var loading = true
    @State private var selectedMeal: MealSummary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(station.title)
                        .font(Typography.voice(24))
                        .foregroundStyle(Palette.ink)

                    if !station.isToday {
                        Text(station.kindLabel)
                            .font(Typography.data(13, weight: .medium))
                            .foregroundStyle(Palette.day(station.kind))
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(station.kcalConsumed)")
                            .font(Typography.data(36, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .monospacedDigit()
                        Text("/ \(station.kcalTarget) kcal")
                            .font(Typography.data(15))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .padding(.top, 4)

                    if let line = station.summaryLine {
                        Text(line)
                            .font(Typography.voice(16))
                            .foregroundStyle(Palette.inkSoft)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }

                if loading {
                    VStack(spacing: Space.sm) {
                        ForEach(0..<3, id: \.self) { index in
                            HStack(spacing: Space.sm) {
                                SkeletonBlock(width: 42, height: 42, radius: 13)
                                VStack(alignment: .leading, spacing: 6) {
                                    SkeletonBlock(width: index == 1 ? 118 : 152, height: 14)
                                    SkeletonBlock(width: 76, height: 10)
                                }
                                Spacer()
                                SkeletonBlock(width: 46, height: 14)
                            }
                        }
                    }
                    .padding(.top, Space.xs)
                    .skeletonLoading()
                } else if meals.isEmpty {
                    Text("No meals logged.")
                        .font(Typography.data(14))
                        .foregroundStyle(Palette.inkFaint)
                } else {
                    ForEach(meals) { meal in
                        Button { selectedMeal = meal } label: {
                            TimelineMealRow(
                                title: meal.title,
                                detail: MealFormat.time(meal.loggedAt),
                                kcal: meal.kcal
                            )
                        }
                        .buttonStyle(PressableCard())
                    }
                }
            }
            .padding(Space.gutter)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.background)
        .task {
            meals = await model.meals(on: station.date)
            loading = false
        }
        .sheet(item: $selectedMeal) { meal in
            MealDetailSheet(meal: meal) {
                try await model.removeMeal(id: meal.id)
                meals = await model.meals(on: station.date)
            }
        }
    }
}

private struct RetryState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(message)
                .font(Typography.data(15))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
            ActionButton(title: "Try again", kind: .secondary, action: retry)
                .frame(maxWidth: 200)
        }
        .padding(28)
    }
}

#if DEBUG
#Preview("Loaded") {
    SettlementView(previewModel: .previewed(.sample))
        .environment(AppEnvironment.preview())
}

#Preview("Needs weigh-in") {
    SettlementView(previewModel: .previewed(.sampleNeedsWeighIn))
        .environment(AppEnvironment.preview())
}

#Preview("Empty") {
    SettlementView(previewModel: .previewed(.sampleEmpty))
        .environment(AppEnvironment.preview())
}

#Preview("Maintain") {
    SettlementView(previewModel: .previewed(.sampleMaintain))
        .environment(AppEnvironment.preview())
}
#endif
