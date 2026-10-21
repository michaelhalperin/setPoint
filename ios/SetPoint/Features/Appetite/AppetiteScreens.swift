import SwiftUI

/// You → Appetite: how hungry you've been, and what still got eaten.
struct AppetiteSettingsView: View {
    var previewHistory: AppetiteHistoryResponse? = nil
    var previewMode: String? = nil

    @Environment(AppEnvironment.self) private var env
    @State private var history: AppetiteHistoryResponse?
    @State private var mode = "NORMAL"
    @State private var drinkableOk = true
    @State private var askDaily = true
    @State private var mealTimes = MealTimesPayload.standard
    @State private var loading = true

    @State private var selectedDay: Int?

    var body: some View {
        InnerScreen(spacing: 16, onRefresh: { await load() }) {
            ScreenHeader(label: "Appetite · 4 weeks")

            if let history {
                hero(history).appearIn(0, rise: 16)
                tide(history).appearIn(1, rise: 14)
                dayReadout(history).appearIn(2)
                if let first = history.patterns.first {
                    patternCard(first).appearIn(3, rise: 14)
                }
                ForEach(history.patterns.dropFirst().prefix(1)) { pattern in
                    quietPattern(pattern)
                }
                if !history.lowDayFoods.isEmpty {
                    lowFoodsSection(history.lowDayFoods).appearIn(4)
                }
                lowDaySection.appearIn(5)
            } else if loading {
                AppetiteSkeletonView()
            } else {
                Headline("How hungry you’ve been.", tail: "Check back after a few days.", size: 34)
                lowDaySection
            }
        }
        .task { await load() }
        .onAppear {
            if let previewMode { mode = previewMode }
            if let previewHistory {
                history = previewHistory
                loading = false
            }
        }
    }

    // MARK: Hero

