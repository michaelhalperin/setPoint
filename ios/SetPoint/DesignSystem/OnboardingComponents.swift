import SwiftUI
import UIKit

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

/// A setup screen's question — big serif, nothing beside it, an optional quiet line under.
struct StepHeadline: View {
    let text: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(text)
                .font(Typography.display(38))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .appearIn(0)
            if let detail {
                Text(detail)
                    .font(Typography.data(16))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .appearIn(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The round Next button. Onboarding progress lives in the ring around it
/// instead of a step bar across the top.
struct RingNextButton: View {
    let progress: Double
    var enabled = true
    var busy = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Palette.surfaceSunk, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion), value: progress)
                Circle()
                    .fill(Palette.accent)
                    .padding(8)
                    .elevation(enabled ? .resting : .flat)
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 78, height: 78)
            .opacity(enabled ? 1 : 0.45)
            .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: enabled)
        }
        .buttonStyle(PressableCard())
        .disabled(!enabled || busy)
        .accessibilityLabel("Next")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent done")
    }
}

/// The quiet circular Back button that pairs with `RingNextButton`.
struct CircleBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 52, height: 52)
                .background(Palette.surfaceSunk, in: Circle())
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel("Back")
    }
}

/// A pill-shaped segmented control on a sunk track.
struct SegmentedPills<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var detail: ((Option) -> String)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    withAnimation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion)) { selection = option }
                } label: {
                    VStack(spacing: 2) {
                        Text(title(option))
                            .font(Typography.data(16, weight: .bold))
                            .foregroundStyle(on ? Palette.ink : Palette.inkSoft)
                        if let detail {
                            Text(detail(option))
                                .font(Typography.data(12, weight: .medium))
                                .foregroundStyle(on ? Palette.inkSoft : Palette.inkFaint)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, detail == nil ? 13 : 11)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: detail == nil ? 999 : 17, style: .continuous)
                                .fill(Palette.surface)
                                .elevation(.resting)
                                .matchedGeometryEffect(id: "segment", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: detail == nil ? 999 : 22, style: .continuous))
    }
}

/// Wrapping selectable chips.
struct FlowChips: View {
    let options: [String]
    @Binding var selected: [String]

    var body: some View {
        FlexWrap(spacing: 10, lineSpacing: 10) {
            ForEach(options, id: \.self) { option in
                let isOn = selected.contains(option)
                Button {
                    withAnimation(Motion.settle) {
                        if isOn { selected.removeAll { $0 == option } } else { selected.append(option) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isOn {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(option)
                    }
                    .font(Typography.data(16, weight: .semibold))
                    .foregroundStyle(isOn ? Palette.background : Palette.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(isOn ? Palette.ink : Palette.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(isOn ? Color.clear : Palette.hairline))
                    .elevation(isOn ? .flat : .resting)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// Minimal flow layout (iOS 16+ Layout).
struct FlexWrap: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
