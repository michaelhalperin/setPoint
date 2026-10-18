import SwiftUI

// The top of Today. The fuel orb — how much of the day's food is in — with the
// one thing that matters now in a glass card under it, and the day's plates as a
// strip of dots. When a check-in fires, the top of Today becomes the check-in.

// MARK: - Orb hero

struct TodayHero: View {
    let home: HomeResponse
    let moment: TodayMoment
    let date: Date
    /// Reload after the morning appetite answer.
    var onAppetiteChanged: () -> Void = {}

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: Space.md) {
            header
            FuelOrbDial(progress: progress, dimmed: moment == .quiet) {
                VStack(spacing: 2) {
                    Text(home.ledger.consumedKcal.formatted())
                        .font(Typography.hero)
                        .tracking(-1.8)
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: Double(home.ledger.consumedKcal)))
                    Text("of \(home.ledger.targetKcal.formatted()) kcal")
                        .font(Typography.mono(12))
                        .foregroundStyle(Color(hex: 0xFDE6CF))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(home.ledger.consumedKcal) of \(home.ledger.targetKcal) kilocalories")
            }
            .padding(.top, Space.xs)

            StatusPill(dot: statusDot, text: statusText) {
                Text("·").foregroundStyle(Palette.inkFaint)
                Text(mealsLine)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }

            Group {
                if AppetiteTodayVisibility.resolve(home: home) == .ask {
                    AppetiteTodayLine(home: home, onChanged: onAppetiteChanged)
                } else {
                    momentCard
                }
            }
            .padding(.top, Space.xs)
            .appearIn(1, rise: 16)

            PlateStrip(home: home)
                .padding(.top, Space.xxs)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.wide)))
                    .font(Typography.data(20, weight: .regular))
                    .tracking(-0.4)
                    .foregroundStyle(Palette.ink)
                Text(subline)
                    .font(Typography.mono(11))
                    .tracking(1.3)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                if let block = home.busyBlocks?.first {
                    chip(dot: Palette.inkSoft, "Busy \(formatBusyRange(block.startMin, block.endMin))")
                }
                if let training = home.training, !training.workouts.isEmpty {
                    NavigationLink {
                        if env.subscription.entitled {
                            TrainingScreen()
                        } else {
                            PaywallView()
                        }
                    } label: {
                        chip(dot: Palette.haze, training.bumpKcal > 0 ? "Training +\(training.bumpKcal)" : "Training")
                    }
                    .buttonStyle(PressableCard())
                }
            }
        }
    }

    private var subline: String {
        let day = date.formatted(.dateTime.day().month(.abbreviated))
        if moment == .quiet { return "\(day) · quiet mode" }
        if let appetite = home.appetite, appetite.didAnswerToday {
            switch appetite.level {
            case "LOW": return "\(day) · low appetite"
            case "HUNGRY": return "\(day) · hungry"
            default: break
            }
        }
        return day
    }

    private func chip(dot: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(text)
                .font(Typography.data(12, weight: .regular))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .glassCapsule(fill: Color.white.opacity(0.05), stroke: Color.white.opacity(0.10))
    }

    // MARK: Status

    private var progress: Double {
        Double(home.ledger.consumedKcal) / Double(max(home.ledger.targetKcal, 1))
    }

    private var behind: Bool { home.day?.pace?.status == "behind" }

    private var statusText: String {
        switch moment {
        case .quiet: return "Quiet mode"
        case .covered: return "Day closed"
        case .checkIn, .conversation: return "Checking in"
        case .snoozed: return "Snoozed"
        default: return behind ? "A bit behind" : "On pace"
        }
    }

    private var statusDot: Color {
        switch moment {
        case .quiet: return Palette.inkSoft
        case .covered: return Palette.amber
        case .checkIn, .conversation, .snoozed: return Palette.ember
        default: return behind ? Palette.ember : Palette.positive
        }
    }

    private var mealsLine: String {
        let slots = home.day?.slots ?? []
        guard !slots.isEmpty else {
            return home.ledger.mealsToday == 1 ? "1 meal" : "\(home.ledger.mealsToday) meals"
        }
        let logged = slots.filter { $0.slotState == .logged }.count
        return "\(logged) of \(slots.count) meals"
    }

    // MARK: Moment card

    @ViewBuilder
    private var momentCard: some View {
        GlassCard(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(momentLabel).sectionLabelStyle()
                Spacer(minLength: 8)
                if let kcal = nextKcal {
                    Text("~\(kcal.formatted()) kcal")
                        .font(Typography.mono(12))
                        .foregroundStyle(Palette.amber)
                }
            }
            Headline(TodayCopy.headline(moment), tail: tail, size: 26)
                .contentTransition(.opacity)
            if !home.managerNote.isEmpty, home.activeCheckIn == nil {
                Text(home.managerNote)
                    .font(Typography.voice(15))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if home.needsWeighIn == true {
                HStack(spacing: 6) {
                    Image(systemName: "scalemass")
                        .font(.system(size: 12, weight: .medium))
                    Text("A weigh-in is due — it’s on Progress.")
                        .font(Typography.data(13, weight: .regular))
                }
                .foregroundStyle(Palette.amber)
                .padding(.top, 2)
            }
        }
    }

    private var tail: String? {
        if let detail = TodayCopy.detail(moment, home: home, now: date) { return detail }
        if case let .watching(_, dueMin, _, _) = moment {
            return "Check-in at \(formatMinutes(dueMin)) if it’s not logged."
        }
        return nil
    }

    private var momentLabel: String {
        switch moment {
        case let .watching(slot, dueMin, overdue, light):
            let title = TodayCopy.slotTitle(slot)
            if overdue { return "Checking in · \(title)" }
            if light { return "Top-up · back \(formatMinutes(dueMin))" }
            let at = home.nextCheckIn?.mealMin ?? dueMin
            let moved = !(home.movedSlots ?? []).isEmpty
            return "Next · \(title) · \(formatMinutes(at))" + (moved ? " · moved" : "")
        case let .snoozed(until):
            return "Snoozed · back \(until?.formatted(date: .omitted, time: .shortened) ?? "later")"
        case .covered: return "Day closed"
        case .quiet: return "Today"
        case .toGo: return "Still to go"
        case .checkIn, .conversation: return "Check-in"
        }
    }

    private var nextKcal: Int? {
        guard case .watching = moment else { return nil }
        if let plate = home.appetite?.nextPlate { return plate.kcal }
        return home.day?.pace?.next?.suggestedKcal
    }
}

