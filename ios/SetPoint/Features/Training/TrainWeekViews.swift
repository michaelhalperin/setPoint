import SwiftUI

// Train, week first: a strip of seven days to pick from, then a card for the day
// picked — today's food around the session, how a past one went, what a planned
// one will add, or a rest day — then what's coming up, then settings in one row.

enum TrainKind {
    static let all = ["STRENGTH", "CARDIO", "MIXED"]

    static func title(_ kind: String) -> String {
        switch kind {
        case "CARDIO": return L10n( "Cardio")
        case "MIXED": return L10n( "Mixed")
        default: return L10n( "Strength")
        }
    }

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "CARDIO": return "figure.run"
        case "MIXED": return "figure.mixed.cardio"
        default: return "dumbbell.fill"
        }
    }
}

/// "17:00" from minutes after midnight.
func trainClock(_ minutes: Int) -> String {
    let m = ((minutes % 1440) + 1440) % 1440
    return String(format: "%02d:%02d", m / 60, m % 60)
}

/// "17:00" from a date, on the phone's clock.
func trainClock(_ date: Date) -> String {
    trainClock(TrainMath.minute(date))
}

/// One day in the week strip, with everything its card needs.
struct TrainDay: Identifiable {
    var id: String { key }
    let key: String
    let date: Date
    let sessions: [TrainSession]
    /// What training adds that day (0 when "Add calories" is off).
    let bumpKcal: Int
    let refuel: TrainMath.Refuel?
    let isToday: Bool
    let isPast: Bool
    /// A session can still be added on this day.
    let canAdd: Bool
    /// All food logged that day, when known.
    var eatenKcal: Int? = nil
    /// The meal that counted as the refuel.
    var refuelMeal: TrainMath.Meal? = nil
}

// MARK: - Small shared pieces

private struct KindTile: View {
    let kind: String
    var tint: Color = Palette.hazeSoft
    var fill: Color = Palette.haze.opacity(0.18)

    var body: some View {
        Image(systemName: TrainKind.symbol(kind))
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
            .accessibilityHidden(true)
    }
}

private struct EditPill: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Edit")
                .font(Typography.data(13, weight: .medium))
                .foregroundStyle(Palette.hazeSoft)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Palette.haze.opacity(0.14), in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.haze.opacity(0.40)))
        }
        .buttonStyle(PressableCard())
        .frame(minHeight: 44)
    }
}

/// The "+" pill: the header's action and the rest day's.
struct TrainPlanPill: View {
    var title = L10n("Plan")
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0xE0E7FF))
                .frame(width: 40, height: 40)
                .background(Palette.haze.opacity(0.16), in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.haze.opacity(0.45)))
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel(title)
        .frame(minHeight: 44)
    }
}

private func sessionTitle(_ s: TrainSession) -> String {
    "\(TrainKind.title(s.kind)) · \(trainClock(s.start))–\(trainClock(s.end))"
}

private func repeatText(_ s: TrainSession) -> String {
    s.repeats ? L10n( "Every \(s.start.formatted(.dateTime.weekday(.wide)))") : L10n( "Once")
}

// MARK: - The week strip

