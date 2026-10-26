import SwiftUI

struct SettlementView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: SettlementViewModel?
    @State private var showingWeighIn = false
    @State private var selectedStation: WeekStation?
    @State private var patternHandled = false
    @State private var patternApplied = false
    @State private var reloading = false

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
                if let since = model.staleSince {
                    StaleBanner(since: since) { Task { await model.load() } }
                }

                if let goal = s.weightGoal {
                    WeightJourneyCard(goal: goal, entries: model.weights, busy: model.loggingWeight) {
                        showingWeighIn = true
                    }
                    .appearIn(1, rise: 14)
                    if let err = model.weighInError {
                        Text(err)
                            .font(Typography.data(13, weight: .regular))
                            .foregroundStyle(Palette.danger)
                    }
                }

                if s.days.count < 3 {
                    WeekOneCard(settledDays: s.days.count, today: s.today, needsWeighIn: s.weightGoal?.needsWeighIn ?? model.weights.isEmpty)
                        .appearIn(2, rise: 14)
                } else {
                    DayOrbsCard(gap: s.gap, stations: stations) { selectedStation = $0 }
                        .appearIn(2, rise: 14)
                }

                if let record = s.record {
                    LandedCard(
                        record: record,
                        pattern: visiblePattern(record),
                        patternApplied: patternApplied,
                        patternBusy: model.applyingPattern,
                        onApply: {
                            guard let pattern = record.pattern else { return }
                            Task {
                                if await model.applyPattern(pattern) {
                                    Haptics.landed()
                                    withAnimation(Motion.settle) { patternApplied = true }
                                }
                            }
                        },
                        onKeep: {
                            guard let pattern = record.pattern else { return }
                            PatternMemory.dismiss(pattern)
                            withAnimation(Motion.settle) { patternHandled = true }
                        }
                    )
                    .appearIn(3, rise: 14)
                }

                if let review = s.targetReview {
                    TargetReviewCard(review: review, busy: model.applyingTargetReview) {
                        Task { await model.acceptTargetReview(review) }
                    } onLater: {
                        Task { await model.dismissTargetReview() }
                    }
                    .appearIn(4, rise: 14)
                }

                NavigationLink {
                    BurnScreen()
                } label: {
                    HStack(spacing: 12) {
                        FuelOrb(size: 34, breathing: false, glow: 0.4)
                            .frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("What you really burn")
                                .font(Typography.data(15, weight: .medium))
                                .foregroundStyle(Palette.ink)
                            Text("From what you eat and the scale")
                                .font(Typography.data(13, weight: .regular))
                                .foregroundStyle(Palette.inkSoft)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x52525B))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .glass(radius: 24, fill: Color.white.opacity(0.03))
                }
                .buttonStyle(PressableCard())
                .appearIn(5, rise: 14)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xl)
        }
        .pullToReload({ await model.load(showSpinner: false) }, covering: $reloading)
        .reloadCover(reloading) { SettlementSkeletonView() }
        .background(alignment: .top) { AmbientGlow(tone: .ember, strength: 0.6).offset(y: -140).ignoresSafeArea() }
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
            Text(L10n("\(MassUnit.current.formatKg(model.reachedGoalTarget ?? 0)) reached. Maintenance is now active."))
        }
    }

    /// The late-meal pattern while it's open, and after it's applied (to show "Moved").
    private func visiblePattern(_ record: SettlementResponse.Record) -> SettlementResponse.Record.Pattern? {
        guard let pattern = record.pattern else { return nil }
        if patternApplied { return pattern }
        if patternHandled || PatternMemory.isDismissed(pattern) { return nil }
        return pattern
    }

    private func reachedBinding(_ model: SettlementViewModel) -> Binding<Bool> {
        Binding(get: { model.reachedGoalTarget != nil }, set: { if !$0 { model.reachedGoalTarget = nil } })
    }
}

/// Progress while it loads: ghost bars rising and falling, a line drawing
/// itself where the weight goes.
private struct SettlementSkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(Palette.amber).frame(width: 6, height: 6)
                Text("COUNTING").font(Typography.mono(10)).tracking(1.1).foregroundStyle(Palette.inkFaint)
            }
            TimelineView(.animation(paused: reduceMotion)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                VStack(alignment: .leading, spacing: 14) {
                    SkeletonBlock(width: 210, height: 24, radius: 8)
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(Array([50, 64, 40, 70, 58, 30, 44].enumerated()), id: \.offset) { i, h in
                            let wave = reduceMotion ? 1 : 0.35 + 0.65 * (1 + sin(t * 2 * .pi / 1.6 - Double(i) * 0.7)) / 2
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(LinearGradient(colors: [Palette.amber.opacity(0.28), Palette.amber.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                                .frame(maxWidth: 34)
                                .frame(height: CGFloat(h) * wave)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 76, alignment: .bottom)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(radius: 26)
            }
            HStack(spacing: 14) {
                SkeletonBlock(width: 80, height: 28, radius: 8)
                Spacer()
                SkeletonBlock(width: 140, height: 20, radius: 8)
            }
            .padding(18)
            .glass(radius: 24)
            .shimmering()
            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock(width: 200, height: 14)
                SkeletonBlock(height: 10).opacity(0.6)
            }
            .padding(18)
            .glass(radius: 24)
            .shimmering()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) { AmbientGlow(tone: .ember, strength: 0.4).offset(y: -140).ignoresSafeArea() }
        .background(Palette.background.ignoresSafeArea())
        .accessibilityElement()
        .accessibilityLabel("Loading progress")
    }
}

