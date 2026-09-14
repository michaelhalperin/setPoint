import SwiftUI

struct SettlementView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: SettlementViewModel?
    @State private var showingWeighIn = false
    @State private var selectedStation: WeekStation?
    @State private var patternHandled = false

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
        let stations = s.weekStations
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Week")
                        .font(Typography.display(42))
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if let range = dateRange(stations) {
                        Text(range)
                            .font(Typography.data(13, weight: .bold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
                .appearIn(0)

                WeekDials(stations: stations, record: s.record) { selectedStation = $0 }
                    .padding(.bottom, Space.xs)

                if let record = s.record {
                    RecordCard(record: record)
                        .appearIn(1)

                    if let pattern = record.pattern, !PatternMemory.isDismissed(pattern), !patternHandled {
                        PatternCard(
                            pattern: pattern,
                            busy: model.applyingPattern,
                            onApply: {
                                Task {
                                    if await model.applyPattern(pattern) {
                                        Haptics.landed()
                                        withAnimation(Motion.settle) { patternHandled = true }
                                    }
                                }
                            },
                            onKeep: {
                                PatternMemory.dismiss(pattern)
                                withAnimation(Motion.settle) { patternHandled = true }
                            }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        .appearIn(2)
                    }
                }

                if let goal = s.weightGoal {
                    WeightTrendCard(goal: goal, entries: model.weights, busy: model.loggingWeight) {
                        showingWeighIn = true
                    }
                    .appearIn(3)
                }

                IntakeStrip(stations: stations)
                    .appearIn(4)
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
            WeighInSheet(lastKg: model.weights.last?.weightKg ?? s.weightGoal?.currentWeightKg) { kg in
                await model.logWeight(kg: kg)
            }
        }
        .alert("Target reached", isPresented: reachedBinding(model)) {
            Button("OK") { model.reachedGoalTarget = nil }
        } message: {
            Text("\(oneDp(model.reachedGoalTarget ?? 0)) kg reached. Maintenance is now active.")
        }
    }

    /// "8 – 14 Sep"
    private func dateRange(_ stations: [WeekStation]) -> String? {
        guard let first = stations.first.flatMap({ WeekStation.parse($0.date) }),
              let last = stations.last.flatMap({ WeekStation.parse($0.date) }) else { return nil }
        var utc = Date.FormatStyle.dateTime
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return "\(first.formatted(utc.day())) – \(last.formatted(utc.day().month(.abbreviated)))"
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
