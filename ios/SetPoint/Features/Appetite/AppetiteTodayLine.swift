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
    var onChanged: () async -> Void = {}

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
        GlassCard(spacing: 14) {
            Text("Morning · appetite").sectionLabelStyle()
            Headline("How’s your appetite today?", tail: "I’ll shape the plates.", size: 26)
            HStack(spacing: 8) {
                ForEach(Self.options, id: \.id) { option in
                    Button {
                        pick(option.id)
                    } label: {
                        VStack(spacing: 6) {
                            FuelOrb(size: option.orb, breathing: false, glow: 0.25)
                                .frame(height: 30)
                            Text(LocalizedStringKey(option.title))
                                .font(Typography.data(15, weight: .medium))
                                .foregroundStyle(Palette.ink)
                            Text(LocalizedStringKey(option.note))
                                .font(Typography.data(11, weight: .regular))
                                .foregroundStyle(Palette.inkSoft)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity)
                        .glass(radius: 18, fill: Color.white.opacity(0.05), stroke: Color.white.opacity(0.10))
                    }
                    .buttonStyle(PressableCard())
                    .disabled(busy)
                    .accessibilityLabel(L10n("\(option.title), \(option.note)"))
                }
            }
        }
    }

    private static let options: [(id: String, title: String, note: String, orb: CGFloat)] = [
        ("HUNGRY", "Hungry", "Bigger plates", 30),
        ("NORMAL", "Normal", "As planned", 22),
        ("LOW", "Low", "5 small meals", 15),
    ]

    private func answeredRow(_ level: String) -> some View {
        HStack(spacing: 8) {
            AppetiteBars(level: level)
            Text(answeredCopy(level))
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            Button("Change") { changing = true }
                .font(Typography.data(13, weight: .medium))
                .foregroundStyle(Palette.amber)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCapsule()
    }

    private func answeredCopy(_ level: String) -> String {
        switch level {
        case "LOW": return L10n( "Low appetite · 5 smaller meals")
        case "HUNGRY": return L10n( "Hungry · bigger plates")
        default: return L10n( "Normal appetite")
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
                await onChanged()
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
