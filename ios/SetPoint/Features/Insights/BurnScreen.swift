import SwiftUI

struct BurnScreen: View {
    var preview: BurnInsightResponse? = nil

    @Environment(AppEnvironment.self) private var env
    @State private var insight: BurnInsightResponse?
    @State private var error: String?

    var body: some View {
        SettingsScreen(title: "Your burn", subtitle: "What you really spend, from intake and the scale.") {
            if let insight {
                content(insight)
            } else if let error {
                SettingsErrorBanner(message: error)
                ActionButton(title: "Try again", kind: .secondary) { Task { await load() } }
            } else {
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ insight: BurnInsightResponse) -> some View {
        if insight.ready, let burn = insight.burnKcal, let low = insight.rangeLow, let high = insight.rangeHigh {
            VStack(alignment: .leading, spacing: 8) {
                Text("You really burn about \(burn.formatted()) kcal a day")
                    .font(Typography.voice(22))
                    .foregroundStyle(Palette.background)
                Text("likely \(low.formatted())–\(high.formatted())")
                    .font(Typography.data(15, weight: .semibold))
                    .foregroundStyle(Palette.onAccentVoice)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .appearIn(2)

            BurnChart(weeks: insight.weeks)
                .appearIn(3)

            SettingsCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(insight.planKcal.formatted()) a day keeps you on plan")
                        .font(Typography.data(17, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text("From \(insight.loggedDays) logged days and \(insight.weighIns) weigh-ins over \(insight.windowDays) days.")
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            .appearIn(4)
        } else {
            SettingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Not enough data yet")
                        .font(Typography.data(18, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text(emptyCopy(insight))
                        .font(Typography.data(14))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            .appearIn(2)
        }
    }

    private func emptyCopy(_ insight: BurnInsightResponse) -> String {
        switch insight.reason {
        case "not_enough_weighins":
            return "Log at least 6 weigh-ins in 8 weeks. You’ve logged \(insight.weighIns)."
        case "not_enough_logs":
            return "Log meals on at least 80% of days. \(insight.loggedDays) of \(insight.windowDays) so far."
        default:
            return "Keep logging meals and weigh-ins for a few more weeks. Need 28 logged days, 80% coverage, and 6 weigh-ins."
        }
    }

    private func load() async {
        if let preview {
            insight = preview
            return
        }
        do {
            insight = try await env.api.get("/api/insights/burn")
            error = nil
        } catch {
            self.error = UserFacingError.message(for: error, fallback: "Couldn't load your burn.")
        }
    }
}

struct BurnChart: View {
    let weeks: [BurnInsightResponse.Week]

    var body: some View {
        let maxKcal = max(weeks.map(\.intakeKcal).max() ?? 1, weeks.compactMap(\.burnHigh).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 10) {
            Text("Intake vs burn")
                .font(Typography.data(13, weight: .bold))
                .foregroundStyle(Palette.inkFaint)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let n = max(weeks.count, 1)
                let gap: CGFloat = 6
                let barW = max(4, (w - gap * CGFloat(n - 1)) / CGFloat(n))
                ZStack(alignment: .bottomLeading) {
                    if let first = weeks.first, let low = first.burnLow, let high = first.burnHigh {
                        let yLow = h * CGFloat(low) / CGFloat(maxKcal)
                        let yHigh = h * CGFloat(high) / CGFloat(maxKcal)
                        Rectangle()
                            .fill(Palette.accent.opacity(0.16))
                            .frame(width: w, height: max(4, yHigh - yLow))
                            .offset(y: -(yLow))
                    }
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(weeks) { week in
                            Capsule()
                                .fill(Palette.ink.opacity(0.78))
                                .frame(width: barW, height: max(4, h * CGFloat(week.intakeKcal) / CGFloat(maxKcal)))
                        }
                    }
                    if let burn = weeks.first?.burnKcal {
                        Rectangle()
                            .fill(Palette.accent)
                            .frame(width: w, height: 2)
                            .offset(y: -(h * CGFloat(burn) / CGFloat(maxKcal)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 140)
        }
        .padding(18)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
