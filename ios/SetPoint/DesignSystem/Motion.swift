import SwiftUI

/// Plan §5a: springs, not durations. Tighter/faster springs for "manager's voice"
/// moments so the app feels responsive without feeling urgent. Everything here
/// respects Reduce Motion.
enum Motion {
    static let standard = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.30, dampingFraction: 0.86)
    static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.90)
    static let sheet = Animation.spring(response: 0.38, dampingFraction: 0.85)

    // Role-named springs (Pass 0). Prefer these at call sites so choreography is
    // described by intent, not by tuning numbers.
    /// Content arriving — lists, cards, revealed sections.
    static let enter = Animation.spring(response: 0.44, dampingFraction: 0.86)
    /// Content leaving.
    static let exit = Animation.spring(response: 0.30, dampingFraction: 0.90)
    /// A shared-element morph (card ↔ full screen). Slightly slower, very settled.
    static let morph = Animation.spring(response: 0.46, dampingFraction: 0.82)
    /// A small attention beat — the manager wants you to look.
    static let nudge = Animation.spring(response: 0.32, dampingFraction: 0.6)
    /// A value landing on its final state after a gesture.
    static let settle = Animation.spring(response: 0.34, dampingFraction: 0.88)

    /// Per-item entrance delay for a staggered sequence (§5a — ~40 ms steps,
    /// capped so long lists don't crawl). Zero under Reduce Motion.
    static func stagger(_ index: Int, step: Double = 0.04, cap: Int = 8, reduceMotion: Bool = false) -> Double {
        reduceMotion ? 0 : Double(min(index, cap)) * step
    }

    /// A plain crossfade when Reduce Motion is on (§5a: "one-line guard").
    static func adaptive(_ spring: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : spring
    }
}

/// A drop-in staggered entrance: fade + a small rise, delayed by index.
struct AppearIn: ViewModifier {
    var index: Int = 0
    var rise: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : rise)
            .onAppear {
                withAnimation(
                    Motion.adaptive(Motion.enter, reduceMotion: reduceMotion)
                        .delay(Motion.stagger(index, reduceMotion: reduceMotion))
                ) { shown = true }
            }
    }
}

extension View {
    /// Fade + rise in, optionally staggered by `index`.
    func appearIn(_ index: Int = 0, rise: CGFloat = 8) -> some View {
        modifier(AppearIn(index: index, rise: rise))
    }

    /// Reveal driven by a Bool (not `onAppear`) — for content that's always in
    /// the tree but should cascade in when a gate flips, e.g. sheet actions
    /// after a morph settles.
    func staggerReveal(_ isOn: Bool, index: Int, rise: CGFloat = 12) -> some View {
        modifier(StaggerReveal(isOn: isOn, index: index, rise: rise))
    }
}

struct StaggerReveal: ViewModifier {
    let isOn: Bool
    let index: Int
    var rise: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isOn ? 1 : 0)
            .offset(y: isOn ? 0 : rise)
            .animation(
                Motion.adaptive(Motion.enter, reduceMotion: reduceMotion)
                    .delay(isOn ? Motion.stagger(index, reduceMotion: reduceMotion) : 0),
                value: isOn
            )
    }
}

/// A single soft pulse on first appearance — never looping (§5a: a repeating
/// alert reads as nagging and works against the "manager, not punisher" tone).
private struct FirstAppearPulse: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                guard active, !reduceMotion else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.5)) { scale = 1.05 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { scale = 1 }
                }
            }
    }
}

extension View {
    func firstAppearPulse(_ active: Bool = true) -> some View {
        modifier(FirstAppearPulse(active: active))
    }
}
