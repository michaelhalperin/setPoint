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
                        .font(Typography.data(17, weight: .medium))
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
                        .strokeBorder(selected ? Palette.ink : Color.white.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if selected {
                        Circle().fill(Palette.ink).frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.onBone)
                    }
                }
                .transaction { if reduceMotion { $0.animation = nil } }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(
                radius: Radius.lg,
                fill: selected ? Color.white.opacity(0.09) : Palette.glass,
                stroke: selected ? Color.white.opacity(0.32) : Palette.hairline
            )
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
    /// Decimal places in the big number (a 0.1 kg weigh-in shows one).
    var fractionDigits = 0
    /// False when the screen shows the number itself.
    var showsValue = true

    @State private var dragStartValue: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pxPerStep: CGFloat = 16
    private let tickAreaHeight: CGFloat = 64

    var body: some View {
        VStack(spacing: Space.md) {
            if showsValue {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value.formatted(.number.precision(.fractionLength(fractionDigits))))
                        .font(Typography.data(56, weight: .light))
                        .tracking(-2)
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: value))
                    Text(unit)
                        .font(Typography.mono(15))
                        .foregroundStyle(Palette.inkFaint)
                }
                .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: value)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(value.formatted(.number.precision(.fractionLength(fractionDigits)))) \(unit)")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: setValue(min(range.upperBound, value + step))
                    case .decrement: setValue(max(range.lowerBound, value - step))
                    @unknown default: break
                    }
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
                        .fill(Palette.amber)
                        .frame(width: 3, height: 40)
                        .shadow(color: Palette.amber.opacity(0.6), radius: 6)
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
                let isMajor = abs((v / majorStep).rounded() * majorStep - v) < step / 2
                VStack(spacing: 4) {
                    Capsule()
                        .fill(isMajor ? Palette.inkSoft : Palette.inkFaint.opacity(0.45))
                        .frame(width: isMajor ? 2 : 1, height: isMajor ? 26 : 14)
                    Text(isMajor ? String(Int(v.rounded())) : "")
                        .font(Typography.mono(10))
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
                .displayTracking(38)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .appearIn(0, rise: 16)
            if let detail {
                Text(detail)
                    .font(Typography.data(15, weight: .regular))
                    .lineSpacing(3)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .appearIn(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
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
                            .font(Typography.data(14, weight: on ? .medium : .regular))
                            .foregroundStyle(on ? Palette.onBone : Palette.inkSoft)
                        if let detail {
                            Text(detail(option))
                                .font(Typography.data(11, weight: .regular))
                                .foregroundStyle(on ? Palette.onBone.opacity(0.6) : Palette.inkFaint)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, detail == nil ? 11 : 10)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: detail == nil ? 999 : 17, style: .continuous)
                                .fill(Palette.ink)
                                .matchedGeometryEffect(id: "segment", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .glass(radius: detail == nil ? 999 : 22, fill: Color.white.opacity(0.05), stroke: Color.white.opacity(0.08))
    }
}

/// Whole-week stepper for a weight-goal timeframe.
struct WeeksStepper: View {
    @Binding var weeks: Int
    var large: Bool = false

    var body: some View {
        HStack {
            stepperButton("minus", delta: -1)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(weeks)")
                    .font(Typography.data(large ? 64 : 48, weight: .light))
                    .tracking(large ? -2 : -1)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: Double(weeks)))
                Text("weeks")
                    .font(Typography.mono(large ? 16 : 14))
                    .foregroundStyle(Palette.inkFaint)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(weeks) weeks")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: nudge(1)
                case .decrement: nudge(-1)
                @unknown default: break
                }
            }
            Spacer()
            stepperButton("plus", delta: 1)
        }
    }

    private func stepperButton(_ symbol: String, delta: Int) -> some View {
        Button { nudge(delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: large ? 56 : 48, height: large ? 56 : 48)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10)))
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel(delta > 0 ? "Increase duration" : "Decrease duration")
    }

    private func nudge(_ delta: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(Motion.settle) {
            weeks = WeightPace.clampWeeks(weeks + delta)
        }
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
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(isOn ? Palette.onBone : Palette.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(isOn ? Palette.ink : Palette.glass, in: Capsule())
                    .overlay(Capsule().strokeBorder(isOn ? Color.clear : Palette.hairline))
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
