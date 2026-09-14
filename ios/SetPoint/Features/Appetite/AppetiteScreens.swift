import SwiftUI

struct AppetitePickerSheet: View {
    var previewLevel: String? = nil
    var previewTarget = 2500
    var onPicked: () -> Void = {}

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var level = "NORMAL"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How hungry are you?")
                .font(Typography.display(32))
                .foregroundStyle(Palette.ink)
            Text(previewLine)
                .font(Typography.data(15))
                .foregroundStyle(Palette.inkSoft)
            ForEach(cards, id: \.id) { card in
                Button {
                    level = card.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.title)
                                .font(Typography.data(17, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            Text(card.detail)
                                .font(Typography.data(13))
                                .foregroundStyle(Palette.inkSoft)
                        }
                        Spacer()
                        miniBars(card.bars)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(level == card.id ? Palette.accentTint : Palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(level == card.id ? Palette.accent : Palette.hairline)
                    )
                }
                .buttonStyle(PressableCard())
            }
            ActionButton(title: "Use for today", kind: .primary) {
                Task { await save() }
            }
            NavigationLink {
                AppetiteSettingsView()
            } label: {
                Text("Always like this? Change in You → Appetite")
                    .font(Typography.data(14, weight: .bold))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(Space.gutter)
        .background(Palette.background.ignoresSafeArea())
        .onAppear { if let previewLevel { level = previewLevel } }
    }

    private var previewLine: String {
        switch level {
        case "HUNGRY": return "3 larger plates, same \(previewTarget.formatted()) kcal"
        case "LOW": return "5 lighter meals, same \(previewTarget.formatted()) kcal"
        default: return "Your usual 3 meals, \(previewTarget.formatted()) kcal"
        }
    }

    private var cards: [(id: String, title: String, detail: String, bars: [CGFloat])] {
        [
            ("HUNGRY", "Hungry", "Bigger plates, same total", [0.9, 0.85, 0.95]),
            ("NORMAL", "Normal", "Breakfast, lunch, dinner", [0.55, 0.7, 0.8]),
            ("LOW", "Not much", "Smaller, more often", [0.35, 0.4, 0.35, 0.4, 0.45]),
        ]
    }

    private func miniBars(_ heights: [CGFloat]) -> some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                Capsule()
                    .fill(Palette.ink.opacity(0.35))
                    .frame(width: 6, height: 22 * h)
            }
        }
        .frame(height: 22)
    }

    private func save() async {
        struct Body: Encodable { let level: String }
        do {
            try await env.api.put("/api/appetite/today", Body(level: level))
            onPicked()
            dismiss()
        } catch {
            dismiss()
        }
    }
}

struct AppetiteSettingsView: View {
    var previewMode: String? = nil

    @Environment(AppEnvironment.self) private var env
    @State private var mode = "NORMAL"
    @State private var drinkableOk = true
    @State private var target = 3120

    var body: some View {
        SettingsScreen(title: "Appetite", subtitle: "Same daily total. The plate size changes.") {
            ForEach(["NORMAL", "SMALL_FREQUENT"], id: \.self) { value in
                Button {
                    mode = value
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(value == "NORMAL" ? "Usual meals" : "Smaller, more often")
                                .font(Typography.data(17, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            Text(value == "NORMAL" ? "3 check-ins" : "5 check-ins follow the extra slots")
                                .font(Typography.data(13))
                                .foregroundStyle(Palette.inkSoft)
                        }
                        Spacer()
                        miniPreview(value == "SMALL_FREQUENT")
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(mode == value ? Palette.accentTint : Palette.surface)
                    )
                }
                .buttonStyle(PressableCard())
            }
            Toggle(isOn: $drinkableOk) {
                Text("Drink some of it")
                    .font(Typography.data(15, weight: .bold))
                    .foregroundStyle(Palette.ink)
            }
            .tint(Palette.accent)
            .padding(16)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text("Your \(target.formatted()) kcal")
                .font(Typography.data(14, weight: .semibold))
                .foregroundStyle(Palette.inkSoft)
            slotPreview

            HStack(spacing: 8) {
                ForEach(["Whole milk", "Nut butter", "Dates"], id: \.self) { chip in
                    Text(chip)
                        .font(Typography.data(12, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Palette.surfaceSunk, in: Capsule())
                }
            }

            ActionButton(title: saveTitle, kind: .primary) {
                Task { await save() }
            }
        }
        .task { await load() }
        .onAppear { if let previewMode { mode = previewMode } }
    }

    private var saveTitle: String {
        mode == "SMALL_FREQUENT" ? "Meals: 3 → 5 · check-ins follow" : "Keep 3 meals"
    }

    private var slotPreview: some View {
        let counts = mode == "SMALL_FREQUENT" ? 5 : 3
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<counts, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Palette.accent)
                    .frame(height: mode == "SMALL_FREQUENT" ? 36 : 56)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .bottom)
    }

    private func miniPreview(_ extra: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<(extra ? 5 : 3), id: \.self) { _ in
                Capsule().fill(Palette.ink.opacity(0.4)).frame(width: 5, height: extra ? 10 : 16)
            }
        }
    }

    private func load() async {
        if let settings: SettingsResponse = try? await env.api.get("/api/settings") {
            mode = settings.appetite?.mode ?? "NORMAL"
            drinkableOk = settings.appetite?.drinkableOk ?? true
            target = settings.dailyKcalTarget
        }
    }

    private func save() async {
        _ = try? await env.api.patch(
            "/api/settings",
            SettingsPatch(appetite: .init(mode: mode, drinkableOk: drinkableOk))
        )
    }
}
