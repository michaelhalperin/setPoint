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

    var body: some View {
        SettingsScreen(
            title: "Appetite",
            subtitle: "How hungry you've been, and what still got eaten."
        ) {
            if let history {
                lastFourWeeks(history)
                eatenTiles(history)
                if !history.patterns.isEmpty {
                    noticedSection(history.patterns)
                }
                if !history.lowDayFoods.isEmpty {
                    lowFoodsSection(history.lowDayFoods)
                }
                whenLowSection
            } else if loading {
                AppetiteSkeletonView()
            } else {
                whenLowSection
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

    // MARK: Sections

    private func lastFourWeeks(_ history: AppetiteHistoryResponse) -> some View {
        let lowCount = history.days.filter { $0.level == "LOW" }.count
        return SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("LAST 4 WEEKS")
                    .font(Typography.data(11, weight: .heavy))
                    .foregroundStyle(Palette.inkFaint)
                    .tracking(0.6)
                Text("Low on \(lowCount) of 28 days")
                    .font(Typography.display(28))
                    .foregroundStyle(Palette.ink)

                appetiteGrid(history.days)

                HStack(spacing: 14) {
                    legend(swatch: Palette.accent, label: "Hungry")
                    legend(swatch: Palette.surfaceSunk, label: "Normal")
                    legend(bordered: true, label: "Low")
                }
                .padding(.top, 4)
            }
        }
    }

    private func appetiteGrid(_ days: [AppetiteHistoryResponse.Day]) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let headers = ["M", "T", "W", "T", "F", "S", "S"]
        let todayISO: String = {
            let f = DateFormatter()
            f.calendar = Calendar.current
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()
        return VStack(spacing: 6) {
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(headers.indices, id: \.self) { i in
                    Text(headers[i])
                        .font(Typography.data(10, weight: .bold))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(days) { day in
                    dayCell(day, isToday: day.date == todayISO)
                }
            }
        }
    }

    private func dayCell(_ day: AppetiteHistoryResponse.Day, isToday: Bool) -> some View {
        let level = day.level
        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(cellFill(level))
                .overlay {
                    if level == "LOW" {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Palette.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    }
                    if isToday {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Palette.ink, lineWidth: 2)
                    }
                }
            if level == "HUNGRY" {
                Text("H")
                    .font(Typography.data(9, weight: .heavy))
                    .foregroundStyle(Palette.background)
            } else if level == "LOW" {
                Text("L")
                    .font(Typography.data(9, weight: .heavy))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .opacity(level == nil ? 0.45 : 1)
    }

    private func cellFill(_ level: String?) -> Color {
        switch level {
        case "HUNGRY": return Palette.accent
        case "LOW": return Palette.surface
        default: return Palette.surfaceSunk
        }
    }

    private func legend(swatch: Color? = nil, bordered: Bool = false, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(swatch ?? Palette.surface)
                .overlay {
                    if bordered {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(Palette.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    }
                }
                .frame(width: 12, height: 12)
            Text(label)
                .font(Typography.data(12, weight: .semibold))
                .foregroundStyle(Palette.inkSoft)
        }
    }

    private func eatenTiles(_ history: AppetiteHistoryResponse) -> some View {
        HStack(spacing: 10) {
            tile(label: "NORMAL DAYS", value: "\(history.percentEatenNormal)%", detail: "of target eaten", accent: false)
            tile(
                label: "LOW DAYS",
                value: "\(history.percentEatenLow)%",
                detail: history.percentEatenLowBefore.map { "up from \($0)% before smaller plates" } ?? "of target eaten",
                accent: true
            )
        }
    }

    private func tile(label: String, value: String, detail: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Typography.data(11, weight: .heavy))
                .foregroundStyle(Palette.inkFaint)
                .tracking(0.5)
            Text(value)
                .font(Typography.data(28, weight: .bold))
                .foregroundStyle(accent ? Palette.accent : Palette.ink)
                .monospacedDigit()
            Text(detail)
                .font(Typography.data(12))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.hairline))
    }

    private func noticedSection(_ patterns: [AppetiteHistoryResponse.Pattern]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT I NOTICED")
                .font(Typography.data(11, weight: .heavy))
                .foregroundStyle(Palette.inkFaint)
                .tracking(0.6)
            ForEach(patterns.prefix(2)) { pattern in
                SettingsCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: pattern.id == "late_dinner" ? "moon.stars.fill" : "dumbbell.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 36, height: 36)
                            .background(Palette.accentTint, in: Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(pattern.title)
                                .font(Typography.data(16, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            Text(pattern.body)
                                .font(Typography.data(14))
                                .foregroundStyle(Palette.inkSoft)
                            if let action = pattern.action {
                                Button {
                                    Task { await moveDinner(action.dinnerMin ?? 1200) }
                                } label: {
                                    Text(action.label)
                                        .font(Typography.data(13, weight: .bold))
                                        .foregroundStyle(Palette.accent)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Palette.accentTint, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 4)
                            }
                        }
                    }
                }
            }
        }
    }

    private func lowFoodsSection(_ foods: [AppetiteHistoryResponse.LowDayFood]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT GETS EATEN ON LOW DAYS")
                .font(Typography.data(11, weight: .heavy))
                .foregroundStyle(Palette.inkFaint)
                .tracking(0.6)
            SettingsCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(foods.enumerated()), id: \.element.id) { index, food in
                        if index > 0 { Divider().overlay(Palette.hairline) }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.name)
                                    .font(Typography.data(15, weight: .bold))
                                    .foregroundStyle(Palette.ink)
                                Text(food.tag)
                                    .font(Typography.data(12))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                GeometryReader { geo in
                                    Capsule().fill(Palette.surfaceSunk)
                                        .overlay(alignment: .leading) {
                                            Capsule().fill(Palette.dayOnTrack)
                                                .frame(width: geo.size.width * ratio(food))
                                        }
                                }
                                .frame(width: 56, height: 6)
                                Text("\(food.eaten)/\(food.offered)")
                                    .font(Typography.data(11, weight: .semibold))
                                    .foregroundStyle(Palette.inkFaint)
                                    .monospacedDigit()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private var whenLowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHEN APPETITE IS LOW")
                .font(Typography.data(11, weight: .heavy))
                .foregroundStyle(Palette.inkFaint)
                .tracking(0.6)
            SettingsCard(padding: 0) {
                VStack(spacing: 0) {
                    settingsRow(
                        title: "Plate size",
                        subtitle: mode == "SMALL_FREQUENT"
                            ? "Smaller plates, 5 check-ins"
                            : "Usual 3 meals, 3 check-ins",
                        trailing: plateSizeSwitch
                    )
                    .padding(.vertical, 4)
                    Divider().overlay(Palette.hairline)
                    Toggle(isOn: Binding(
                        get: { drinkableOk },
                        set: { drinkableOk = $0; Task { await savePrefs() } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Drinks count")
                                .font(Typography.data(16, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            Text("Smoothies, milk, shakes")
                                .font(Typography.data(13))
                                .foregroundStyle(Palette.inkSoft)
                        }
                    }
                    .tint(Palette.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    Divider().overlay(Palette.hairline)
                    Toggle(isOn: Binding(
                        get: { askDaily },
                        set: { askDaily = $0; Task { await savePrefs() } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ask me each morning")
                                .font(Typography.data(16, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            Text("Before breakfast, once a day")
                                .font(Typography.data(13))
                                .foregroundStyle(Palette.inkSoft)
                        }
                    }
                    .tint(Palette.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private var plateSizeSwitch: some View {
        let smaller = mode == "SMALL_FREQUENT"
        return HStack(spacing: 0) {
            plateSizeOption("Usual", selected: !smaller) {
                setMode("NORMAL")
            }
            plateSizeOption("Smaller", selected: smaller) {
                setMode("SMALL_FREQUENT")
            }
        }
        .padding(3)
        .background(Palette.surfaceSunk, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plate size")
    }

    private func plateSizeOption(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typography.data(12, weight: .bold))
                .foregroundStyle(selected ? Palette.ink : Palette.inkSoft)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    if selected {
                        Capsule().fill(Palette.surface)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func setMode(_ next: String) {
        guard mode != next else { return }
        mode = next
        Task { await savePrefs() }
    }

    private func settingsRow<Trailing: View>(title: String, subtitle: String, trailing: Trailing) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.data(16, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                    action: .init(label: "Move dinner to 20:00", dinnerMin: 1200)
                ),
                .init(
                    id: "after_training",
                    title: "Hungrier after training",
                    body: "3 of 4 hungry days were the day after a workout. I already add the calories.",
                    action: nil
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
                            .fill(i % 5 == 0 ? Palette.surfaceSunk.opacity(0.7) : Palette.surfaceSunk)
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
                    Circle().fill(Palette.surfaceSunk).frame(width: 36, height: 36)
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
                        if index > 0 { Divider().overlay(Palette.hairline) }
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                SkeletonBlock(width: index == 1 ? 140 : 118, height: 15)
                                SkeletonBlock(width: 64, height: 11)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Capsule().fill(Palette.surfaceSunk).frame(width: 56, height: 6)
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
                        if index > 0 { Divider().overlay(Palette.hairline) }
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                SkeletonBlock(width: index == 2 ? 148 : 92, height: 15)
                                SkeletonBlock(width: index == 0 ? 168 : 140, height: 12)
                            }
                            Spacer()
                            if index == 0 {
                                SkeletonBlock(width: 52, height: 14)
                            } else {
                                Capsule().fill(Palette.surfaceSunk).frame(width: 48, height: 28)
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
    SettingsScreen(title: "Appetite", subtitle: "How hungry you've been, and what still got eaten.") {
        AppetiteSkeletonView()
    }
}
#endif
