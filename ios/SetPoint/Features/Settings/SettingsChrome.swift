import SwiftUI
import UIKit

/// Shared chrome for Settings inner screens: round back, big serif title, cards, rows, save bar.
struct SettingsScreen<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 44, height: 44)
                            .background(Palette.surfaceSunk, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(Typography.display(38))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .appearIn(0)
                        if let subtitle {
                            Text(subtitle)
                                .font(Typography.data(16))
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                                .appearIn(1)
                        }
                    }
                }

                content
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
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
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Palette.surface)
                    .elevation(.resting)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
            }
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 36, height: 36)
                .background(Palette.surfaceSunk, in: Circle())
            Text(title)
                .font(Typography.data(16, weight: .bold))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(Typography.data(14))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
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
                Text(note)
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
            .font(Typography.data(13))
            .foregroundStyle(Palette.accentDeep)
            .padding(Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.accentTint, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
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