// MARK: - Plate strip

/// The day's plates as dots on a line: amber when eaten, a pulsing ember ring
/// for the one due now, a dim ring for a missed one, faint for later.
struct PlateStrip: View {
    let home: HomeResponse

    private struct Plate: Identifiable {
        let id: String
        let atMin: Int
        let state: SlotState
        let snack: Bool
    }

    private var plates: [Plate] {
        let now = home.day?.nowMin ?? 0
        var out = (home.day?.slots ?? []).map { slot -> Plate in
            var state = slot.slotState
            if state == .missed, !home.enforcementEnabled { state = .upcoming }
            return Plate(id: slot.slot, atMin: slot.atMin, state: state, snack: false)
        }
        for extra in home.appetite?.extraSlots ?? [] {
            out.append(Plate(id: extra.slot, atMin: extra.atMin, state: extra.atMin < now ? .logged : .upcoming, snack: true))
        }
        return out.sorted { $0.atMin < $1.atMin }
    }

    var body: some View {
        let plates = plates
        if !plates.isEmpty {
            HStack(alignment: .top, spacing: 0) {
                ForEach(plates) { plate in
                    VStack(spacing: 6) {
                        dot(plate)
                            .frame(width: 18, height: 18)
                        Text(formatMinutes(plate.atMin))
                            .font(Typography.mono(10))
                            .foregroundStyle(plate.state == .now ? Palette.amber : Palette.inkFaint)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary(plates))
        }
    }

    @ViewBuilder
    private func dot(_ plate: Plate) -> some View {
        let size: CGFloat = plate.snack ? 8 : 12
        switch plate.state {
        case .logged:
            Circle()
                .fill(plate.snack ? Palette.amber.opacity(0.5) : Palette.amber)
                .frame(width: size, height: size)
                .shadow(color: Palette.amber.opacity(0.6), radius: 6)
        case .now:
            ZStack {
                PingRing(color: Palette.ember)
                Circle().strokeBorder(Palette.ember, lineWidth: 2).frame(width: size, height: size)
            }
        case .missed:
            Circle().strokeBorder(Palette.ember.opacity(0.55), lineWidth: 1.5).frame(width: size, height: size)
        case .upcoming:
            Circle().fill(Color.white.opacity(0.2)).frame(width: plate.snack ? 6 : 8, height: plate.snack ? 6 : 8)
        }
    }

    private func accessibilitySummary(_ plates: [Plate]) -> String {
        plates.map { plate in
            let name = TodayCopy.slotTitle(plate.id)
            let state: String
            switch plate.state {
            case .logged: state = "eaten"
            case .now: state = "due now"
            case .missed: state = "missed"
            case .upcoming: state = "later"
            }
            return "\(name) \(formatMinutes(plate.atMin)), \(state)"
        }
        .joined(separator: "; ")
    }
}

/// An expanding, fading ring — a live signal.
struct PingRing: View {
    var color: Color

    var body: some View {
        LoopingPhase(period: 1.6, still: 0) { t in
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .scaleEffect(1 + 1.4 * t)
                .opacity(0.7 * (1 - t))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Check-in takeover

/// A check-in (or the tier-3 talk) taking over the top of Today: an ember glow,
/// the manager's line, the plate, and one bone button.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                ZStack {
                    PingRing(color: Palette.ember)
                    Circle().fill(Palette.ember).frame(width: 7, height: 7)
                }
                .frame(width: 10, height: 10)
                Text(label).sectionLabelStyle(Palette.amber)
            }
            .appearIn(0)

            Headline(TodayCopy.headline(moment), tail: TodayCopy.detail(moment, home: home), size: 42)
                .appearIn(1, rise: 16)

            if let rx = checkIn.prescription {
                Button(action: onOpen) {
                    PrescriptionCard(prescription: rx)
                }
                .buttonStyle(PressableCard())
                .accessibilityHint("Opens the full check-in")
                .appearIn(2, rise: 16)
            }

            actions
                .appearIn(3, rise: 16)

            if let error {
                Text(error)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.danger)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            AmbientGlow(tone: .ember, strength: 1.2)
                .offset(y: -160)
        }
    }

