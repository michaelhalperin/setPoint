import SwiftUI

/// Progress → Your burn: what you really burn, learned from meals and the scale.
struct BurnScreen: View {
    var preview: BurnInsightResponse? = nil
    /// Holds the loading skeleton (for the admin's Screen previews).
    var showsSkeleton = false

    @Environment(AppEnvironment.self) private var env
    @State private var insight: BurnInsightResponse?
    @State private var error: String?
    @State private var selectedWeek: Int?
    @State private var showingHelp = CommandLine.arguments.contains("-burnHelp")

    var body: some View {
        // Fixed to the screen: no scrolling. A very small phone falls back to scrolling the content.
        InnerScreen(spacing: 12, scrolls: false) {
            ScreenHeader(label: "Your burn") {
                RoundIconButton("questionmark", label: "How this works") { showingHelp = true }
            }

            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }.scrollIndicators(.hidden)
            }
        }
        .task { if !showsSkeleton { await load() } }
        .sheet(isPresented: $showingHelp) { BurnHelpSheet(insight: insight) }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let insight {
                if insight.ready, let burn = insight.burnKcal {
                    ready(insight, burn: burn)
                } else {
                    notReady(insight)
                }
            } else if let error {
                SettingsErrorBanner(message: error)
                ActionButton(title: "Try again", kind: .secondary) { Task { await load() } }
            } else {
                BurnSkeleton()
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: Ready

    @ViewBuilder
    private func ready(_ insight: BurnInsightResponse, burn: Int) -> some View {
        Headline(L10n("You burn \(burn.formatted())."), tail: "Learned from you, not guessed.", size: 30)
            .appearIn(0, rise: 16)

        ZStack {
            OrbRing(progress: coverage(insight))
                .frame(width: 198, height: 198)
            FuelOrb(size: 154, glow: 0.45)
            VStack(spacing: 2) {
                Text(burn.formatted())
                    .font(Typography.data(42, weight: .light))
                    .tracking(-1.7)
                Text("kcal a day")
                    .font(Typography.mono(11))
                    .foregroundStyle(Color(hex: 0xFDE6CF))
            }
            .foregroundStyle(Palette.ink)
            .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
        }
        .frame(maxWidth: .infinity)
        .appearIn(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n("You burn about \(burn.formatted()) calories a day"))

        if let low = insight.rangeLow, let high = insight.rangeHigh {
            Text(L10n("likely \(low.formatted())–\(high.formatted()) · from \(Int((coverage(insight) * 100).rounded()))% of days logged"))
                .font(Typography.mono(11))
                .foregroundStyle(Palette.inkSoft)
                .frame(maxWidth: .infinity)
        }

        if !insight.weeks.isEmpty {
            eatenVsBurn(insight.weeks, burn: burn).appearIn(2, rise: 14)
        }

        yourDay(burn: burn, plan: insight.planKcal).appearIn(3, rise: 14)

        sources(insight).appearIn(4)
    }

    private func coverage(_ insight: BurnInsightResponse) -> Double {
        guard insight.windowDays > 0 else { return 0 }
        return min(1, Double(insight.loggedDays) / Double(insight.windowDays))
    }

    /// Each week above or below the burn line — orange over, grey under. Tap a week.
    private func eatenVsBurn(_ weeks: [BurnInsightResponse.Week], burn: Int) -> some View {
        let selected = min(selectedWeek ?? weeks.count - 1, weeks.count - 1)
        let week = weeks[selected]
        let delta = week.intakeKcal - burn
        let maxDelta = max(250, weeks.map { abs($0.intakeKcal - burn) }.max() ?? 250)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Eaten vs burn").sectionLabelStyle()
                Spacer()
                Text(L10n("\(delta >= 0 ? "+" : "−")\(abs(delta).formatted()) kcal"))
                    .font(Typography.mono(11))
                    .foregroundStyle(delta >= 0 ? Palette.amber : Palette.inkSoft)
            }
            ZStack {
                Rectangle()
                    .fill(Palette.amber.opacity(0.75))
                    .frame(height: 1.5)
                    .shadow(color: Palette.amber.opacity(0.5), radius: 6)
                HStack {
                        Text("UNDER").font(Typography.mono(9)).foregroundStyle(Palette.inkFaint)
                    Spacer()
                    Text("BURN").font(Typography.mono(9)).foregroundStyle(Palette.amber)
                }
                .offset(y: 43)
                HStack(spacing: 8) {
                    ForEach(Array(weeks.enumerated()), id: \.element.id) { index, w in
                        let d = w.intakeKcal - burn
                        let height = max(3, CGFloat(abs(d)) / CGFloat(maxDelta) * 46)
                        let on = index == selected
                        Button { withAnimation(Motion.settle) { selectedWeek = index } } label: {
                            VStack(spacing: 0) {
                                ZStack(alignment: .bottom) {
                                    Color.clear
                                    if d >= 0 { bar(height: height, over: true, on: on) }
                                }
                                .frame(height: 50)
                                ZStack(alignment: .top) {
                                    Color.clear
                                    if d < 0 { bar(height: height, over: false, on: on) }
                                }
                                .frame(height: 50)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n("Week \(index + 1): \(abs(d)) \(d >= 0 ? L10n("over") : L10n("under")) your burn"))
                    }
                }
                .padding(.horizontal, 44)
            }
            .frame(height: 100)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("Week \(selected + 1) · ate \(week.intakeKcal.formatted()) a day"))
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.ink)
                Text(LocalizedStringKey(delta >= 0 ? "Over your burn — the scale should creep up." : "Under your burn, so the scale held still or dropped."))
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .padding(14)
        .glass(radius: 24)
    }

    private func bar(height: CGFloat, over: Bool, on: Bool) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: over ? 6 : 2, bottomLeadingRadius: over ? 2 : 6,
            bottomTrailingRadius: over ? 2 : 6, topTrailingRadius: over ? 6 : 2, style: .continuous
        )
        .fill(over ? AnyShapeStyle(LinearGradient(colors: [Palette.amber, Palette.ember], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.22)))
        .frame(maxWidth: 22)
        .frame(height: height)
        .opacity(on ? 1 : 0.5)
        .shadow(color: (over ? Palette.ember : .white).opacity(on ? 0.5 : 0), radius: 8)
    }

    /// burn + what the goal adds = your day.
    private func yourDay(burn: Int, plan: Int) -> some View {
        let delta = plan - burn
        return VStack(alignment: .leading, spacing: 10) {
            Text("So your day is").sectionLabelStyle()
            HStack(spacing: 8) {
                term(burn.formatted(), L10n("burn"), highlight: false)
                Text(delta >= 0 ? "+" : "−").foregroundStyle(Palette.inkFaint)
                term(abs(delta).formatted(), delta >= 0 ? L10n("for your goal") : L10n("to lose"), highlight: false)
                Text("=").foregroundStyle(Palette.inkFaint)
                term(plan.formatted(), L10n("your day"), highlight: true)
            }
            .font(Typography.data(18, weight: .light))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func term(_ value: String, _ label: String, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Typography.mono(17))
                .foregroundStyle(highlight ? Palette.amber : Palette.ink)
            Text(LocalizedStringKey(label))
                .font(Typography.data(11, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(highlight
                      ? AnyShapeStyle(LinearGradient(colors: [Palette.ember.opacity(0.16), Palette.ember.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                      : AnyShapeStyle(Color.white.opacity(0.04)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(highlight ? Color(hex: 0xFF8A50, opacity: 0.55) : Color.white.opacity(0.08))
        }
    }

    /// The logged days as a small grid, weigh-ins in haze.
    private func sources(_ insight: BurnInsightResponse) -> some View {
        HStack(spacing: 10) {
            let cols = Array(repeating: GridItem(.fixed(4), spacing: 2), count: 13)
            LazyVGrid(columns: cols, spacing: 2) {
                ForEach(0..<min(52, insight.loggedDays), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i % max(1, insight.loggedDays / max(1, insight.weighIns)) == 3 ? Palette.haze : Palette.amber.opacity(0.35 + Double(i) / 52 * 0.6))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: 13 * 6)
            .accessibilityHidden(true)
            Text(L10n("\(insight.loggedDays) logged days and \(insight.weighIns) weigh-ins over \(insight.windowDays) days. Updates every Sunday."))
                .font(Typography.data(12, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glass(radius: 18, fill: Color.white.opacity(0.025))
    }

    // MARK: Not ready

    @ViewBuilder
    private func notReady(_ insight: BurnInsightResponse) -> some View {
        Headline("Still learning your burn.", tail: "A few more weeks of meals and weigh-ins.", size: 32)
            .appearIn(0, rise: 16)

        FuelOrb(size: 150, dimmed: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

        VStack(alignment: .leading, spacing: 14) {
            requirement("Logged days", value: insight.loggedDays, goal: 28)
            requirement("Weigh-ins", value: insight.weighIns, goal: 6)
            Text(emptyCopy(insight))
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .hintCopy()
        }
        .padding(16)
        .glass(radius: 22)
        .appearIn(2)
    }

    private func requirement(_ title: String, value: Int, goal: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(LocalizedStringKey(title))
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(L10n("\(value) of \(goal)"))
                    .font(Typography.mono(11))
                    .foregroundStyle(value >= goal ? Palette.positive : Palette.inkSoft)
            }
            GeometryReader { geo in
                Capsule().fill(Color.white.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [Palette.ember, Palette.amber], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, geo.size.width * min(1, CGFloat(value) / CGFloat(goal))))
                    }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
    }

    private func emptyCopy(_ insight: BurnInsightResponse) -> String {
        switch insight.reason {
        case "not_enough_weighins":
            return L10n( "Log at least 6 weigh-ins in 8 weeks.")
        case "not_enough_logs":
            return L10n( "Log meals on at least 80% of days.")
        default:
            return L10n( "Need 28 logged days, 80% coverage, and 6 weigh-ins.")
        }
    }

    private func load() async {
        if let preview {
            insight = preview
            return
        }
        error = nil
        do {
            insight = try await env.api.get("/api/insights/burn")
            error = nil
        } catch {
            self.error = UserFacingError.message(for: error, fallback: L10n( "Couldn't load your burn."))
        }
    }
}

/// The shape of Your burn while it loads: the headline, the orb, the eaten-vs-burn bars, the day sum and
/// the sources line. The fixed words are real; the numbers are placeholders that shimmer on their own.
private struct BurnSkeleton: View {
    private let wash = Color.white.opacity(0.06)
    private let washStrong = Color.white.opacity(0.1)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock(width: 220, height: 28, radius: 9, tint: washStrong)
            }
            .shimmering()

            ZStack {
                Circle().stroke(washStrong, lineWidth: 8).frame(width: 198, height: 198)
                Circle().fill(wash).frame(width: 154, height: 154)
                VStack(spacing: 8) {
                    SkeletonBlock(width: 110, height: 40, radius: 10, tint: washStrong)
                    Text("kcal a day")
                        .font(Typography.mono(11))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .shimmering()
            .frame(maxWidth: .infinity)

            SkeletonBlock(width: 230, height: 11, tint: wash)
                .shimmering()
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Eaten vs burn").sectionLabelStyle()
                    Spacer()
                    SkeletonBlock(width: 70, height: 11, tint: wash).shimmering()
                }
                ZStack {
                    Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1.5)
                    HStack(spacing: 8) {
                        ForEach(0 ..< 8, id: \.self) { i in
                            let up = i % 2 == 0
                            VStack(spacing: 0) {
                                ZStack(alignment: .bottom) {
                                    Color.clear
                                    if up { bar(height: CGFloat([20, 34, 26, 40][i / 2])) }
                                }
                                .frame(height: 50)
                                ZStack(alignment: .top) {
                                    Color.clear
                                    if !up { bar(height: CGFloat([14, 28, 18, 32][i / 2])) }
                                }
                                .frame(height: 50)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 44)
                    .shimmering()
                }
                .frame(height: 100)
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBlock(width: 190, height: 13, tint: washStrong)
                    SkeletonBlock(width: 250, height: 11, tint: wash)
                }
                .shimmering()
            }
            .padding(16)
            .glass(radius: 24)

            VStack(alignment: .leading, spacing: 10) {
                Text("So your day is").sectionLabelStyle()
                HStack(spacing: 8) {
                    term("burn")
                    Text("+").foregroundStyle(Palette.inkFaint)
                    term("for your goal")
                    Text("=").foregroundStyle(Palette.inkFaint)
                    term("your day")
                }
                .font(Typography.data(18, weight: .light))
            }

            HStack(spacing: 10) {
                SkeletonBlock(width: 78, height: 26, radius: 6, tint: wash).shimmering()
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBlock(height: 11, tint: wash)
                    SkeletonBlock(width: 130, height: 11, tint: wash)
                }
                .shimmering()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glass(radius: 18, fill: Color.white.opacity(0.025))
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }

    private func bar(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(washStrong).frame(maxWidth: 22).frame(height: height)
    }

    private func term(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SkeletonBlock(width: 52, height: 16, radius: 5, tint: washStrong).shimmering()
            Text(LocalizedStringKey(label))
                .font(Typography.data(11, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }
}
