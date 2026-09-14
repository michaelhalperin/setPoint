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
                if let range = dateRange(stations) {
                    Text(range)
                        .font(Typography.data(13, weight: .bold))
                        .foregroundStyle(Palette.inkFaint)
                        .accessibilityAddTraits(.isHeader)
                        .appearIn(0)
                }

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
                    if let err = model.weighInError {
                        Text(err)
                            .font(Typography.data(13, weight: .semibold))
                            .foregroundStyle(Palette.accentDeep)
                    }
                }

                if let review = s.targetReview {
                    TargetReviewCard(review: review, busy: model.applyingTargetReview) {
                        Task { await model.acceptTargetReview(review) }
                    } onLater: {
                        Task { await model.dismissTargetReview() }
                    }
                    .appearIn(4)
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
    private let wash = Palette.background.opacity(0.28)
    private let washStrong = Palette.background.opacity(0.42)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                SkeletonBlock(width: 92, height: 13)

                weekDials
                    .padding(.bottom, Space.xs)

                record
                weight
                intake
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDisabled(true)
        .background(Palette.background.ignoresSafeArea())
        .skeletonLoading()
    }

    private var weekDials: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 6) {
                    MiniDayDial(marks: [], today: index == 6)
                        .frame(width: 44, height: 44)
                    SkeletonBlock(width: 10, height: 12)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var record: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(width: 240, height: 28, radius: 8, tint: washStrong)
                SkeletonBlock(width: 196, height: 28, radius: 8, tint: wash)
            }
            HStack(spacing: Space.sm) {
                recordStat
                recordStat
                recordStat
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var recordStat: some View {
        VStack(alignment: .leading, spacing: 4) {
            SkeletonBlock(width: 36, height: 34, radius: 8, tint: washStrong)
            SkeletonBlock(width: 52, height: 12, tint: wash)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weight: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                SkeletonBlock(width: 88, height: 36, radius: 8)
                Spacer()
                SkeletonBlock(width: 72, height: 26, radius: Radius.pill)
            }
            Capsule().fill(Palette.surfaceSunk).frame(height: 54)
            HStack {
                SkeletonBlock(width: 72, height: 12)
                Spacer()
                SkeletonBlock(width: 108, height: 12)
            }
            SkeletonBlock(height: 52, radius: Radius.md)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hairline))
        }
    }

    private var intake: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SkeletonBlock(width: 56, height: 11)
                Spacer()
                SkeletonBlock(width: 132, height: 13)
            }
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { _ in
                    Capsule().fill(Palette.surfaceSunk).frame(height: 6)
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.hairline))
        }
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
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    SkeletonBlock(width: index == 1 ? 118 : 152, height: 16)
                                    SkeletonBlock(width: 64, height: 12)
                                }
                                Spacer(minLength: 8)
                                SkeletonBlock(width: 62, height: 14)
                            }
                            .padding(14)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .strokeBorder(Palette.hairline)
                            )
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

#Preview("Skeleton") {
    SettlementSkeletonView()
}
#endif