    private var label: String {
        let time = Date().formatted(date: .omitted, time: .shortened)
        switch CheckInFlavor(kind: checkIn.kind ?? "MEAL") {
        case .close: return "Closing the day · \(time)"
        case .light: return "Top-up · \(time)"
        case .meal: return checkIn.tier >= 3 ? "Let’s talk" : "Check-in · \(time)"
        }
    }

    @ViewBuilder
    private var actions: some View {
        if checkIn.tier >= 3 {
            ActionButton(title: "Talk it through", action: onOpen)
        } else {
            VStack(spacing: 10) {
                if let rx = checkIn.prescription {
                    ActionButton(
                        title: "Eating it · \(rx.totalKcal.formatted()) kcal",
                        busy: busy,
                        busyTitle: "Logging",
                        symbol: "checkmark",
                        action: onAteThis
                    )
                }
                HStack(spacing: 10) {
                    ActionButton(title: "I already ate", kind: .secondary, action: onAlreadyAte)
                    ActionButton(title: "Snooze", kind: .secondary, action: onSnooze)
                }
                .disabled(busy)
            }
        }
    }
}

/// The suggested plate: one row per food, then the totals.
struct PrescriptionCard: View {
    let prescription: HomeResponse.ActiveCheckIn.Prescription
    var roomy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(prescription.items) { item in
                HStack(spacing: 12) {
                    Text(item.quantity > 1 ? "\(Int(item.quantity))× \(item.name)" : item.name)
                        .font(Typography.data(roomy ? 17 : 16, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text("\(item.kcal)")
                        .font(Typography.mono(13))
                        .foregroundStyle(Palette.inkSoft)
                }
                .padding(.vertical, roomy ? 12 : 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                }
            }
            HStack {
                Text("\(prescription.totalKcal.formatted()) kcal")
                    .font(Typography.mono(14))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("\(Int(prescription.totalProteinG.rounded())) g protein")
                    .font(Typography.mono(13))
                    .foregroundStyle(Palette.amber)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .padding(.bottom, 10)
        .glass(radius: Radius.xl)
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

/// Calories left and protein, in one glass row under the hero.
struct FuelStrip: View {
    let home: HomeResponse
    let moment: TodayMoment

    var body: some View {
        let ledger = home.ledger
        HStack(spacing: 0) {
            cell(
                value: moment == .quiet || home.framing.state != "under" ? ledger.consumedKcal : max(0, ledger.remainingKcal),
                unit: moment == .quiet ? "kcal logged" : home.framing.state == "under" ? "kcal left" : "kcal eaten",
                fraction: Double(ledger.consumedKcal) / Double(max(ledger.targetKcal, 1)),
                tint: Palette.amber
            )
            if let target = ledger.targetProteinG, target > 0 {
                Rectangle().fill(Palette.hairline).frame(width: 1, height: 40)
                cell(
                    value: Int(ledger.consumedProteinG.rounded()),
                    unit: "of \(Int(target.rounded())) g protein",
                    fraction: ledger.consumedProteinG / target,
                    tint: Palette.ink
                )
            }
        }
        .padding(.vertical, 14)
        .glass(radius: Radius.lg)
    }

    private func cell(value: Int, unit: String, fraction: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value.formatted())
                    .font(Typography.data(22, weight: .light))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: Double(value)))
                Text(unit)
                    .font(Typography.mono(11))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            GeometryReader { geo in
                Capsule().fill(Color.white.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint)
                            .frame(width: geo.size.width * min(1, max(0, fraction)))
                    }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
