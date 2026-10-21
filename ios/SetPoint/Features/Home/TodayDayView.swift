import SwiftUI

/// Today → the pace pill: the day's meals under their slots, how much is in,
/// and protein. Tap a meal to fix or remove it.
struct TodayDayView: View {
    let home: HomeResponse
    let pending: TodayPending?
    let date: Date
    let onOpenMeal: (MealSummary) -> Void
    let onLogMissed: (HomeResponse.Day.Slot) -> Void
    let onLog: () -> Void

    var body: some View {
        screenBody.trackScreen("today_day")
    }

    @ViewBuilder
    private var screenBody: some View {
        let moment = TodayMoment.resolve(home)
        InnerScreen(spacing: 18) {
            ScreenHeader(label: "Today · \(date.formatted(.dateTime.day().month(.abbreviated)))")

            VStack(alignment: .leading, spacing: 10) {
                Headline(title, tail: tail, size: 38, persistTail: !home.enforcementEnabled || home.framing.state == "under")
                    .appearIn(0, rise: 16)
                progressBar
                    .appearIn(1)
            }

            FuelStrip(home: home, moment: moment)
                .appearIn(2)

            MealLog(
                home: home,
                pending: pending,
                onOpenMeal: onOpenMeal,
                onLogMissed: onLogMissed
            )
            .appearIn(3)

            ActionButton(title: "Log a meal", symbol: "plus", action: onLog)
                .padding(.top, Space.xs)
                .appearIn(4)
        }
    }

    private var title: String {
        "\(home.ledger.consumedKcal.formatted()) eaten."
    }

    private var tail: String {
        if !home.enforcementEnabled { return L10n( "No targets today.") }
        if home.framing.state != "under" { return L10n( "That’s the whole job.") }
        return L10n( "\(max(0, home.ledger.remainingKcal).formatted()) to go.")
    }

    private var progressBar: some View {
        let fraction = Double(home.ledger.consumedKcal) / Double(max(home.ledger.targetKcal, 1))
        return GeometryReader { geo in
            Capsule().fill(Color.white.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.ember, Palette.amber], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * min(1, max(0, fraction)))
                }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
