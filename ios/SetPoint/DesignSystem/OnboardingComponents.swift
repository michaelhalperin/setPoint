import SwiftUI

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

/// A yes/no question — two pills. Unanswered until one is tapped.
struct YesNoRow: View {
    let question: String
    @Binding var answer: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question)
                .font(Typography.data(15))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                pill("No", isOn: answer == false) { answer = false }
                pill("Yes", isOn: answer == true) { answer = true }
            }
        }
        .padding(.vertical, 6)
    }

    private func pill(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Typography.data(15, weight: .semibold))
                .foregroundStyle(isOn ? .white : Palette.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    isOn ? Palette.ink : Palette.surfaceSunk,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

/// A numeric measure entry (height, weight).
struct MeasureField: View {
    let label: String
    let unit: String
    let range: ClosedRange<Double>
    @Binding var value: Double?

    @State private var text = ""

    var body: some View {
        HStack {
            Text(label)
                .font(Typography.data(15))
                .foregroundStyle(Palette.inkSoft)
            Spacer()
            TextField("—", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(Typography.data(17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 72)
                .onChange(of: text) { _, new in
                    if let parsed = Double(new.replacingOccurrences(of: ",", with: ".")), range.contains(parsed) {
                        value = parsed
                    } else if new.isEmpty {
                        value = nil
                    }
                }
                .onAppear { if let value { text = formatted(value) } }
            Text(unit)
                .font(Typography.data(14))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surface)
                .elevation(.resting)
                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.hairline))
        }
    }

    private func formatted(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(v)
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