struct TrainWeekStrip: View {
    let title: String
    let range: String
    let summary: String
    let days: [TrainDay]
    let selectedKey: String
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    /// Set when the strip shows a week other than this one.
    var onThisWeek: (() -> Void)?
    let onPick: (TrainDay) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(Palette.ink)
                    Text(range.uppercased())
                        .font(Typography.mono(11))
                        .tracking(0.6)
                        .foregroundStyle(Palette.inkFaint)
                }
                Spacer(minLength: 4)
                if let onThisWeek {
                    Button("This week", action: onThisWeek)
                        .font(Typography.data(13, weight: .medium))
                        .foregroundStyle(Palette.hazeSoft)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 4)
                }
                arrow("chevron.backward", label: "Earlier week", enabled: canGoBack, action: onBack)
                arrow("chevron.forward", label: "Later week", enabled: canGoForward, action: onForward)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 4) {
                ForEach(days) { day in
                    dayButton(day)
                }
            }

            Text(summary)
                .font(Typography.data(12, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .glass(radius: 24, fill: Color.white.opacity(0.035), stroke: Color.white.opacity(0.08))
    }

    private func arrow(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? Palette.ink : Palette.inkFaint.opacity(0.5))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(enabled ? 0.07 : 0.02), in: Circle())
        }
        .buttonStyle(PressableCard())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func dayButton(_ day: TrainDay) -> some View {
        let selected = day.key == selectedKey
        return Button { onPick(day) } label: {
            VStack(spacing: 5) {
                Text(day.date.formatted(.dateTime.weekday(.narrow).locale(AppLanguage.current.locale)))
                    .font(Typography.mono(10))
                    .opacity(0.8)
                Text(day.date.formatted(.dateTime.day()))
                    .font(Typography.data(17, weight: .medium))
                mark(day, selected: selected)
            }
            .foregroundStyle(selected ? Palette.onBone : Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? Palette.ink : day.isToday ? Palette.haze.opacity(0.10) : .clear)
            }
            .overlay {
                if day.isToday && !selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.hazeSoft.opacity(0.6))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility(day))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func mark(_ day: TrainDay, selected: Bool) -> some View {
        if day.sessions.isEmpty {
            Circle().fill(.clear).frame(width: 6, height: 6)
        } else if day.refuel == .planned && !day.isToday && !selected {
            Circle().strokeBorder(Palette.hazeSoft, lineWidth: 1.5).frame(width: 6, height: 6)
        } else {
            Circle().fill(markColor(day.refuel, selected: selected)).frame(width: 6, height: 6)
        }
    }

    private func markColor(_ refuel: TrainMath.Refuel?, selected: Bool) -> Color {
        switch refuel {
        case .done: return selected ? Color(hex: 0x16A34A) : Palette.positive
        case .missed, .due: return selected ? Color(hex: 0xC2410C) : Palette.amber
        case .planned: return selected ? Color(hex: 0x4F46E5) : Palette.hazeSoft
        case nil: return selected ? Palette.onBone.opacity(0.5) : Palette.inkFaint
        }
    }

    private func accessibility(_ day: TrainDay) -> String {
        let name = day.date.formatted(.dateTime.weekday(.wide).day().locale(AppLanguage.current.locale))
        guard let first = day.sessions.first else { return L10n( "\(name), rest day") }
        let status: String
        switch day.refuel {
        case .done: status = L10n("refueled")
        case .missed: status = L10n("missed the refuel")
        case .due: status = L10n("refuel now")
        case .planned: status = L10n("planned")
        case nil: status = ""
        }
        return L10n( "\(name), \(TrainKind.title(first.kind)) \(status)")
    }
}

// MARK: - Today

struct TrainTodayCard: View {
    let session: TrainSession
    let baseKcal: Int
    let bumpKcal: Int
    let targetKcal: Int
    let addCalories: Bool
    let dinnerMin: Int
    let steps: TrainMath.Steps?
    /// A snack they already eat, or a light staple that fits.
    var snackBefore: TrainingWeekResponse.SnackBefore? = nil
    let now: Date
    var onLog: () -> Void
    var onLogSnack: ((TrainingWeekResponse.SnackBefore) -> Void)?
    var loggingSnack = false
    var snackLogged = false
    var onOpenSnack: ((TrainingWeekResponse.SnackBefore) -> Void)?
    /// Set while the session can still be changed.
    var onEdit: (() -> Void)?

