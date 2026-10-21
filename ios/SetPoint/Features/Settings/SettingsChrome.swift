import SwiftUI
import UIKit

/// Shared chrome for inner screens: round glass back, a light title, glass cards, rows, save bar.
struct SettingsScreen<Content: View>: View {
    /// The mono label in the header row (and the headline, unless `headline` is set).
    let title: String
    /// The dim tail after the headline.
    var subtitle: String? = nil
    /// Trailing item on the header row (a status pill, day arrows).
    var accessory: AnyView? = nil
    /// False when the screen is a tab's root — there's nowhere to go back to.
    var showsBack: Bool = true
    /// The light behind the title — haze for training screens.
    var glow: AmbientGlow.Tone = .ember
    /// A headline that differs from the label ("Your plan." under "Edit plan").
    var headline: String? = nil
    /// False on tab roots — the tab bar already names the screen.
    var showsHeadline: Bool = true
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if showsBack {
                    ZStack {
                        Text(LocalizedStringKey(title)).sectionLabelStyle()
                            .lineLimit(1)
                            .padding(.horizontal, 56)
                        HStack {
                            RoundIconButton("chevron.backward", label: "Back") { dismiss() }
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(minHeight: 40)
                }

                if showsHeadline || accessory != nil {
                    HStack(alignment: .center, spacing: 12) {
                        if showsHeadline {
                            Headline(headline ?? title, tail: subtitle, size: 34)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Spacer(minLength: 0)
                        }
                        if let accessory { accessory }
                    }
                    .appearIn(0, rise: 16)
                }

                content
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        #if DEBUG
        // Screenshots of the lower half of a stub: `-uiStub calendar-week -stubScrollBottom`.
        .defaultScrollAnchor(CommandLine.arguments.contains("-stubScrollBottom") ? .bottom : .top)
        #endif
        .background(alignment: .top) {
            AmbientGlow(tone: glow, strength: 0.55)
                .offset(y: -170)
                .ignoresSafeArea()
        }
        .background(Palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }
}

struct SettingsCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(radius: 24)
    }
}

struct SettingsRow: View {
    let symbol: String
    let title: String
    var value: String? = nil
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Palette.ink)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.06), in: Circle())
            Text(LocalizedStringKey(title))
                .font(Typography.data(16, weight: .regular))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            if let value {
                Text(LocalizedStringKey(value))
                    .font(Typography.data(14))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct SettingsSaveBar: View {
    let note: String?
    let saving: Bool
    let disabled: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let note {
                Text(LocalizedStringKey(note))
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ActionButton(title: "Save changes", busy: saving, busyTitle: "Saving", action: onSave)
                .opacity(disabled && !saving ? 0.45 : 1)
                .allowsHitTesting(!disabled && !saving)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(alignment: .top) {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Palette.background.opacity(0), Palette.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 24)
                Palette.background
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

struct SettingsErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(Typography.data(13, weight: .regular))
            .foregroundStyle(Palette.danger)
            .padding(Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(radius: Radius.sm, fill: Palette.danger.opacity(0.08), stroke: Palette.danger.opacity(0.25))
    }
}

extension View {
    func settingsSaveBar(
        visible: Bool,
        note: String?,
        saving: Bool,
        disabled: Bool,
        onSave: @escaping () -> Void
    ) -> some View {
        modifier(SettingsSaveBarInset(
            visible: visible,
            note: note,
            saving: saving,
            disabled: disabled,
            onSave: onSave
        ))
    }
}

private struct SettingsSaveBarInset: ViewModifier {
    let visible: Bool
    let note: String?
    let saving: Bool
    let disabled: Bool
    let onSave: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if visible {
                    SettingsSaveBar(note: note, saving: saving, disabled: disabled, onSave: onSave)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion), value: visible)
    }
}

/// Keeps the interactive pop gesture alive when the navigation bar is hidden.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
