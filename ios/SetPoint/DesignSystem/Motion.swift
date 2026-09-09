import SwiftUI

/// Plan §5a: springs, not durations. Tighter/faster springs for "manager's voice"
/// moments so the app feels responsive without feeling urgent. Everything here
/// respects Reduce Motion.
enum Motion {
    static let standard = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.30, dampingFraction: 0.86)
    static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.90)
    static let sheet = Animation.spring(response: 0.38, dampingFraction: 0.85)

    /// A plain crossfade when Reduce Motion is on (§5a: "one-line guard").
    static func adaptive(_ spring: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : spring
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