    private var start: Int { TrainMath.minute(session.start) }
    private var end: Int { start + session.durationMin }
    private var nowMin: Int { TrainMath.minute(now) }
    private var window: Int { TrainMath.refuelWindowMin }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                KindTile(kind: session.kind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sessionTitle(session))
                        .font(Typography.data(17, weight: .regular))
                        .foregroundStyle(Palette.ink)
                    Text(status)
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 8)
                if let onEdit { EditPill(action: onEdit).accessibilityLabel(L10n("Edit today’s session")) }
            }

            VStack(alignment: .leading, spacing: 10) {
                if bumpKcal > 0 {
                    Text(L10n("Eat \(bumpKcal) more today."))
                        .font(Typography.display(28))
                        .tracking(-0.8)
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    targetBar
                } else {
                    Headline("Eat around it.", tail: addCalories ? "Here’s when." : L10n("“Add calories” is off — today stays at \(baseKcal.formatted())."), size: 26, persistTail: !addCalories)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                let rows = stepRows
                ForEach(Array(rows.enumerated()), id: \.offset) { index, step in
                    stepRow(step, last: index == rows.count - 1)
                }
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Palette.haze.opacity(0.17), Color.white.opacity(0.03)], startPoint: .topLeading, endPoint: UnitPoint(x: 0.6, y: 0.9)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Palette.hazeSoft.opacity(0.40))
        }
    }

    private var status: String {
        let origin = session.isPlanned ? L10n( "added by you") : L10n( "from Apple Health")
        if nowMin >= end { return L10n( "Done · \(origin)") }
        if nowMin >= start { return L10n( "Under way · until \(trainClock(end))") }
        return L10n( "\(repeatText(session)) · \(origin)")
    }

    /// Today's target as one bar: a normal day, then what training adds.
    private var targetBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let total = max(1, CGFloat(baseKcal + bumpKcal))
                let baseWidth = max(0, (geo.size.width - 3) * CGFloat(baseKcal) / total)
                HStack(spacing: 3) {
                    UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 5)
                        .fill(Palette.ink.opacity(0.82))
                        .frame(width: baseWidth)
                    UnevenRoundedRectangle(bottomTrailingRadius: 5, topTrailingRadius: 5)
                        .fill(LinearGradient(colors: [Palette.haze, Palette.hazeSoft], startPoint: .leading, endPoint: .trailing))
                        .shadow(color: Palette.haze.opacity(0.6), radius: 6)
                }
            }
            .frame(height: 10)
            .animation(Motion.settle, value: bumpKcal)
            HStack {
                barLabel(baseKcal.formatted(), L10n("normal day"), tint: Palette.ink)
                Spacer(minLength: 4)
                barLabel("+\(bumpKcal.formatted())", L10n("training"), tint: Palette.hazeSoft)
                Spacer(minLength: 4)
                barLabel(targetKcal.formatted(), L10n("today"), tint: Palette.amber)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n("\(baseKcal) on a normal day, plus \(bumpKcal) for training, makes \(targetKcal) today"))
    }

    private func barLabel(_ value: String, _ caption: String, tint: Color) -> some View {
        (Text(value).font(Typography.mono(12)).foregroundColor(tint) + Text(verbatim: " \(caption)").font(Typography.data(12, weight: .regular)).foregroundColor(Palette.inkSoft))
            .contentTransition(.numericText())
    }

    // MARK: Steps

    private enum StepState { case done, next, later, missed }

    private struct Step {
        let title: String
        let when: String
        let hint: String
        let detail: String
        let state: StepState
        let loggable: Bool
    }

    private var snackHint: String {
        snackBefore.map { "\($0.kcal)" } ?? "~250"
    }

    private var snackDetail: String {
        guard let snack = snackBefore else {
            return L10n("Something light — fuel without feeling full.")
        }
        switch snack.source {
        case "history":
            return L10n("\(snack.name) — you’ve had this before a session.")
        case "usual":
            return L10n("\(snack.name) — one of your plates.")
        default:
            return L10n("\(snack.name) — light, and it fits what you eat.")
        }
    }

    private var stepRows: [Step] {
        let refuelBy = end + window
        let refuelKcal = min(450, max(250, bumpKcal))
        let raw: [(title: String, when: String, hint: String, detail: String, missed: String, done: Bool, over: Bool, loggable: Bool)] = [
            (L10n("Snack before"), trainClock(max(0, start - 90)), snackHint, snackDetail, L10n("Nothing logged before — that’s fine. The refuel matters more."), (steps?.before ?? false) || snackLogged, nowMin >= start, true),
            (TrainKind.title(session.kind), trainClock(start), L10n("\(session.durationMin) min"), session.isPlanned ? L10n("Apple Health adds it when your watch saves it.") : L10n("From Apple Health."), "", (steps?.workout ?? false) || nowMin >= end, false, false),
            (L10n("Refuel after"), trainClock(refuelBy), "~\(refuelKcal)", L10n("Something with protein within \(window) min of finishing — chocolate milk or a sandwich. I’ll remind you."), L10n("Missed the window — still eat something with protein now."), steps?.refuel ?? false, nowMin > refuelBy, true),
            (bumpKcal > 0 ? L10n("Dinner, a bit bigger") : L10n("Dinner"), trainClock(dinnerMin), "", bumpKcal > 0 ? L10n("Your usual dinner plus a side.") : L10n("Your usual dinner."), "", steps?.dinner ?? false, false, true),
        ]
        var foundNext = false
        return raw.map { r in
            let state: StepState
            if r.done { state = .done }
            else if r.over && !r.missed.isEmpty { state = .missed }
            else if !foundNext { state = .next; foundNext = true }
            else { state = .later }
            return Step(title: r.title, when: r.when, hint: r.hint, detail: state == .missed ? r.missed : r.detail, state: state, loggable: r.loggable)
        }
    }

    private func stepRow(_ step: Step, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step.when)
                .font(Typography.mono(11))
                .foregroundStyle(step.state == .next ? Palette.hazeSoft : Palette.inkFaint)
                .frame(width: 44, alignment: .leading)
                .padding(.top, 3)

            VStack(spacing: 4) {
                ZStack {
                    switch step.state {
                    case .done:
                        Circle().fill(Palette.positive)
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.onBone)
                    case .next:
                        Circle().fill(Palette.background)
                        Circle().strokeBorder(Palette.hazeSoft, lineWidth: 2)
                    case .missed:
                        Circle().fill(Palette.background)
                        Circle().strokeBorder(Palette.amber, lineWidth: 1.5)
                        Text("!").font(Typography.data(10, weight: .semibold)).foregroundStyle(Palette.amber)
                    case .later:
                        Circle().fill(Palette.background)
                        Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
                    }
                }
                .frame(width: 20, height: 20)
                .shadow(color: step.state == .next ? Palette.haze.opacity(0.7) : .clear, radius: 6)
                .animation(Motion.settle, value: step.state == .done)
                if !last {
                    Capsule()
                        .fill(step.state == .done ? Palette.positive.opacity(0.5) : Color.white.opacity(0.10))
                        .frame(width: 2)
                        .frame(minHeight: 12)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(step.title)
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(step.state == .done ? Palette.inkFaint : Palette.ink)
                    Spacer(minLength: 8)
                    Text(step.hint)
                        .font(Typography.mono(11))
                        .foregroundStyle(Palette.inkFaint)
                }
                if step.state == .missed {
                    Text(step.detail)
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                } else if step.title == L10n("Snack before"), step.state == .done, !snackLogged {
                    Text(L10n("You had a meal before — that counts."))
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                } else if step.title == L10n("Snack before"), let snack = snackBefore {
                    Button {
                        onOpenSnack?(snack)
                    } label: {
                        snackPreview(snack)
                    }
                    .buttonStyle(PressableCard())
                    .padding(.top, 4)
                    .accessibilityHint(L10n("Opens the snack"))
                    .accessibilityValue(snackLogged ? L10n("Logged") : "")
                } else if step.state == .next {
                    Text(step.detail)
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .hintCopy()
                }
                if step.state == .next && step.loggable {
                    if step.title == L10n("Snack before"), let snack = snackBefore, !snackLogged {
                        Button {
                            onLogSnack?(snack)
                        } label: {
                            Text(loggingSnack ? "Logging…" : "Log it")
                                .font(Typography.data(13, weight: .medium))
                                .foregroundStyle(Palette.onBone)
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                                .background(Palette.ink, in: Capsule())
                        }
                        .buttonStyle(PressableCard())
                        .disabled(loggingSnack)
                        .padding(.top, 6)
                    } else if step.title != L10n("Snack before") {
                        Button(action: onLog) {
                            Text("Log it")
                                .font(Typography.data(13, weight: .medium))
                                .foregroundStyle(Palette.onBone)
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                                .background(Palette.ink, in: Capsule())
                        }
                        .buttonStyle(PressableCard())
                        .padding(.top, 6)
                    }
                }
            }
            .padding(.bottom, last ? 0 : 14)
        }
        .accessibilityElement(children: .combine)
    }

    private func snackPreview(_ snack: TrainingWeekResponse.SnackBefore) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(snack.name)
                    .font(Typography.data(15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            if let items = snack.items, !items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.prefix(3))) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.name)
                                .font(Typography.data(13, weight: .regular))
                                .foregroundStyle(Palette.inkSoft)
                            if let quantity = item.quantity, !quantity.isEmpty {
                                Text(quantity)
                                    .font(Typography.data(12, weight: .regular))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                            Spacer(minLength: 8)
                            Text("\(item.kcal)")
                                .font(Typography.mono(11))
                                .foregroundStyle(Palette.inkFaint)
                        }
                    }
                }
            } else if !snackLogged {
                Text(snackDetail)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if snackLogged {
                Text(L10n("Logged · \(snack.kcal.formatted()) kcal"))
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.positive)
            }
        }
        .padding(.vertical, snackLogged ? 10 : 8)
        .padding(.horizontal, snackLogged ? 12 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(snackLogged
                      ? AnyShapeStyle(LinearGradient(colors: [Palette.positive.opacity(0.10), Palette.positive.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                      : AnyShapeStyle(Color.white.opacity(0.05)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(snackLogged ? Palette.positive.opacity(0.40) : Color.clear)
        }
        .animation(Motion.settle, value: snackLogged)
    }
}

// MARK: - A day that's happened

/// A planned session once its time has come: "Did you train?" with Done and
/// Skipped, then the answer with a way to take it back.
struct SessionOutcomeRow: View {
    let session: TrainSession
    let onAnswer: (String?) -> Void

    var body: some View {
        Group {
            if session.isDone {
                answered(symbol: "checkmark", title: L10n("Done"), detail: L10n("Counted in today’s target"), tint: Palette.positive)
            } else if session.isSkipped {
                answered(symbol: "minus", title: L10n("Skipped"), detail: L10n("It adds nothing to the day"), tint: Palette.inkSoft)
            } else {
                question
            }
        }
        .animation(Motion.settle, value: session.outcome)
    }

    private var label: String {
        L10n("\(TrainKind.title(session.kind)) · \(trainClock(session.start))")
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Did you train?")
                    .font(Typography.data(15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(label)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }
            HStack(spacing: 8) {
                Button { onAnswer("DONE") } label: {
                    Label("Done", systemImage: "checkmark")
                        .font(Typography.data(14, weight: .semibold))
                        .foregroundStyle(Palette.onBone)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Palette.ink, in: Capsule())
                }
                .buttonStyle(PressableCard())
                Button { onAnswer("SKIPPED") } label: {
                    Text("Skipped")
                        .font(Typography.data(14, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .glassCapsule()
                }
                .buttonStyle(PressableCard())
            }
        }
        .padding(16)
        .glass(radius: 22, fill: Palette.ember.opacity(0.06), stroke: Palette.ember.opacity(0.3))
        .accessibilityElement(children: .contain)
    }

    private func answered(symbol: String, title: String, detail: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("\(title) · \(label)"))
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(detail)
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 8)
            Button("Undo") { onAnswer(nil) }
                .font(Typography.data(13, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
                .frame(minHeight: 44)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .glass(radius: 18)
    }
}

struct TrainPastCard: View {
    let day: TrainDay
    let weightKg: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                KindTile(kind: first.kind, tint: Color(hex: 0xD4D4D8), fill: Color.white.opacity(0.06))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.data(17, weight: .regular))
                        .foregroundStyle(Palette.ink)
                    Text(L10n("\(trainClock(first.start)) · \(first.isPlanned ? L10n("added by you") : L10n("from Apple Health"))"))
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                }
            }

            if let result {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(result.tint)
                    Text(result.detail)
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(result.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(result.tint.opacity(0.32)))
            }

            HStack(spacing: 8) {
                stat(burned, burnedCaption)
                stat(day.eatenKcal.map { L10n("\($0.formatted()) kcal") } ?? "—", L10n("eaten that day"))
            }
        }
        .padding(18)
        .glass(radius: 28, fill: Color.white.opacity(0.04), stroke: Color.white.opacity(0.09))
    }

    private var first: TrainSession { day.sessions[0] }

    private var title: String {
        let base = L10n("\(TrainKind.title(first.kind)) · \(first.durationMin) min")
        return day.sessions.count > 1 ? L10n("\(base) + \(day.sessions.count - 1) more") : base
    }

    private var result: (title: String, detail: String, tint: Color)? {
        switch day.refuel {
        case .done:
            let detail = day.refuelMeal.map { L10n("\($0.kcal) kcal at \(trainClock($0.at)) — within the window.") } ?? L10n("You ate within the window.")
            return (L10n("Refueled"), detail, Palette.positive)
        case .missed:
            return (L10n("Missed the refuel"), L10n("Nothing logged within \(TrainMath.refuelWindowMin) min of finishing. Next time, a drink counts."), Palette.amber)
        default:
            return nil
        }
    }

    private var recorded: Int? {
        let values = day.sessions.compactMap(\.activeKcal).filter { $0 > 0 }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    /// Sessions that happened (or might have): a skipped one burned nothing.
    private var trained: [TrainSession] { day.sessions.filter { !$0.isSkipped } }

    private var burned: String {
        if let recorded { return L10n( "\(recorded.formatted()) kcal") }
        if trained.isEmpty { return "—" }
        let estimate = trained.reduce(0) { $0 + TrainMath.sessionKcal($1, weightKg: weightKg) }
        return L10n( "~\(Int(estimate.rounded()).formatted()) kcal")
    }

    private var burnedCaption: String {
        if recorded != nil { return L10n("burned · Apple Health") }
        return trained.isEmpty ? L10n("skipped") : L10n("burned · estimate")
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Typography.mono(15)).foregroundStyle(Palette.ink)
            Text(caption).font(Typography.data(11, weight: .regular)).foregroundStyle(Palette.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A planned day ahead

struct TrainPlannedCard: View {
    let session: TrainSession
    /// What the day's training adds; nil on a second session that day.
    let dayBumpKcal: Int?
    let addCalories: Bool
    let dinnerMin: Int
    var snackBefore: TrainingWeekResponse.SnackBefore? = nil
    var onOpenSnack: ((TrainingWeekResponse.SnackBefore) -> Void)?
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                KindTile(kind: session.kind, fill: Palette.haze.opacity(0.14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(sessionTitle(session))
                        .font(Typography.data(17, weight: .regular))
                        .foregroundStyle(Palette.ink)
                    Text(session.repeats ? repeatText(session) : L10n("Just once"))
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 8)
                EditPill(action: onEdit).accessibilityLabel(L10n("Edit this session"))
            }

            if let bump = dayBumpKcal {
                Group {
                    if addCalories && bump > 0 {
                        Text(L10n("I’ll add \(bump.formatted()) to that day."))
                    } else {
                        Text("“Add calories” is off, so that day’s target stays the same.")
                    }
                }
                .font(Typography.display(22))
                .tracking(-0.4)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                snackRow
                line(trainClock(session.start), L10n("\(TrainKind.title(session.kind)), \(session.durationMin) min"))
                line(L10n("by \(trainClock(TrainMath.minute(session.end) + TrainMath.refuelWindowMin))"), L10n("Refuel with protein"))
                line(trainClock(dinnerMin), L10n("Dinner, a bit bigger"))
            }

            Text("You can change it until it starts.")
                .font(Typography.data(12, weight: .regular))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(18)
        .background(Palette.haze.opacity(0.06), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Palette.hazeSoft.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }

    private var snackRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(trainClock(max(0, TrainMath.minute(session.start) - 90)))
                .font(Typography.mono(11))
                .foregroundStyle(Palette.hazeSoft)
                .frame(width: 60, alignment: .leading)
                .padding(.top, 2)
            if let snack = snackBefore {
                Button {
                    onOpenSnack?(snack)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Snack before")
                                .font(Typography.data(13, weight: .regular))
                                .foregroundStyle(Color(hex: 0xD4D4D8))
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        Text(L10n("\(snack.name) · \(snack.kcal) kcal"))
                            .font(Typography.data(16, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                        if let items = snack.items, !items.isEmpty {
                            Text(items.map(\.name).joined(separator: " · "))
                                .font(Typography.data(13, weight: .regular))
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(snackReason(snack))
                                .font(Typography.data(12, weight: .regular))
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PressableCard())
                .accessibilityHint(L10n("Opens the snack"))
            } else {
                Text("Snack before")
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Color(hex: 0xD4D4D8))
            }
        }
    }

    private func snackReason(_ snack: TrainingWeekResponse.SnackBefore) -> String {
        switch snack.source {
        case "history": return L10n("You’ve had this before a session.")
        case "usual": return L10n("One of your plates.")
        default: return L10n("Light, and it fits what you eat.")
        }
    }

    private func line(_ at: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(at)
                .font(Typography.mono(11))
                .foregroundStyle(Palette.inkFaint)
                .frame(width: 60, alignment: .leading)
            Text(text)
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Color(hex: 0xD4D4D8))
        }
    }
}

