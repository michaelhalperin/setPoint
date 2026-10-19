import SwiftUI

// Train, drawn as two pictures: today as a river from the snack before to dinner
// (the session a lit bar, the refuel window dashed after it), and the week as
// pillars sized by the extra food each day earned. Tap a pillar for that day.

enum TrainKind {
    static func title(_ kind: String) -> String {
        switch kind {
        case "CARDIO": return "Cardio"
        case "MIXED": return "Mixed"
        default: return "Strength"
        }
    }

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "CARDIO": return "figure.run"
        case "MIXED": return "figure.mixed.cardio"
        default: return "dumbbell.fill"
        }
    }

    static func source(_ source: String) -> String {
        switch source {
        case "HEALTHKIT": return "Apple Health"
        case "PLANNED": return "planned"
        default: return "added by you"
        }
    }
}

// MARK: - Today

struct TrainTodayCard: View {
    let today: TrainingWeekResponse.Today

    private var workout: TrainingWeekResponse.Session? { today.workouts.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(label).sectionLabelStyle(Palette.hazeSoft)
                Spacer(minLength: 8)
                if today.bumpKcal > 0 {
                    Text("+\(today.bumpKcal) kcal")
                        .font(Typography.mono(12))
                        .foregroundStyle(Palette.hazeSoft)
                }
            }
            Headline(title, tail: tail, size: 28)

            if workout != nil {
                SessionRiver(today: today)
                    .frame(height: 70)
            }

            if today.bumpKcal > 0 {
                equation
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Palette.haze.opacity(0.17), Palette.haze.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Palette.hazeSoft.opacity(0.30))
        }
    }

    private var label: String {
        guard let workout else { return "Today · rest" }
        return "Today · \(TrainKind.title(workout.kind).lowercased()) · \(clock24(workout.startMin))"
    }

    private var title: String {
        guard let workout else { return "Rest day." }
        return "\(TrainKind.title(workout.kind)) day."
    }

    private var tail: String {
        if workout == nil { return "Plates as usual: \(today.baseKcal.formatted()) kcal." }
        return today.bumpKcal > 0 ? "More food today, timed around it." : "Food timed around it."
    }

    private var equation: some View {
        HStack(spacing: 6) {
            term(today.baseKcal.formatted(), "your day", tint: nil)
            Text("+").foregroundStyle(Palette.inkFaint)
            term(today.bumpKcal.formatted(), "the session", tint: Palette.haze)
            Text("=").foregroundStyle(Palette.inkFaint)
            term(today.targetKcal.formatted(), "today", tint: Palette.ember)
        }
        .font(Typography.data(15, weight: .light))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(today.baseKcal) plus \(today.bumpKcal) for the session makes \(today.targetKcal) kilocalories today")
    }

    private func term(_ value: String, _ caption: String, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Typography.mono(15))
                .foregroundStyle(tint == Palette.haze ? Palette.hazeSoft : tint == Palette.ember ? Palette.amber : Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(caption)
                .font(Typography.data(11, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.map { $0.opacity(0.13) } ?? Color.white.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint == Palette.haze ? Palette.hazeSoft.opacity(0.35) : tint == Palette.ember ? Color(hex: 0xFF8A50, opacity: 0.5) : Color.white.opacity(0.08))
        }
    }
}

/// Today from the snack before to dinner: rings for food, a lit bar for the
/// session, a dashed band for the refuel window.
struct SessionRiver: View {
    let today: TrainingWeekResponse.Today

    /// The backend counts a refuel within this many minutes of the session ending.
    static let refuelWindowMin = 45

    private struct Stop: Identifiable {
        enum Kind { case before, session, refuel, dinner }
        let id: String
        let kind: Kind
        let atMin: Int
        let lengthMin: Int
        let top: String
        let time: String?
    }

    private var stops: [Stop] {
        let workout = today.workouts.first
        return today.timeline.compactMap { event -> Stop? in
            switch event.kind {
            case "before":
                return Stop(id: "before", kind: .before, atMin: event.atMin, lengthMin: 0, top: "EAT", time: clock24(event.atMin))
            case "workout":
                let title = workout.map { TrainKind.title($0.kind).uppercased() } ?? "SESSION"
                return Stop(id: "session", kind: .session, atMin: event.atMin, lengthMin: max(20, workout?.durationMin ?? 60), top: title, time: clock24(event.atMin))
            case "refuel":
                return Stop(id: "refuel", kind: .refuel, atMin: event.atMin, lengthMin: Self.refuelWindowMin, top: "REFUEL", time: nil)
            case "dinner":
                return Stop(id: "dinner", kind: .dinner, atMin: event.atMin, lengthMin: 0, top: "DINNER", time: clock24(event.atMin))
            default:
                return nil
            }
        }
    }

