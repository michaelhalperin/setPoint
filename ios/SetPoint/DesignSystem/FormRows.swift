import SwiftUI
import UIKit

// The design-v2 form vocabulary from the prototype: a step title (mono label +
// light headline with a dim tail), option rows, ± stepper rows inside a glass
// list, toggle rows and a glass text field.

/// A screen's question: a mono label, a light headline with a dim tail, and an
/// optional soft line under it.
struct StepTitle: View {
    let label: String
    let text: String
    var tail: String? = nil
    var detail: String? = nil
    var size: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(label)).sectionLabelStyle()
            Headline(text, tail: tail, size: size)
            if let detail {
                Text(LocalizedStringKey(detail))
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appearIn(0, rise: 16)
    }
}

/// A selectable row: optional icon tile, title, detail. Selected rows brighten
/// and gain a bone check.
struct OptionRow: View {
    let title: String
    var detail: String? = nil
    var symbol: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            HStack(spacing: 14) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(selected ? Palette.amber : Palette.ink)
                        .frame(width: 46, height: 46)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(title))
                        .font(Typography.data(16, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    if let detail {
                        Text(LocalizedStringKey(detail))
                            .font(Typography.data(13, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .strokeBorder(selected ? Palette.ink : Color.white.opacity(0.2), lineWidth: 1.5)
                    if selected {
                        Circle().fill(Palette.ink)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.onBone)
                    }
                }
                .frame(width: 22, height: 22)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(
                radius: 20,
                fill: selected ? Color.white.opacity(0.09) : Palette.glass,
                stroke: selected ? Color.white.opacity(0.32) : Palette.hairline
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selected)
        }
        .buttonStyle(PressableCard())
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A small glass circle with + or −.
struct StepCircle: View {
    let symbol: String
    let label: String
    var size: CGFloat = 36
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10)))
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(PressableCard())
        .disabled(!enabled)
        .accessibilityLabel(LocalizedStringKey(label))
    }
}

/// A list row with a name, a note, and a value nudged by − / +.
struct StepperRow: View {
    let name: String
    var note: String? = nil
    let value: String
    var valueWidth: CGFloat = 64
    var canDown = true
    var canUp = true
    let onDown: () -> Void
    let onUp: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(name))
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.ink)
                if let note {
                    Text(LocalizedStringKey(note))
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            Spacer(minLength: 8)
            StepCircle(symbol: "minus", label: L10n("Less \(L10nKey(name).lowercased())"), enabled: canDown, action: onDown)
            Text(value)
                .font(Typography.mono(16))
                .foregroundStyle(Palette.ink)
                .frame(width: valueWidth)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            StepCircle(symbol: "plus", label: L10n("More \(L10nKey(name).lowercased())"), enabled: canUp, action: onUp)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityValue(value)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canUp { onUp() }
            case .decrement: if canDown { onDown() }
            @unknown default: break
            }
        }
    }
}

/// A glass list. Put a `ListDivider()` between rows.
struct GlassList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .glass(radius: 24)
    }
}

/// The faint line between rows in a glass list.
struct ListDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }
}

/// A glass row with a title, detail and a switch.
struct ToggleRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    var tint: Color = Palette.ember

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.ink)
                if let detail {
                    Text(LocalizedStringKey(detail))
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
        }
        .tint(tint)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glass(radius: 20)
    }
}

/// A glass capsule text field.
struct GlassField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        TextField(LocalizedStringKey(prompt), text: $text)
            .font(Typography.data(15, weight: .regular))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 18)
            .frame(height: 50)
            .glassCapsule(fill: Color.white.opacity(0.05), stroke: Color.white.opacity(0.10))
    }
}

/// A row of dot-led lines ("· At most 4 a day…").
struct DotLines: View {
    let lines: [String]
    var dot: Color = Palette.amber

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(lines, id: \.self) { line in
                HStack(spacing: 10) {
                    Circle().fill(dot).frame(width: 6, height: 6)
                    Text(LocalizedStringKey(line))
                        .font(Typography.data(14, weight: .regular))
                        .foregroundStyle(Color(hex: 0xD4D4D8))
                }
            }
        }
    }
}