// MARK: - A rest day

struct TrainRestCard: View {
    let day: TrainDay
    let onPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Headline("Rest day.", tail: "Normal food — rest is when you build back up.", size: 22)
            if !day.isPast {
                TrainPlanPill(title: day.isToday ? L10n("Plan a session today") : L10n("Plan a session on \(day.date.formatted(.dateTime.weekday(.wide).locale(AppLanguage.current.locale)))"), action: onPlan)
            } else if day.canAdd {
                Button(L10n("Trained without your watch? Add it."), action: onPlan)
                    .font(Typography.data(13, weight: .medium))
                    .foregroundStyle(Palette.hazeSoft)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glass(radius: 28, fill: Color.white.opacity(0.03), stroke: Color.white.opacity(0.08))
    }
}

// MARK: - Coming up

struct TrainComingUp: View {
    let sessions: [TrainSession]
    /// The last planned session's day.
    let through: Date?
    let weightKg: Double
    let addCalories: Bool
    let onOpen: (TrainSession) -> Void
    let onPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Coming up").sectionLabelStyle()
                Spacer()
                Text(through.map { L10n("Planned through \($0.formatted(.dateTime.day().month(.abbreviated).locale(AppLanguage.current.locale)))") } ?? L10n("Nothing planned yet"))
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(sessions) { s in
                    Button { onOpen(s) } label: { row(s) }
                        .buttonStyle(.plain)
                        .accessibilityHint(L10n("Edits the session"))
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                }
                Button(action: onPlan) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.hazeSoft)
                            .frame(width: 44, height: 40)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hazeSoft.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Plan ahead")
                                .font(Typography.data(14, weight: .regular))
                                .foregroundStyle(Palette.hazeSoft)
                            Text("Once, or every week for 8 weeks")
                                .font(Typography.data(12, weight: .regular))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .glass(radius: 22, fill: Color.white.opacity(0.035), stroke: Color.white.opacity(0.08))
        }
    }

    private func row(_ s: TrainSession) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(s.start.formatted(.dateTime.weekday(.abbreviated).locale(AppLanguage.current.locale)).uppercased())
                    .font(Typography.mono(10))
                    .foregroundStyle(Palette.hazeSoft)
                Text(s.start.formatted(.dateTime.day()))
                    .font(Typography.data(16, weight: .medium))
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 44)
            .padding(.vertical, 6)
            .background(Palette.haze.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(L10n("\(TrainKind.title(s.kind)) · \(s.durationMin) min"))
                        .font(Typography.data(14, weight: .regular))
                        .foregroundStyle(Palette.ink)
                    if s.repeats {
                        Image(systemName: "repeat")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                            .accessibilityLabel("weekly")
                    }
                }
                Text(s.repeats
                     ? L10n("\(trainClock(s.start)) · every \(s.start.formatted(.dateTime.weekday(.wide).locale(AppLanguage.current.locale)))")
                     : L10n("\(trainClock(s.start)) · once"))
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 8)
            if addCalories {
                Text("+\(TrainMath.bump([s], weightKg: weightKg))")
                    .font(Typography.mono(12))
                    .foregroundStyle(Palette.hazeSoft)
            }
            Image(systemName: "chevron.forward")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Settings, folded into one row

struct TrainSettingsRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(hex: 0xD4D4D8))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)
                Text("Training settings")
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glass(radius: 20, fill: Color.white.opacity(0.035), stroke: Color.white.opacity(0.08))
        }
        .buttonStyle(PressableCard())
    }
}