    var body: some View {
        let stops = stops
        let lo = Double(((stops.map(\.atMin).min() ?? 840) - 30) / 60 * 60)
        let hi = Double(((stops.map { $0.atMin + $0.lengthMin }.max() ?? 1260) + 89) / 60 * 60)
        GeometryReader { geo in
            let width = geo.size.width
            let x = { (minute: Int) -> CGFloat in CGFloat((Double(minute) - lo) / max(1, hi - lo)) * width }
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: width, height: 2)
                    .offset(y: 40)
                ForEach(stops) { stop in
                    let start = x(stop.atMin)
                    let length = stop.lengthMin > 0 ? max(14, x(stop.atMin + stop.lengthMin) - start) : 0
                    VStack(alignment: length > 0 ? .leading : .center, spacing: 6) {
                        Text(stop.top)
                            .font(Typography.mono(9))
                            .tracking(0.9)
                            .foregroundStyle(topColor(stop.kind))
                            .fixedSize()
                            .frame(height: 12)
                        mark(stop.kind)
                            .frame(width: length > 0 ? length : 12, height: 12)
                        Text(stop.time ?? " ")
                            .font(Typography.mono(10))
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize()
                            .frame(height: 12)
                    }
                    .frame(width: length > 0 ? length : 44, alignment: length > 0 ? .leading : .center)
                    .offset(x: length > 0 ? start : start - 22, y: 17)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stops.map { stop in
            switch stop.kind {
            case .before: return "eat at \(clock24(stop.atMin))"
            case .session: return "\(stop.top.lowercased()) at \(clock24(stop.atMin))"
            case .refuel: return "refuel within \(Self.refuelWindowMin) minutes"
            case .dinner: return "dinner at \(clock24(stop.atMin))"
            }
        }.joined(separator: ", "))
    }

    @ViewBuilder
    private func mark(_ kind: Stop.Kind) -> some View {
        switch kind {
        case .before:
            Circle().fill(Palette.background).overlay(Circle().strokeBorder(Palette.amber, lineWidth: 2))
        case .session:
            Capsule()
                .fill(LinearGradient(colors: [Palette.haze, Palette.hazeSoft], startPoint: .leading, endPoint: .trailing))
                .shadow(color: Palette.haze.opacity(0.8), radius: 7)
        case .refuel:
            Capsule()
                .fill(Palette.hazeSoft.opacity(0.10))
                .overlay(Capsule().strokeBorder(Palette.hazeSoft, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
        case .dinner:
            Circle().fill(Palette.background).overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5))
        }
    }

    private func topColor(_ kind: Stop.Kind) -> Color {
        switch kind {
        case .before: return Palette.amber
        case .dinner: return Palette.inkSoft
        default: return Palette.hazeSoft
        }
    }
}

// MARK: - Week

struct TrainWeekCard: View {
    let week: TrainingWeekResponse
    let todayISO: String
    @Binding var selected: String?

