import SwiftUI

/// A card surface — soft, warm, low elevation. The app's default container.
struct Card<Content: View>: View {
    var tint: Color = Palette.surface
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(0.05))
            )
    }
}

/// The primary action button. Accent-filled only where the plan allows a primary
/// CTA (under-eating); everything else uses `.secondary`.
struct ActionButton: View {
    enum Kind { case primary, secondary }

    let title: String
    var kind: Kind = .primary
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var pressed = false

    var body: some View {
        Text(title)
            .font(Typography.data(16, weight: .semibold))
            .foregroundStyle(kind == .primary ? Color.white : Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                kind == .primary ? Palette.accent : Palette.surfaceSunk,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: pressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressed) { _, state, _ in state = true }
                    .onEnded { _ in action() }
            )
    }
}

/// The manager "speaking" — editorial serif on a faintly tinted surface, clearly
/// distinct from the cold data around it (§6).
struct ManagerNote: View {
    let text: String
    var emphasised = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(emphasised ? Palette.accent : Palette.inkFaint)
                .frame(width: 3)
            Text(text)
                .font(Typography.voice(17))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (emphasised ? Palette.accentSoft.opacity(0.5) : Palette.surfaceSunk.opacity(0.6)),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}
