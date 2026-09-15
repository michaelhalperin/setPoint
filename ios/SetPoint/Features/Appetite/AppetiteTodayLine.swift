import SwiftUI

/// Visibility and copy for the slim appetite capsule on Today.
enum AppetiteTodayVisibility: Equatable {
    case hidden
    case ask
    case answered(level: String)

    static func resolve(
        enforcementEnabled: Bool,
        appetite: HomeResponse.Appetite?,
        mealsToday: Int,
        changing: Bool = false,
        optimisticLevel: String? = nil
    ) -> AppetiteTodayVisibility {
        guard enforcementEnabled, let appetite else { return .hidden }
        if let optimisticLevel {
            return changing ? .ask : .answered(level: optimisticLevel)
        }
        if appetite.didAnswerToday {
            return changing ? .ask : .answered(level: appetite.level)
        }
        // Part 4 gates the morning ask on askDaily; treat missing as true.
        if appetite.askDaily == false { return .hidden }
        if mealsToday > 0 { return .hidden }
        return .ask
    }

    static func resolve(
        home: HomeResponse,
        changing: Bool = false,
        optimisticLevel: String? = nil
    ) -> AppetiteTodayVisibility {
        resolve(
            enforcementEnabled: home.enforcementEnabled,
            appetite: home.appetite,
            mealsToday: home.ledger.mealsToday,
            changing: changing,
            optimisticLevel: optimisticLevel
        )
    }
}

/// Slim capsule under Today's headline: ask Hungry/Normal/Low, or show today's answer.
struct AppetiteTodayLine: View {
    let home: HomeResponse
    var onChanged: () -> Void = {}

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var changing = false
    @State private var optimisticLevel: String?
    @State private var busy = false

    var body: some View {
        Group {
            switch AppetiteTodayVisibility.resolve(
                home: home,
                changing: changing,
                optimisticLevel: optimisticLevel
            ) {
            case .hidden:
                EmptyView()
            case .ask:
                askRow
            case let .answered(level):
                answeredRow(level)
            }
        }
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: optimisticLevel)
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: changing)
        .onChange(of: home.appetite?.level) { _, _ in clearOptimisticIfSynced() }
        .onChange(of: home.appetite?.answeredToday) { _, _ in clearOptimisticIfSynced() }
    }

    private var askRow: some View {
        HStack(spacing: 10) {
            Text("Appetite today?")
                .font(Typography.data(14, weight: .bold))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                ForEach([("HUNGRY", "Hungry"), ("NORMAL", "Normal"), ("LOW", "Low")], id: \.0) { id, title in
                    Button {
                        pick(id)
                    } label: {
                        Text(title)
                            .font(Typography.data(12, weight: .bold))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Palette.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceSunk, in: Capsule())
    }

    private func answeredRow(_ level: String) -> some View {
        HStack(spacing: 8) {
            if level == "LOW" {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
            }
            Text(answeredCopy(level))
                .font(Typography.data(14, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            Button("Change") { changing = true }
                .font(Typography.data(13, weight: .bold))
                .foregroundStyle(Palette.accent)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceSunk, in: Capsule())
    }

    private func answeredCopy(_ level: String) -> String {
        switch level {
        case "LOW": return "Low appetite · 5 smaller meals"
        case "HUNGRY": return "Hungry · bigger plates"
        default: return "Normal appetite"
        }
    }

    /// Flip the capsule immediately, then save + reload home in the background.
    private func pick(_ level: String) {
        optimisticLevel = level
        changing = false
        busy = true
        Task {
            struct Body: Encodable { let level: String }
            do {
                try await env.api.put("/api/appetite/today", Body(level: level))
                onChanged()
            } catch {
                optimisticLevel = nil
                changing = true
            }
            busy = false
        }
    }

    private func clearOptimisticIfSynced() {
        guard let optimisticLevel, let appetite = home.appetite, appetite.didAnswerToday else { return }
        if appetite.level == optimisticLevel {
            self.optimisticLevel = nil
        }
    }
}
