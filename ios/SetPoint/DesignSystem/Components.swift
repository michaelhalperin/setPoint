import SwiftUI

/// A card surface — soft, warm, lifting gently off the paper ground. The app's
/// default container.
struct Card<Content: View>: View {
    var tint: Color = Palette.surface
    var elevation: Elevation = .resting
    var padding: CGFloat = Space.md - 2
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(tint)
                    .elevation(elevation)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(Palette.hairline)
                    )
            }
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
            .background {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(kind == .primary ? Palette.accent : Palette.surfaceSunk)
                    .elevation(kind == .primary && !pressed ? .resting : .flat)
            }
            .scaleEffect(pressed ? 0.97 : 1)
            .brightness(pressed && kind == .primary ? -0.04 : 0)
            .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: pressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressed) { _, state, _ in state = true }
                    .onEnded { _ in action() }
            )
    }
}

/// A compact CTA for sticky bars — not full-width.
struct PillButton: View {
    enum Kind { case primary, secondary }

    let title: String
    var kind: Kind = .primary
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var pressed = false

    var body: some View {
        Text(title)
            .font(Typography.data(15, weight: .semibold))
            .foregroundStyle(kind == .primary ? Color.white : Palette.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background {
                Capsule(style: .continuous)
                    .fill(kind == .primary ? Palette.accent : Palette.surfaceSunk)
                    .elevation(kind == .primary && !pressed ? .resting : .flat)
            }
            .scaleEffect(pressed ? 0.97 : 1)
            .brightness(pressed && kind == .primary ? -0.04 : 0)
            .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: pressed)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressed) { _, state, _ in state = true }
                    .onEnded { _ in action() }
            )
    }
}

/// A tappable card that presses in — scales down slightly, shadow softens.
struct PressableCard: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// The manager "speaking" — editorial serif on a faintly tinted surface, clearly
/// distinct from the cold data around it (§6).
struct ManagerNote: View {
    let text: String
    var emphasised = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(emphasised ? Palette.accent : Palette.inkFaint)
                .frame(width: 3)
            Text(text)
                .font(Typography.voice(17))
                .foregroundStyle(Palette.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (emphasised ? Palette.accentTint : Palette.surfaceSunk.opacity(0.6)),
            in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        )
    }
}

/// Building blocks used by each destination to mirror its own loaded layout.
struct SkeletonBlock: View {
    var width: CGFloat?
    let height: CGFloat
    var radius: CGFloat = 7
    var tint: Color = Palette.surfaceSunk

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(tint)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width, height: height)
    }
}

struct SkeletonCard<Content: View>: View {
    var height: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(Space.md)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(Palette.hairline)
            }
    }
}

extension View {
    func skeletonLoading() -> some View {
        self
            .shimmering()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
    }
}