/// The first days, before there's a week to read: day N of 7, and what unlocks when.
private struct WeekOneCard: View {
    let settledDays: Int
    let today: SettlementResponse.Today
    let needsWeighIn: Bool

    private var fraction: Double {
        guard today.kcalTarget > 0 else { return 0 }
        return min(1, Double(today.kcalConsumed) / Double(today.kcalTarget))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Headline(L10n("Day \(settledDays + 1) of 7."), tail: "Patterns need a week.", size: 32)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 6) {
                        if i < settledDays {
                            Circle().fill(Palette.amber).frame(width: 14, height: 14)
                                .frame(width: 42, height: 42)
                        } else if i == settledDays {
                            ZStack {
                                Circle().fill(AngularGradient(colors: [Palette.amber, Palette.amber], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * fraction)))
                                Circle().trim(from: fraction, to: 1).stroke(Color.white.opacity(0.08), lineWidth: 4).rotationEffect(.degrees(-90))
                                FuelOrb(size: 34, breathing: false, glow: 0.3)
                            }
                            .frame(width: 42, height: 42)
                            .shadow(color: Palette.amber.opacity(0.35), radius: 10)
                        } else {
                            Circle().strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                .frame(width: 32, height: 32)
                                .frame(width: 42, height: 42)
                        }
                        Text(i == settledDays ? L10n("TODAY") : label(i))
                            .font(Typography.mono(10))
                            .foregroundStyle(i == settledDays ? Palette.amber : Color(hex: 0x52525B))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(L10n("Day \(settledDays + 1) of 7"))

            VStack(alignment: .leading, spacing: 0) {
                step(when: L10n("Tonight"), title: L10n("Today closes"), note: L10n("You’ll see how close you got. \(today.kcalConsumed.formatted()) of \(today.kcalTarget.formatted()) so far."), lit: true, last: false)
                step(when: needsWeighIn ? L10n("This week") : L10n("Sunday"), title: needsWeighIn ? L10n("First weigh-in") : L10n("Next weigh-in"), note: L10n("Starts your weight line. One a week is enough."), lit: false, last: false)
                step(when: L10n("After 7 days"), title: L10n("One thing to fix"), note: L10n("Late meals, light breakfasts, what works on low days."), lit: false, last: true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(radius: 24)
        }
    }

    private func label(_ i: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: i - settledDays, to: .now) ?? .now
        return String(date.formatted(.dateTime.weekday(.narrow).locale(AppLanguage.current.locale)))
    }

    private func step(when: String, title: String, note: String, lit: Bool, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                Group {
                    if lit {
                        EmberDot(size: 12)
                    } else {
                        Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5).frame(width: 12, height: 12)
                    }
                }
                .padding(.top, 2)
                if !last {
                    Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1.5)
                        .mask(VStack(spacing: 3) { ForEach(0..<20, id: \.self) { _ in Rectangle().frame(height: 3) } })
                }
            }
            .frame(width: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(when.uppercased())
                    .font(Typography.mono(10))
                    .tracking(1)
                    .foregroundStyle(lit ? Palette.amber : Palette.inkFaint)
                Text(title)
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.ink)
                Text(note)
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, last ? 0 : 16)
        }
        .accessibilityElement(children: .combine)
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
                VStack(alignment: .leading, spacing: 10) {
                    Text(station.title).sectionLabelStyle()
                    Headline(
                        L10n("\(station.kcalConsumed.formatted()) of \(station.kcalTarget.formatted())."),
                        tail: station.isToday ? L10n("So far today.") : L10n("\(station.kindLabel)."),
                        size: 34,
                        persistTail: true
                    )
                    GeometryReader { geo in
                        Capsule().fill(Color.white.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(LinearGradient(colors: [Palette.ember, Palette.amber], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(6, geo.size.width * station.fill))
                            }
                    }
                    .frame(height: 6)
                    if let line = station.summaryLine {
                        Text(line)
                            .font(Typography.data(14, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
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
                            .glass(radius: Radius.lg)
                        }
                    }
                    .padding(.top, Space.xs)
                    .skeletonLoading()
                } else if meals.isEmpty {
                    Text("Nothing logged that day.")
                        .font(Typography.data(14, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(28)
                        .background {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                } else {
                    ForEach(meals) { meal in
                        Button { selectedMeal = meal } label: {
                            TodayMealRow(meal: meal)
                        }
                        .buttonStyle(PressableCard())
                    }
                }
            }
            .padding(Space.gutter)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheet)
        .task {
            meals = await model.meals(on: station.date)
            loading = false
        }
        .sheet(item: $selectedMeal) { meal in
            MealDetailSheet(
                meal: meal,
                onRemove: {
                    // Off the list and the sheet closed now; the server catches up.
                    selectedMeal = nil
                    meals.removeAll { $0.id == meal.id }
                    Task {
                        do {
                            try await model.removeMeal(id: meal.id)
                        } catch {
                            Haptics.nudge()
                            meals = await model.meals(on: station.date)
                        }
                    }
                },
                onFixed: { Task { meals = await model.meals(on: station.date) } }
            )
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