    private func hero(_ history: AppetiteHistoryResponse) -> some View {
        let lowCount = history.days.filter { $0.level == "LOW" }.count
        return HStack(alignment: .bottom, spacing: 14) {
            Text("\(lowCount)")
                .font(Typography.data(92, weight: .light))
                .tracking(-5)
                .foregroundStyle(Palette.ink)
                .frame(height: 76, alignment: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(lowCount == 1 ? L10n("low day") : L10n("low days"))
                    .font(Typography.data(22, weight: .light))
                    .foregroundStyle(Palette.ink)
                Text(history.percentEatenLowBefore.map { L10n("You still ate \(history.percentEatenLow)% on them · was \($0)%") } ?? L10n("You still ate \(history.percentEatenLow)% on them"))
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }
            .padding(.bottom, 4)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Tide

    private static func level(_ raw: String?) -> Double {
        switch raw {
        case "HUNGRY": return 1
        case "LOW": return 0.25
        default: return 0.6
        }
    }

    private func defaultDay(_ days: [AppetiteHistoryResponse.Day]) -> Int {
        days.lastIndex { $0.level == "LOW" } ?? max(0, days.count - 1)
    }

    private func pickDay(at x: CGFloat, width: CGFloat, count: Int) {
        guard count > 0 else { return }
        let n = max(1, count - 1)
        let t = (x - 6) / max(1, width - 12)
        pickDay(min(max(0, Int((t * CGFloat(n)).rounded())), count - 1))
    }

    private func pickDay(_ i: Int) {
        guard selectedDay != i else { return }
        selectedDay = i
        Haptics.select()
    }

    /// Appetite over four weeks as one curve: lows dip below the line and get a ring.
    private func tide(_ history: AppetiteHistoryResponse) -> some View {
        let days = history.days
        let raw = days.map { Self.level($0.level) }
        let smooth = raw.indices.map { i in
            0.5 * raw[i] + 0.25 * (raw[max(0, i - 1)] + raw[min(raw.count - 1, i + 1)])
        }
        let selected = selectedDay ?? defaultDay(days)
        return VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width, h: CGFloat = 150
                let n = max(1, days.count - 1)
                let pts = smooth.indices.map { CGPoint(x: 6 + CGFloat($0) / CGFloat(n) * (w - 12), y: 130 - CGFloat(smooth[$0]) * 120) }
                ZStack(alignment: .topLeading) {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 72)); p.addLine(to: CGPoint(x: w, y: 72))
                    }
                    .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    Text("Low")
                        .font(Typography.mono(9))
                        .foregroundStyle(Palette.inkFaint)
                        .position(x: w - 12, y: 62)

                    Self.curve(pts, close: h).fill(Palette.ember.opacity(0.16))
                    Self.curve(pts, close: nil)
                        .stroke(Palette.amber, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .shadow(color: Palette.amber.opacity(0.6), radius: 6)

                    if pts.indices.contains(selected) {
                        Rectangle().fill(Color.white.opacity(0.22)).frame(width: 1, height: h)
                            .position(x: pts[selected].x, y: h / 2)
                    }
                    ForEach(days.indices, id: \.self) { i in
                        if days[i].level == "LOW" {
                            Circle().strokeBorder(Palette.amber, lineWidth: 1.5)
                                .background(Circle().fill(Palette.background))
                                .frame(width: 11, height: 11)
                                .position(pts[i])
                        } else if days[i].level == nil {
                            Circle().fill(Color(hex: 0x52525B)).frame(width: 6, height: 6).position(pts[i])
                        }
                    }
                    if pts.indices.contains(selected) {
                        Circle().fill(Palette.amber).frame(width: 14, height: 14)
                            .shadow(color: Palette.amber.opacity(0.85), radius: 7)
                            .position(pts[selected])
                    }
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    pickDay(at: value.location.x, width: w, count: days.count)
                                }
                        )
                        .accessibilityElement()
                        .accessibilityLabel(L10n("Appetite over four weeks"))
                        .accessibilityValue(
                            days.indices.contains(selected)
                                ? L10n("\(Self.dayTitle(days[selected].date)), \(Self.word(days[selected].level))")
                                : ""
                        )
                        .accessibilityAdjustableAction { direction in
                            let i = selected
                            switch direction {
                            case .increment: pickDay(min(days.count - 1, i + 1))
                            case .decrement: pickDay(max(0, i - 1))
                            default: break
                            }
                        }
                }
            }
            .frame(height: 150)
            HStack {
                ForEach(Self.weekTicks(days), id: \.self) { tick in
                    Text(tick)
                    if tick != Self.weekTicks(days).last { Spacer() }
                }
            }
            .font(Typography.mono(10))
            .foregroundStyle(Palette.inkFaint)
        }
    }

    private static func curve(_ pts: [CGPoint], close: CGFloat?) -> Path {
        Path { p in
            guard let first = pts.first else { return }
            p.move(to: first)
            for i in 0..<(pts.count - 1) {
                let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(pts.count - 1, i + 2)]
                p.addCurve(
                    to: p2,
                    control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                    control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                )
            }
            if let close, let last = pts.last {
                p.addLine(to: CGPoint(x: last.x, y: close))
                p.addLine(to: CGPoint(x: first.x, y: close))
                p.closeSubpath()
            }
        }
    }

    private static func date(_ iso: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: iso)
    }

    private static func dayTitle(_ iso: String) -> String {
        date(iso)?.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppLanguage.current.locale)) ?? iso
    }

    private static func weekTicks(_ days: [AppetiteHistoryResponse.Day]) -> [String] {
        stride(from: 0, to: days.count, by: 7).compactMap { date(days[$0].date)?.formatted(.dateTime.day().month(.abbreviated).locale(AppLanguage.current.locale)).uppercased() }
    }

    private static func word(_ level: String?) -> String {
        switch level {
        case "HUNGRY": return L10n("Hungry")
        case "LOW": return L10n("Low")
        case nil: return L10n( "No check-in")
        default: return L10n("Normal")
        }
    }

    private func dayReadout(_ history: AppetiteHistoryResponse) -> some View {
        let days = history.days
        let i = min(max(0, selectedDay ?? defaultDay(days)), max(0, days.count - 1))
        let level = days.isEmpty ? nil : days[i].level
        return HStack(spacing: 12) {
            dot(level).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(days.isEmpty ? "—" : L10n("\(Self.dayTitle(days[i].date)) · \(Self.word(level))"))
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.ink)
                Text(LocalizedStringKey(level == "LOW" ? "Smaller plates that day" : level == nil ? "Nothing logged" : "Usual plates"))
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 8)
            StepCircle(symbol: "chevron.backward", label: "Previous day") { withAnimation(Motion.settle) { selectedDay = max(0, i - 1) } }
            StepCircle(symbol: "chevron.forward", label: "Next day") { withAnimation(Motion.settle) { selectedDay = min(days.count - 1, i + 1) } }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .glass(radius: 22)
    }

    /// Appetite as orb size: a big lit orb for hungry, a small ring for low.
    @ViewBuilder
    private func dot(_ level: String?) -> some View {
        switch level {
        case "HUNGRY":
            FuelOrb(size: 20, breathing: false, glow: 0.35)
        case "LOW":
            Circle().strokeBorder(Palette.amber.opacity(0.85), lineWidth: 1.5).frame(width: 12, height: 12)
        case nil:
            Circle().fill(Color.white.opacity(0.15)).frame(width: 6, height: 6)
        default:
            Circle().fill(Color.white.opacity(0.3)).frame(width: 13, height: 13)
        }
    }

    // MARK: Patterns

    private func patternCard(_ pattern: AppetiteHistoryResponse.Pattern) -> some View {
        CalloutCard(haze: true, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(Palette.haze).frame(width: 7, height: 7).shadow(color: Palette.haze, radius: 4)
                Text("What I noticed").sectionLabelStyle(Palette.hazeSoft)
            }
            Headline(pattern.localizedTitle.replacingOccurrences(of: " → ", with: ", ") + ".", tail: pattern.localizedBody, size: 22)
            if let action = pattern.action, let label = pattern.localizedActionLabel {
                BonePill(title: label) {
                    Task { await moveDinner(action.dinnerMin ?? 1200) }
                }
            }
        }
    }

    private func quietPattern(_ pattern: AppetiteHistoryResponse.Pattern) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: pattern.id == "late_dinner" ? "moon.stars.fill" : "dumbbell.fill")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Palette.hazeSoft)
                .frame(width: 34, height: 34)
                .background(Palette.haze.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(pattern.localizedTitle)
                    .font(Typography.data(15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(pattern.localizedBody)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 22)
    }

    private func lowFoodsSection(_ foods: [AppetiteHistoryResponse.LowDayFood]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What gets eaten on low days").sectionLabelStyle()
            VStack(spacing: 10) {
                ForEach(foods) { food in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(food.name)
                                .font(Typography.data(14, weight: .regular))
                                .foregroundStyle(Palette.ink)
                            Text(L10nKey(food.tag))
                                .font(Typography.data(11))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .frame(width: 140, alignment: .leading)
                        GeometryReader { geo in
                            Capsule().fill(Color.white.opacity(0.07))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(LinearGradient(colors: [Palette.ember, Palette.amber], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(6, geo.size.width * ratio(food)))
                                }
                        }
                        .frame(height: 6)
                        Text("\(food.eaten)/\(food.offered)")
                            .font(Typography.mono(11))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16)
            .glass(radius: 22)
        }
    }

    // MARK: On a low day

    private var lowDaySection: some View {
        let smaller = mode == "SMALL_FREQUENT"
        return VStack(alignment: .leading, spacing: 10) {
            Text("On a low day").sectionLabelStyle()
            HStack(spacing: 10) {
                plateTile("Usual plates", "3 a day", count: 3, size: 22, selected: !smaller) { setMode("NORMAL") }
                plateTile("Smaller plates", "5 a day, easier", count: 5, size: 13, selected: smaller) { setMode("SMALL_FREQUENT") }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ToggleChip(title: "Drinks count", on: drinkableOk) {
                    drinkableOk.toggle()
                    Task { await savePrefs() }
                }
                ToggleChip(title: "Ask me each morning", on: askDaily) {
                    askDaily.toggle()
                    Task { await savePrefs() }
                }
            }
        }
    }

    private func plateTile(_ title: String, _ note: String, count: Int, size: CGFloat, selected: Bool, action: @escaping () -> Void) -> some View {
        ChoiceTile(selected: selected, action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(0..<count, id: \.self) { _ in
                        if selected {
                            EmberDot(size: size, glow: 0.5)
                        } else {
                            Circle().fill(Color.white.opacity(0.18)).frame(width: size, height: size)
                        }
                    }
                }
                .frame(height: 34)
                Text(LocalizedStringKey(title))
                    .font(Typography.data(15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(LocalizedStringKey(note))
                    .font(Typography.mono(11))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
    }

    private func setMode(_ next: String) {
        guard mode != next else { return }
        withAnimation(Motion.settle) { mode = next }
        Task { await savePrefs() }
    }

    private func ratio(_ food: AppetiteHistoryResponse.LowDayFood) -> CGFloat {
        guard food.offered > 0 else { return 0 }
        return CGFloat(food.eaten) / CGFloat(food.offered)
    }

    // MARK: Networking

    private func load() async {
        if previewHistory != nil {
            loading = false
            return
        }
        let first = history == nil
        if first { loading = true }
        defer { loading = false }
        async let hist: AppetiteHistoryResponse? = try? await env.api.get("/api/appetite/history")
        async let settings: SettingsResponse? = try? await env.api.get("/api/settings")
        history = await hist
        if let settings = await settings {
            mode = settings.appetite?.mode ?? "NORMAL"
            drinkableOk = settings.appetite?.drinkableOk ?? true
            askDaily = settings.appetite?.askDaily ?? true
            mealTimes = settings.mealTimes
        }
    }

    private func savePrefs() async {
        _ = try? await env.api.patch(
            "/api/settings",
            SettingsPatch(appetite: .init(mode: mode, drinkableOk: drinkableOk, askDaily: askDaily))
        )
    }

    private func moveDinner(_ dinnerMin: Int) async {
        var times = mealTimes
        times.dinnerMin = dinnerMin
        mealTimes = times
        _ = try? await env.api.patch("/api/settings", SettingsPatch(mealTimes: times))
    }
}

#if DEBUG
extension AppetiteHistoryResponse {
    static var sample: AppetiteHistoryResponse {
        let start = "2026-08-24"
        var days: [Day] = []
        for i in 0..<28 {
            let date = Calendar.current.date(byAdding: .day, value: i, to: ISO8601DateFormatter().date(from: "\(start)T12:00:00Z")!)!
            let iso = ISO8601DateFormatter().string(from: date).prefix(10)
            let level: String?
            switch i % 7 {
            case 1, 2: level = "LOW"
            case 4: level = "HUNGRY"
            case 5: level = nil
            default: level = "NORMAL"
            }
            days.append(.init(date: String(iso), level: level))
        }
        return .init(
            days: days,
            percentEatenNormal: 97,
            percentEatenLow: 88,
            percentEatenLowBefore: 71,
            patterns: [
                .init(
                    id: "late_dinner",
                    title: "Late dinners → low mornings",
                    body: "4 of your 8 low days came after dinner past 21:00.",
                    action: .init(label: "Move dinner to 20:00", dinnerMin: 1200),
                    count: 4,
                    total: 8
                ),
                .init(
                    id: "after_training",
                    title: "Hungrier after training",
                    body: "3 of 4 hungry days were the day after a workout. I already add the calories.",
                    action: nil,
                    count: 3,
                    total: 4
                ),
            ],
            lowDayFoods: [
                .init(name: "Protein smoothie", tag: "Drinkable", eaten: 6, offered: 8),
                .init(name: "Peanut butter toast", tag: "No prep", eaten: 4, offered: 7),
                .init(name: "White rice", tag: "Dense", eaten: 2, offered: 5),
            ]
        )
    }
}
#endif

/// Mirrors the Appetite record layout while history + settings load.
private struct AppetiteSkeletonView: View {
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            weeksCard
            tiles
            noticed
            foods
            whenLow
        }
        .skeletonLoading()
    }

    private var weeksCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                SkeletonBlock(width: 96, height: 10)
                SkeletonBlock(width: 210, height: 28, radius: 8)
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(0..<7, id: \.self) { _ in
                        SkeletonBlock(height: 10)
                    }
                }
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(0..<28, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(i % 5 == 0 ? Color.white.opacity(0.05) : Color.white.opacity(0.06))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                HStack(spacing: 14) {
                    SkeletonBlock(width: 64, height: 12)
                    SkeletonBlock(width: 58, height: 12)
                    SkeletonBlock(width: 44, height: 12)
                }
                .padding(.top, 4)
            }
        }
    }

    private var tiles: some View {
        HStack(spacing: 10) {
            tile
            tile
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonBlock(width: 88, height: 10)
            SkeletonBlock(width: 72, height: 28, radius: 8)
            SkeletonBlock(width: 110, height: 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.hairline))
    }

    private var noticed: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(width: 112, height: 10)
            SettingsCard {
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(Color.white.opacity(0.06)).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBlock(width: 180, height: 16)
                        SkeletonBlock(height: 13)
                        SkeletonBlock(width: 220, height: 13)
                        SkeletonBlock(width: 148, height: 28, radius: Radius.pill)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    private var foods: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(width: 196, height: 10)
            SettingsCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        if index > 0 { ListDivider() }
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                SkeletonBlock(width: index == 1 ? 140 : 118, height: 15)
                                SkeletonBlock(width: 64, height: 11)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Capsule().fill(Color.white.opacity(0.06)).frame(width: 56, height: 6)
                                SkeletonBlock(width: 28, height: 11)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
            }
        }
    }

    private var whenLow: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(width: 148, height: 10)
            SettingsCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        if index > 0 { ListDivider() }
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                SkeletonBlock(width: index == 2 ? 148 : 92, height: 15)
                                SkeletonBlock(width: index == 0 ? 168 : 140, height: 12)
                            }
                            Spacer()
                            if index == 0 {
                                SkeletonBlock(width: 52, height: 14)
                            } else {
                                Capsule().fill(Color.white.opacity(0.06)).frame(width: 48, height: 28)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Appetite skeleton") {
    SettingsScreen(title: "Appetite", subtitle: "And what still got eaten.", headline: "How hungry you’ve been.") {
        AppetiteSkeletonView()
    }
}
#endif
