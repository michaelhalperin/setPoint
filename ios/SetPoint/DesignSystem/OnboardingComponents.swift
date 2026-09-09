import SwiftUI

struct StepHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Typography.voice(26))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(Typography.data(14))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A large tappable option card (goal, activity level).
struct ChoiceCard: View {
    let title: String
    var blurb: String?
    let selected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                selected ? Palette.accentSoft.opacity(0.6) : Palette.surface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Palette.accent : Palette.ink.opacity(0.06), lineWidth: selected ? 1.5 : 1)
            )
            .scaleEffect(selected ? 1 : 0.995)
            .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: selected)
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
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

/// Progress bar for the onboarding flow.
struct OnboardingProgressBar: View {
    let progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surfaceSunk)
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: max(6, geo.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: 4)
        .animation(Motion.adaptive(Motion.gentle, reduceMotion: reduceMotion), value: progress)
    }
}
