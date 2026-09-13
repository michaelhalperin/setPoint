import SwiftUI
import UIKit

/// The manager opening a beat of the intake — first person, editorial serif,
/// with the same accent rule the check-in voice uses, so it reads as the same
/// person talking. An optional `context` line above acknowledges the last answer.
struct ManagerLine: View {
    /// A short note on what you just told it, e.g. "Gaining to 84 kg." Shown
    /// above the line.
    var context: String?
    /// What the manager says to open this beat.
    let line: String
    /// A quiet aside under the line (the old "subtitle" — practical detail).
    var aside: String?

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Palette.accent)
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: Space.xs) {
                if let context {
                    Text(context)
                        .sectionLabelStyle()
                        .foregroundStyle(Palette.accent)
                        .appearIn(0)
                }
                Text(line)
                    .font(Typography.voice(24))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .appearIn(context == nil ? 0 : 1)
                if let aside {
                    Text(aside)
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .appearIn(context == nil ? 1 : 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Space.sm)
    }
}

/// A large tappable option card (goal, activity level). Lifts and tints when
/// chosen; a checkmark draws in.
struct ChoiceCard: View {
    let title: String
    var blurb: String?
    let selected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(alignment: blurb == nil ? .center : .top, spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Typography.data(18, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    if let blurb {
                        Text(blurb)
                            .font(Typography.data(13))
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .strokeBorder(selected ? Palette.accent : Palette.inkFaint.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if selected {
                        Circle().fill(Palette.accent).frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .transaction { if reduceMotion { $0.animation = nil } }
            }
            .padding(Space.md - 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(selected ? Palette.accentTint : Palette.surface)
                    .elevation(selected ? .floating : .resting)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(selected ? Palette.accent.opacity(0.4) : Palette.hairline, lineWidth: 1)
                    )
            }
            .scaleEffect(selected ? 1 : 0.985)
            .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: selected)
        }
        .buttonStyle(.plain)
    }
}

/// A scrollable ruler for a single numeric value (height, weight, target
/// weight) — drag to scrub, snaps to the nearest step, a light tick per unit
/// crossed. The tactile, single-focus alternative to a text field + keyboard:
/// one big number, one gesture, nothing else on screen to read.
struct RulerPicker: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let unit: String
    /// Numerals are drawn under ticks that land on a multiple of this.
    var majorStep: Double = 10

    @State private var dragStartValue: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pxPerStep: CGFloat = 16
    private let tickAreaHeight: CGFloat = 64

    var body: some View {
        VStack(spacing: Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(Int(value.rounded())))
                    .font(Typography.data(52, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value))
                Text(unit)
                    .font(Typography.data(18, weight: .medium))
                    .foregroundStyle(Palette.inkFaint)
            }
            .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Int(value.rounded())) \(unit)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: setValue(min(range.upperBound, value + step))
                case .decrement: setValue(max(range.lowerBound, value - step))
                @unknown default: break
                }
            }

            GeometryReader { geo in
                let width = geo.size.width
                // `.topLeading` so the tape isn't auto-centered by the ZStack
                // before `tape(width:)`'s own offset runs — a ZStack centers
                // its children by default, which would double up the shift.
                ZStack(alignment: .topLeading) {
                    tape(width: width)
                        .mask(edgeFade)
                }
                // `.frame` also centers an oversized child by default — this is
                // the second place that centering sneaks back in.
                .frame(width: width, height: tickAreaHeight, alignment: .topLeading)
                .clipped()
                .overlay {
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: 3, height: 40)
                }
                .contentShape(Rectangle())
                .gesture(drag)
            }
            .frame(height: tickAreaHeight)
        }
    }

    private func tape(width: CGFloat) -> some View {
        let totalSteps = Int(((range.upperBound - range.lowerBound) / step).rounded())
        let offset = width / 2 - CGFloat((value - range.lowerBound) / step) * pxPerStep - pxPerStep / 2
        return HStack(spacing: 0) {
            ForEach(0 ... totalSteps, id: \.self) { i in
                let v = range.lowerBound + Double(i) * step
                let isMajor = v.truncatingRemainder(dividingBy: majorStep) == 0
                VStack(spacing: 4) {
                    Capsule()
                        .fill(isMajor ? Palette.inkSoft : Palette.inkFaint.opacity(0.45))
                        .frame(width: isMajor ? 2 : 1, height: isMajor ? 26 : 14)
                    Text(isMajor ? String(Int(v)) : "")
                        .font(Typography.data(10, weight: .medium))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize()
                        .frame(height: 12)
                }
                .frame(width: pxPerStep)
            }
        }
        .offset(x: offset)
    }

    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.16),
                .init(color: .black, location: 0.84),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { g in
                let base = dragStartValue ?? value
                if dragStartValue == nil { dragStartValue = value }
                let deltaSteps = (g.translation.width / pxPerStep).rounded(.towardZero)
                let proposed = base - Double(deltaSteps) * step
                setValue(min(range.upperBound, max(range.lowerBound, proposed)))
            }
            .onEnded { _ in dragStartValue = nil }
    }

    private func setValue(_ raw: Double) {
        let snapped = (raw / step).rounded() * step
        guard snapped != value else { return }
        value = snapped
        if !reduceMotion { UISelectionFeedbackGenerator().selectionChanged() }
    }
}

/// A time-of-day picker stored as minutes since local midnight.
struct MinutesField: View {
    let label: String
    @Binding var minutes: Int

    private var binding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = minutes / 60
                comps.minute = minutes % 60
                return Calendar.current.date(from: comps) ?? .now
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    var body: some View {
        HStack {
            Text(label)
                .font(Typography.data(15))
                .foregroundStyle(Palette.inkSoft)
            Spacer()
            DatePicker("", selection: binding, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

/// The onboarding journey indicator — one segment per step, filling as you go.
/// The current segment sits at a low opacity ("in progress"); completed ones are
/// solid. Segments animate their fill when `step` advances.
struct ProgressThread: View {
    /// 0-based index of the current step.
    let step: Int
    /// Number of steps shown (the outcome screen isn't one).
    let total: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< max(total, 1), id: \.self) { i in
                Capsule()
                    .fill(fill(for: i))
                    .frame(height: 4)
            }
        }
        .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion), value: step)
    }

    private func fill(for i: Int) -> Color {
        if i < step { return Palette.accent }
        if i == step { return Palette.accent.opacity(0.35) }
        return Palette.surfaceSunk
    }
}

