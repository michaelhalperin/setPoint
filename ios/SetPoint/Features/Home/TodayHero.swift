import SwiftUI

// The top of Today. Normally the day dial — each meal a knob, a bell where a
// check-in would come, the one thing that matters now in the centre. When a
// check-in fires, the top of the screen turns terracotta: the manager is talking.

// MARK: - Dial hero

struct TodayHero: View {
    let home: HomeResponse
    let moment: TodayMoment
    let date: Date

    var body: some View {
        let times = home.resolvedMealTimes
        let quiet = home.resolvedQuietHours
        VStack(alignment: .leading, spacing: Space.md) {
            DayDial(
                breakfastMin: times.breakfastMin, lunchMin: times.lunchMin, dinnerMin: times.dinnerMin,
                quietStartMin: quiet.startMin, quietEndMin: quiet.endMin,
                showsHourLabels: false,
                today: DialToday(
                    states: TodayCopy.dialStates(home),
                    nowMin: home.day?.nowMin ?? minuteOfDay(date),
                    ringColor: ringColor,
                    showsBells: home.enforcementEnabled,
                    firedSlot: firedSlot
                )
            ) {
                center
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: 320)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(TodayCopy.headline(moment))
                    .font(Typography.display(34))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.opacity)
                if let detail = TodayCopy.detail(moment, home: home, now: date) {
                    Text(detail)
                        .font(Typography.data(16))
                        .foregroundStyle(Palette.inkSoft)
                }
                if !home.managerNote.isEmpty, home.activeCheckIn == nil {
                    Text(home.managerNote)
                        .font(Typography.voice(17))
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.top, 4)
                }
                if home.needsWeighIn == true {
                    Text("A weigh-in is due — it’s on the Week tab.")
                        .font(Typography.data(14, weight: .bold))
                        .foregroundStyle(Palette.accentDeep)
                        .padding(.top, 6)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var center: some View {
        switch moment {
        case let .watching(slot, dueMin, overdue):
            VStack(spacing: 1) {
                Text(overdue ? "Checking in" : "Next check-in").sectionLabelStyle()
                Text(formatMinutes(dueMin))
                    .font(Typography.data(42, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                Text("if \(slot.title.lowercased()) isn’t logged")
                    .font(Typography.data(12, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
            }
        case let .snoozed(until):
            VStack(spacing: 1) {
                Text("Snoozed").sectionLabelStyle()
                Text(until?.formatted(date: .omitted, time: .shortened) ?? "Later")
                    .font(Typography.data(42, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                Text("then I check again")
                    .font(Typography.data(12, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
            }
        case .covered:
            VStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Palette.accent, in: Circle())
                Text(home.ledger.consumedKcal.formatted())
                    .font(Typography.data(28, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                Text("kcal today")
                    .font(Typography.data(12, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
            }
        case .quiet:
            bigNumber(home.ledger.consumedKcal, caption: "kcal logged")
        case let .toGo(kcal):
            bigNumber(kcal, caption: "kcal left")
        case .checkIn, .conversation:
            EmptyView()
        }
    }

    private func bigNumber(_ value: Int, caption: String) -> some View {
        VStack(spacing: 1) {
            Text(value.formatted())
                .font(Typography.data(38, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
            Text(caption)
                .font(Typography.data(12, weight: .semibold))
                .foregroundStyle(Palette.inkSoft)
        }
    }

    private var ringColor: Color {
        switch moment {
        case .covered: return Palette.dayOnTrack
        case .quiet: return Palette.inkFaint
        default: return Palette.accent
        }
    }

    private var firedSlot: MealSlot? {
        if case .snoozed = moment { return home.activeCheckIn?.slot.flatMap(MealSlot.init(rawValue:)) }
        return nil
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

// MARK: - Check-in takeover

/// A check-in (or the tier-3 talk) taking over the top of Today, on terracotta.
struct CheckInTakeover: View {
    let home: HomeResponse
    let checkIn: HomeResponse.ActiveCheckIn
    let moment: TodayMoment
    let busy: Bool
    let error: String?
    let onOpen: () -> Void
    let onAteThis: () -> Void
    let onAlreadyAte: () -> Void
    let onSnooze: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: 8) {
                LoopingPhase(period: 1.8, still: 1) { t in
                    ZStack {
                        Circle()
                            .fill(Palette.background)
                            .scaleEffect(1 + 1.4 * Phase.ramp(t, 0, 0.7))
                            .opacity(0.8 * (1 - Phase.ramp(t, 0, 0.7)))
                        Circle().fill(Palette.background)
                    }
                }
                .frame(width: 8, height: 8)
                Text(checkIn.tier >= 3 ? "Let’s talk" : "Check-in")
                    .sectionLabelStyle(Palette.background.opacity(0.85))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(TodayCopy.headline(moment))
                    .font(Typography.display(44))
                    .foregroundStyle(Palette.background)
                if let detail = TodayCopy.detail(moment, home: home) {
                    Text(detail)
                        .font(Typography.data(16))
                        .foregroundStyle(Palette.background.opacity(0.82))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if let rx = checkIn.prescription {
                Button(action: onOpen) {
                    PrescriptionCard(prescription: rx)
                }
                .buttonStyle(PressableCard())
                .padding(.top, Space.xs)
            }

            actions
                .padding(.top, Space.xs)

            if let error {
                Text(error)
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.background)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
        .padding(.bottom, Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Taller than the block so the colour runs up under the status bar
            // and past any overscroll.
            UnevenRoundedRectangle(bottomLeadingRadius: 36, bottomTrailingRadius: 36, style: .continuous)
                .fill(Palette.accent)
                .padding(.top, -1000)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if checkIn.tier >= 3 {
            creamButton("Talk it through", action: onOpen)
        } else {
            HStack(spacing: 8) {
                if checkIn.prescription != nil {
                    creamButton("I ate this", busy: busy, busyTitle: "Logging", action: onAteThis)
                }
                Button(action: onAlreadyAte) {
                    Text("I already ate")
                        .font(Typography.data(16, weight: .bold))
                        .foregroundStyle(Palette.background)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Palette.background.opacity(0.5), lineWidth: 1.5)
                        )
                }
                .buttonStyle(PressableCard())
                Button(action: onSnooze) {
                    Image(systemName: "zzz")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.background)
                        .frame(width: 52, height: 52)
                        .background(Palette.background.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableCard())
                .accessibilityLabel("Snooze")
            }
            .disabled(busy)
        }
    }

    private func creamButton(
        _ title: String,
        busy: Bool = false,
        busyTitle: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            BusyLabel(
                title: busy ? (busyTitle ?? title) : title,
                busy: busy,
                tint: Palette.accentDeep
            )
            .font(Typography.data(16, weight: .bold))
            .foregroundStyle(Palette.accentDeep)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableCard())
        .disabled(busy)
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: busy)
    }
}

/// The suggested meal: one row per food, then the totals.
struct PrescriptionCard: View {
    let prescription: HomeResponse.ActiveCheckIn.Prescription
    var roomy = false

    var body: some View {
        VStack(alignment: .leading, spacing: roomy ? 14 : 12) {
            ForEach(prescription.items) { item in
                HStack(spacing: 12) {
                    Image(systemName: FoodSymbol.for(item.name))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: roomy ? 38 : 34, height: roomy ? 38 : 34)
                        .background(Palette.surfaceSunk, in: Circle())
                    Text(item.quantity > 1 ? "\(Int(item.quantity))× \(item.name)" : item.name)
                        .font(Typography.data(roomy ? 16 : 15, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text("\(item.kcal) kcal")
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkFaint)
                        .monospacedDigit()
                }
            }
            Divider().overlay(Palette.hairline)
            HStack {
                Text("\(prescription.totalKcal.formatted()) kcal")
                    .font(Typography.data(15, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("\(Int(prescription.totalProteinG.rounded())) g protein")
                    .font(Typography.data(15, weight: .bold))
                    .foregroundStyle(Palette.accent)
            }
            .monospacedDigit()
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Palette.surface)
                .elevation(.lifted)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.hairline))
        }
        .accessibilityElement(children: .combine)
    }
}

/// A rough symbol for a food name — enough to make a list scannable.
enum FoodSymbol {
    static func `for`(_ name: String) -> String {
        let n = name.lowercased()
        if ["milk", "shake", "juice", "smoothie", "latte", "kefir"].contains(where: n.contains) { return "cup.and.saucer.fill" }
        if ["banana", "apple", "berries", "orange", "fruit", "grapes", "dates"].contains(where: n.contains) { return "leaf.fill" }
        if ["oil", "butter", "avocado"].contains(where: n.contains) { return "drop.fill" }
        if ["rice", "oats", "pasta", "bread", "toast", "granola", "bagel", "potato", "tortilla", "cereal"].contains(where: n.contains) { return "takeoutbag.and.cup.and.straw.fill" }
        if ["nut", "almond", "peanut", "seed", "trail"].contains(where: n.contains) { return "circle.hexagongrid.fill" }
        return "fork.knife"
    }
}

// MARK: - Fuel strip

/// Calories and protein, shrunk to a strip under the hero.
struct FuelStrip: View {
    let home: HomeResponse
    let moment: TodayMoment

    var body: some View {
        let ledger = home.ledger
        HStack(spacing: 10) {
            cell(
                value: moment == .quiet || home.framing.state != "under" ? ledger.consumedKcal : max(0, ledger.remainingKcal),
                unit: moment == .quiet ? "kcal logged" : home.framing.state == "under" ? "kcal left" : "of \(ledger.targetKcal.formatted()) kcal",
                fraction: Double(ledger.consumedKcal) / Double(max(ledger.targetKcal, 1)),
                accentNumber: moment.takesOver
            )
            if let target = ledger.targetProteinG, target > 0 {
                cell(
                    value: Int(ledger.consumedProteinG.rounded()),
                    unit: "/ \(Int(target.rounded())) g protein",
                    fraction: ledger.consumedProteinG / target,
                    accentNumber: false
                )
            }
        }
    }

    private var fill: Color {
        switch moment {
        case .checkIn, .conversation: return Palette.accent
        case .covered: return Palette.dayOnTrack
        case .quiet: return Palette.inkFaint
        default: return Palette.ink
        }
    }

    private func cell(value: Int, unit: String, fraction: Double, accentNumber: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value.formatted())
                    .font(Typography.data(22, weight: .bold))
                    .foregroundStyle(accentNumber ? Palette.accent : Palette.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(value)))
                Text(unit)
                    .font(Typography.data(12, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            GeometryReader { geo in
                Capsule().fill(Palette.surfaceSunk)
                    .overlay(alignment: .leading) {
                        Capsule().fill(fill)
                            .frame(width: geo.size.width * min(1, max(0, fraction)))
                    }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.surface)
                .elevation(.resting)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.hairline))
        }
        .accessibilityElement(children: .combine)
    }
}