    private var selectedDay: TrainingWeekResponse.Day? {
        let id = selected ?? todayISO
        return week.days.first { $0.date == id } ?? week.days.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("This week").sectionLabelStyle()
                Spacer(minLength: 8)
                fueled
            }
            .padding(.horizontal, 2)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(week.days) { day in
                    pillar(day)
                }
            }
            .frame(height: 156)

            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)

            if let day = selectedDay {
                detail(day)
                    .padding(.horizontal, 2)
                    .id(day.date)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .glass(radius: 26)
    }

    // MARK: Fueled

    @ViewBuilder
    private var fueled: some View {
        let total = min(week.fueledWell.total, 8)
        if total > 0 {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(0..<total, id: \.self) { i in
                        Capsule()
                            .fill(i < week.fueledWell.good ? Palette.amber : Color.white.opacity(0.12))
                            .frame(width: 14, height: 6)
                    }
                }
                .accessibilityHidden(true)
                Text("\(week.fueledWell.good) of \(week.fueledWell.total) fueled well")
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }
        } else {
            Text("Refuels count after a session")
                .font(Typography.data(12, weight: .regular))
                .foregroundStyle(Palette.inkFaint)
        }
    }

    // MARK: Pillar

    private enum PillarState { case rest, done, planned }

    private func state(_ day: TrainingWeekResponse.Day) -> PillarState {
        if day.rest || day.workouts.isEmpty { return .rest }
        return day.workouts.contains { $0.source != "PLANNED" } ? .done : .planned
    }

    private func pillar(_ day: TrainingWeekResponse.Day) -> some View {
        let state = state(day)
        let on = day.date == (selectedDay?.date ?? todayISO)
        let isToday = day.date == todayISO
        let height: CGFloat = state == .rest ? 10 : 34 + CGFloat(min(day.bumpKcal, 600)) / 600 * 74
        return Button {
            withAnimation(Motion.settle) { selected = day.date }
        } label: {
            VStack(spacing: 6) {
                Text(day.bumpKcal > 0 ? "+\(day.bumpKcal)" : " ")
                    .font(Typography.mono(9))
                    .foregroundStyle(Palette.hazeSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: 12)
                cap(state, on: on)
                    .frame(maxWidth: 34)
                    .frame(height: height)
                Text(weekdayLetter(day.date))
                    .font(Typography.mono(10))
                    .foregroundStyle(on ? Palette.ink : isToday ? Palette.hazeSoft : Palette.inkFaint)
            }
            .padding(.top, 6)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(on ? Color.white.opacity(0.05) : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(on ? Color.white.opacity(0.12) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel(accessibility(day, state: state, isToday: isToday))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder
    private func cap(_ state: PillarState, on: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        switch state {
        case .rest:
            shape.fill(Color.white.opacity(0.08))
        case .planned:
            shape
                .fill(Palette.haze.opacity(0.16))
                .overlay(shape.strokeBorder(Palette.hazeSoft.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        case .done:
            shape
                .fill(LinearGradient(colors: [Palette.hazeSoft, Palette.haze], startPoint: .top, endPoint: .bottom))
                .shadow(color: Palette.haze.opacity(on ? 0.75 : 0.45), radius: on ? 9 : 5)
        }
    }

    private func accessibility(_ day: TrainingWeekResponse.Day, state: PillarState, isToday: Bool) -> String {
        let name = weekdayLong(day.date) + (isToday ? ", today" : "")
        switch state {
        case .rest: return "\(name), rest"
        case .planned, .done:
            let kind = day.workouts.first.map { TrainKind.title($0.kind) } ?? "Session"
            let extra = day.bumpKcal > 0 ? ", plus \(day.bumpKcal) kilocalories" : ""
            return "\(name), \(kind)\(state == .planned ? ", planned" : "")\(extra)"
        }
    }

    // MARK: Detail

    @ViewBuilder
    private func detail(_ day: TrainingWeekResponse.Day) -> some View {
        let isToday = day.date == todayISO
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(weekdayLong(day.date) + (isToday ? " · today" : ""))
                    .font(Typography.data(17, weight: .regular))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Text(day.rest ? "Rest" : day.bumpKcal > 0 ? "+\(day.bumpKcal) kcal" : "No extra food")
                    .font(Typography.mono(12))
                    .foregroundStyle(day.rest ? Palette.inkFaint : Palette.hazeSoft)
            }

            ForEach(day.workouts) { session in
                HStack(spacing: 12) {
                    Image(systemName: TrainKind.symbol(session.kind))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.hazeSoft)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.haze.opacity(0.14)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hazeSoft.opacity(0.3)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TrainKind.title(session.kind))
                            .font(Typography.data(15, weight: .regular))
                            .foregroundStyle(Palette.ink)
                        Text(sessionMeta(session))
                            .font(Typography.data(12, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }

            if isToday, !day.workouts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(week.today.timeline) { event in
                        HStack(spacing: 10) {
                            stepDot(event.kind)
                                .frame(width: 9, height: 9)
                            Text(clock24(event.atMin))
                                .font(Typography.mono(11))
                                .foregroundStyle(Palette.inkSoft)
                                .frame(width: 42, alignment: .leading)
                            Text(stepText(event))
                                .font(Typography.data(14, weight: .regular))
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.leading, 4)
            }

            if day.rest {
                Text("Rest day. Plates as usual: \(week.today.baseKcal.formatted()) kcal.")
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
    }

    private func sessionMeta(_ session: TrainingWeekResponse.Session) -> String {
        var parts = ["\(session.durationMin) min", clock24(session.startMin), TrainKind.source(session.source)]
        if let kcal = session.activeKcal, kcal > 0 { parts.append("\(kcal) active kcal") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func stepDot(_ kind: String) -> some View {
        switch kind {
        case "workout":
            RoundedRectangle(cornerRadius: 3).fill(Palette.haze)
        case "refuel":
            Circle().strokeBorder(Palette.hazeSoft, lineWidth: 1.5)
        case "before":
            Circle().strokeBorder(Palette.amber, lineWidth: 1.5)
        default:
            Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
        }
    }

    private func stepText(_ event: TrainingWeekResponse.TimelineEvent) -> String {
        switch event.kind {
        case "before": return "Eat before you train"
        case "workout": return week.today.workouts.first.map { TrainKind.title($0.kind) } ?? "Session"
        case "refuel": return "Refuel within \(SessionRiver.refuelWindowMin) min"
        case "dinner": return week.today.bumpKcal > 0 ? "Dinner · a bit bigger tonight" : "Dinner"
        default: return event.label
        }
    }

    // MARK: Dates

    private func date(_ iso: String) -> Date? { WeekStation.parse(iso) }

    private func weekdayLetter(_ iso: String) -> String {
        guard let d = date(iso) else { return "·" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return String(calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: d) - 1])
    }

    private func weekdayLong(_ iso: String) -> String {
        guard let d = date(iso) else { return iso }
        let f = DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEEE"
        return f.string(from: d)
    }
}
