import SwiftUI

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
