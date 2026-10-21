import SwiftUI

/// Teaching lines under headlines and on empty states. Names, numbers, actions
/// and status stay visible. Default on — new users still get the gloss.
enum HintCopy {
    static let storageKey = "com.setpoint.app.showHints"
}

private struct ShowHintsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var showHints: Bool {
        get { self[ShowHintsKey.self] }
        set { self[ShowHintsKey.self] = newValue }
    }
}

/// Drops this view when Hints is off. Use on teaching copy only.
struct HintCopyGate<Content: View>: View {
    @Environment(\.showHints) private var showHints
    @ViewBuilder var content: Content

    var body: some View {
        if showHints { content }
    }
}

extension View {
    func hintCopy() -> some View {
        HintCopyGate { self }
    }
}

/// Reads the on-device preference and hands it down the tree.
struct HintCopyReader: ViewModifier {
    @AppStorage(HintCopy.storageKey) private var showHints = true

    func body(content: Content) -> some View {
        content.environment(\.showHints, showHints)
    }
}