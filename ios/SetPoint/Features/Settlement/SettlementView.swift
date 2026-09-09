import SwiftUI

struct SettlementView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: SettlementViewModel?

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
                    }
                    .frame(height: maxBarHeight)
                    .animation(
                        Motion.adaptive(Motion.gentle, reduceMotion: reduceMotion)
                            .delay(reduceMotion ? 0 : Double(index) * 0.04),
                        value: grown
                    )

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
