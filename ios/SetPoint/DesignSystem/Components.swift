import SwiftUI
import UIKit

/// A glass card — white at 4.5% with a 9% border. The app's default container.
struct Card<Content: View>: View {
    var tint: Color = Palette.glass
    var elevation: Elevation = .resting
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(tint)
                    .elevation(elevation)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                            .strokeBorder(Palette.hairline)
                    )
            }
    }
}

/// Three dots that light up in sequence — the in-button stand-in for a spinner
/// (§5a: never a spinner). Holds a mid-frame under Reduce Motion.
struct BusyDots: View {
    var tint: Color = Palette.ink
    var period: Double = 0.9

    var body: some View {
        LoopingPhase(period: period, still: 0.45) { t in
            HStack(spacing: 3.5) {
                ForEach(0..<3, id: \.self) { i in
                    let peak = (Double(i) + 0.5) / 3
                    let dist = min(abs(t - peak), 1 - abs(t - peak))
                    let lit = max(0, 1 - dist / 0.28)
                    Circle()
                        .fill(tint.opacity(0.22 + 0.78 * lit))
                        .frame(width: 5.5, height: 5.5)
                        .scaleEffect(0.82 + 0.18 * lit)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Title plus a working/done mark — used inside buttons so "Saving…" isn't just
/// a text swap.
struct BusyLabel: View {
    let title: String
    var busy = false
    var done = false
    var tint: Color = Palette.ink

    var body: some View {
        HStack(spacing: 8) {
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .transition(.scale.combined(with: .opacity))
            } else if busy {
                BusyDots(tint: tint)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
            Text(LocalizedStringKey(title))
                .contentTransition(.interpolate)
        }
    }
}

/// The main button. `.primary` is a bone capsule with the ember ball on the
/// right — one per screen. `.secondary` is a glass capsule.
struct ActionButton: View {
    enum Kind { case primary, secondary }

    let title: String
    var kind: Kind = .primary
    var busy: Bool = false
    var busyTitle: String? = nil
    var done: Bool = false
    var doneTitle: String? = nil
    /// The icon inside the ember ball on a primary button.
    var symbol: String = "arrow.forward"
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @GestureState private var pressed = false

    private var shownTitle: String {
        if done { return doneTitle ?? title }
        if busy { return busyTitle ?? title }
        return title
    }

    private var tint: Color { kind == .primary ? Palette.onBone : Palette.ink }

    var body: some View {
        Group {
            if kind == .primary {
                HStack(spacing: 12) {
                    BusyLabel(title: shownTitle, busy: busy && !done, done: done, tint: tint)
                        .font(Typography.data(16, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    EmberBall(size: 42) {
                        Image(systemName: done ? "checkmark" : symbol)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .opacity(busy && !done ? 0.55 : 1)
                }
                .foregroundStyle(tint)
                .padding(.leading, 24)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Capsule(style: .continuous).fill(Palette.ink))
            } else {
                BusyLabel(title: shownTitle, busy: busy && !done, done: done, tint: tint)
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .glassCapsule(fill: Color.white.opacity(0.06), stroke: Color.white.opacity(0.10))
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: pressed)
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: busy)
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: done)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($pressed) { _, state, _ in
                    guard !busy, !done, isEnabled else { return }
                    state = true
                }
                .onEnded { _ in
                    guard !busy, !done, isEnabled else { return }
                    action()
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(busy ? .updatesFrequently : [])
        .accessibilityLabel(shownTitle)
        .accessibilityAction { if !busy, !done { action() } }
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
            .font(Typography.data(15, weight: .medium))
            .foregroundStyle(kind == .primary ? Palette.onBone : Palette.ink)
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .background {
                if kind == .primary {
                    Capsule(style: .continuous).fill(Palette.ink)
                } else {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.10)))
                }
            }
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: pressed)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressed) { _, state, _ in state = true }
                    .onEnded { _ in action() }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title)
            .accessibilityAction { action() }
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

/// The manager "speaking" — a glass note with a thin bar: ember when it
/// matters, faint otherwise.
struct ManagerNote: View {
    let text: String
    var emphasised = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Capsule()
                .fill(emphasised ? Palette.ember : Palette.inkFaint.opacity(0.6))
                .frame(width: 3)
            Text(text)
                .font(Typography.voice(16))
                .foregroundStyle(Palette.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: Radius.lg, fill: emphasised ? Palette.ember.opacity(0.08) : Palette.glass)
    }
}

/// Shown when the manager is meant to be active but iOS notifications are
/// denied — the server-driven check-in can't actually reach the user, so the
/// core loop is silently dead until they re-enable it (plan §2).
struct NotificationsOffBanner: View {
    var compact = false

    var body: some View {
        Button {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: 10) {
                Circle().fill(Palette.ember).frame(width: 6, height: 6)
                Text("Notifications are off · check-ins can’t reach you")
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                Text("Turn on")
                    .font(Typography.data(13, weight: .medium))
                    .foregroundStyle(Palette.amber)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .glassCapsule(fill: Palette.ember.opacity(0.08), stroke: Palette.ember.opacity(0.28))
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel("Notifications are off, so check-ins can’t reach you. Turn them on.")
        .accessibilityHint("Opens the SetPoint section of the Settings app")
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
            .glass(radius: Radius.xl)
    }
}

extension View {
    func skeletonLoading() -> some View {
        self
            .shimmering()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
    }

    /// Pull past the top to reload. Always bounces so a short screen can still pull.
    func pullToReload(_ action: (() async -> Void)?) -> some View {
        modifier(PullReloadModifier(action: action, covering: nil))
    }

    /// Same pull, and `covering` fades a reload cover in and out — the scroll
    /// view stays mounted so the refresh isn't cancelled mid-flight.
    func pullToReload(_ action: (() async -> Void)?, covering: Binding<Bool>) -> some View {
        modifier(PullReloadModifier(action: action, covering: covering))
    }

    /// Crossfade a skeleton over live content. The content stays in the tree.
    func reloadCover<Skeleton: View>(_ active: Bool, @ViewBuilder skeleton: () -> Skeleton) -> some View {
        modifier(ReloadCoverModifier(active: active, skeleton: skeleton()))
    }
}

/// Pull-to-reload that outlives the refresh control: a gentle fade, a short
/// linger, then a fade back. Instant skeleton swaps feel like a snap.
enum PullReload {
    static let linger: UInt64 = 620_000_000

    @MainActor
    static func run(show: Binding<Bool>?, reduceMotion: Bool, work: @escaping () async -> Void) async {
        if let show, show.wrappedValue { return }
        let task = Task.detached { @MainActor in
            if let show {
                withAnimation(Motion.adaptive(Motion.gentle, reduceMotion: reduceMotion)) {
                    show.wrappedValue = true
                }
            }
            await work()
            try? await Task.sleep(nanoseconds: linger)
            if let show {
                withAnimation(Motion.adaptive(Motion.gentle, reduceMotion: reduceMotion)) {
                    show.wrappedValue = false
                }
            }
        }
        await task.value
    }
}

private struct PullReloadModifier: ViewModifier {
    let action: (() async -> Void)?
    var covering: Binding<Bool>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let action {
            content
                .scrollBounceBehavior(.always)
                .refreshable {
                    await PullReload.run(show: covering, reduceMotion: reduceMotion, work: action)
                }
        } else {
            content
        }
    }
}

private struct ReloadCoverModifier<Skeleton: View>: ViewModifier {
    let active: Bool
    let skeleton: Skeleton
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .overlay {
                if active {
                    skeleton
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(Motion.adaptive(Motion.gentle, reduceMotion: reduceMotion), value: active)
    }
}

/// A refresh failed but the screen still shows the last good data: say how old
/// it is and offer a retry, instead of replacing everything with an error.
struct StaleBanner: View {
    let since: Date
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Palette.hazeSoft)
            (Text("As of ") + Text(since.formatted(date: .omitted, time: .shortened)).font(Typography.mono(13)).foregroundColor(Palette.hazeSoft))
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Button(action: retry) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Color(hex: 0xE0E7FF))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Palette.haze.opacity(0.18), in: Capsule())
            }
            .buttonStyle(PressableCard())
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 40)
        .background(Capsule().fill(Color(hex: 0x151518)))
        .overlay(Capsule().strokeBorder(Palette.hazeSoft.opacity(0.35)))
        .shadow(color: Palette.haze.opacity(0.18), radius: 12)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Couldn’t refresh. Showing \(since.formatted(date: .omitted, time: .shortened)). Refresh")
    }
}
