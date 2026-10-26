import SwiftUI

/// The Train screen's sheets.
enum TrainSheet: Identifiable {
    /// Plan a session, starting from this date and time.
    case plan(Date)
    /// Change a session that hasn't started.
    case edit(TrainSession)
    case settings
    case snack(TrainingWeekResponse.SnackBefore)

    var id: String {
        switch self {
        case let .plan(date): return "plan-\(date.timeIntervalSince1970)"
        case let .edit(s): return "edit-\(s.id)"
        case .settings: return "settings"
        case let .snack(s): return "snack-\(s.id)"
        }
    }
}

private func sheetLabel(_ text: String) -> some View {
    Text(LocalizedStringKey(text)).sectionLabelStyle()
}

private func chipFill(_ on: Bool) -> some ShapeStyle {
    on ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Color.white.opacity(0.04))
}

private func foodKcal(kind: String, durationMin: Int, weightKg: Double) -> Int {
    TrainMath.bump([TrainSession(id: "draft", kind: kind, source: "PLANNED", start: .now, durationMin: durationMin)], weightKg: weightKg)
}

private let lengthOptions = [30, 45, 60, 90, 120]

private func lengthTitle(_ m: Int) -> String {
    m >= 120 && m % 60 == 0 ? L10n("\(m / 60) h") : L10n("\(m) min")
}

// MARK: - Plan a session

/// Plan a session: what, which day (a row of the next two weeks, or a calendar
/// further ahead), a quick start time, how long, and whether it repeats on one
/// or more weekdays. Shows what it does to food before it's saved.
struct PlanSessionSheet: View {
    let earliest: Date
    let horizonEnd: Date
    let weightKg: Double
    let addCalories: Bool
    /// Days that already have a session, as day keys.
    let busyDays: Set<String>
    let onSave: (SessionDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: SessionDraft
    @State private var showCalendar = false
    @State private var otherTime = false

    private static let quickTimes = [7 * 60, 8 * 60, 12 * 60, 17 * 60, 18 * 60, 19 * 60]

    init(start: Date, earliest: Date, horizonEnd: Date, weightKg: Double, addCalories: Bool, busyDays: Set<String>, onSave: @escaping (SessionDraft) -> Void) {
        self.earliest = earliest
        self.horizonEnd = horizonEnd
        self.weightKg = weightKg
        self.addCalories = addCalories
        self.busyDays = busyDays
        self.onSave = onSave
        _draft = State(initialValue: SessionDraft(start: start))
        _otherTime = State(initialValue: !Self.quickTimes.contains(TrainMath.minute(start)))
        let inRow = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: start)).day ?? 0
        _showCalendar = State(initialValue: inRow < 0 || inRow > 13)
    }

    private var inPast: Bool { draft.start <= .now }
    private var starts: [Date] { inPast ? [draft.start] : TrainMath.plannedStarts(from: draft.start, weekdays: draft.repeatDays, until: horizonEnd) }
    private var valid: Bool { draft.start >= earliest && draft.start < horizonEnd }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Headline("Plan a session.", tail: "I’ll plan food around it.", size: 30)
                kindTiles
                dayPicker
                timePicker
                VStack(alignment: .leading, spacing: 10) {
                    sheetLabel("How long")
                    SegmentedPills(options: lengthOptions, selection: $draft.durationMin, title: lengthTitle)
                }
                if !inPast { repeatBox }
                foodCard
            }
            .padding(Space.gutter)
            .padding(.top, Space.xs)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            ActionButton(title: saveTitle, kind: .primary, symbol: "plus") {
                onSave(inPast ? SessionDraft(kind: draft.kind, start: draft.start, durationMin: draft.durationMin) : draft)
                dismiss()
            }
            .disabled(!valid)
            .opacity(valid ? 1 : 0.45)
            .padding(.horizontal, Space.gutter)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Palette.sheet)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheet)
        .presentationCornerRadius(32)
    }

    private var saveTitle: String {
        if inPast { return L10n( "Add session") }
        return starts.count > 1 ? L10n( "Plan \(starts.count) sessions") : L10n( "Plan session")
    }

    // MARK: What

    private var kindTiles: some View {
        HStack(spacing: 8) {
            ForEach(TrainKind.all, id: \.self) { kind in
                let on = draft.kind == kind
                Button {
                    Haptics.select()
                    draft.kind = kind
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: TrainKind.symbol(kind))
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(on ? Palette.hazeSoft : Palette.inkSoft)
                        Text(TrainKind.title(kind))
                            .font(Typography.data(14, weight: .regular))
                            .foregroundStyle(Palette.ink)
                    }
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .background(on ? Palette.haze.opacity(0.16) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(on ? Palette.hazeSoft.opacity(0.7) : Color.white.opacity(0.08), lineWidth: on ? 1.5 : 1))
                }
                .buttonStyle(PressableCard())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    // MARK: Which day

    private var rowDays: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<14).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    private var dayPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sheetLabel("Day")
                Spacer()
                Button(showCalendar ? L10n("Hide calendar") : L10n("Further ahead")) {
                    withAnimation(Motion.settle) { showCalendar.toggle() }
                }
                .font(Typography.data(13, weight: .medium))
                .foregroundStyle(Palette.hazeSoft)
                .frame(minHeight: 44)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(rowDays, id: \.self) { day in dayChip(day) }
                }
                .padding(.horizontal, Space.gutter)
            }
            .padding(.horizontal, -Space.gutter)
            if showCalendar {
                DatePicker("Day", selection: Binding(get: { draft.start }, set: { setDay($0) }), in: earliest...horizonEnd.addingTimeInterval(-60), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(Palette.hazeSoft)
                    .padding(8)
                    .glass(radius: 20, fill: Color.white.opacity(0.04), stroke: Color.white.opacity(0.08))
                    .transition(.opacity)
            }
        }
    }

    private func dayChip(_ day: Date) -> some View {
        let on = Calendar.current.isDate(day, inSameDayAs: draft.start)
        let busy = busyDays.contains(TrainMath.dayKey(day))
        let today = Calendar.current.isDateInToday(day)
        return Button { setDay(day) } label: {
            VStack(spacing: 4) {
                Text(today ? L10n("TODAY") : day.appShortWeekday.uppercased())
                    .font(Typography.mono(10))
                    .opacity(0.8)
                Text(day.formatted(.dateTime.day().locale(AppLanguage.current.locale)))
                    .font(Typography.data(17, weight: .medium))
                Circle()
                    .fill(busy ? (on ? Color(hex: 0x4F46E5) : Palette.hazeSoft) : .clear)
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(on ? Palette.onBone : Palette.ink)
            .frame(width: 56, height: 70)
            .background(chipFill(on), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? .clear : Color.white.opacity(0.08)))
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel(L10n("\(today ? L10n("Today, ") : "")\(day.formatted(.dateTime.weekday(.wide).day().locale(AppLanguage.current.locale)))\(busy ? L10n(", has a session") : "")"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Moves the session to `day`, keeping its time. A single repeat weekday follows the day.
    private func setDay(_ day: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: draft.start)
        let oldWeekday = Calendar.current.component(.weekday, from: draft.start)
        draft.start = TrainMath.at(c.hour ?? 17, c.minute ?? 0, on: day)
        if draft.repeatDays == [oldWeekday] {
            draft.repeatDays = [Calendar.current.component(.weekday, from: draft.start)]
        }
        Haptics.select()
    }

    // MARK: When

    private var timePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sheetLabel("Starts at")
            FlowRow(spacing: 6) {
                ForEach(Self.quickTimes, id: \.self) { minute in
                    let on = !otherTime && TrainMath.minute(draft.start) == minute
                    Button {
                        otherTime = false
                        draft.start = TrainMath.at(minute / 60, minute % 60, on: draft.start)
                        Haptics.select()
                    } label: {
                        Text(trainClock(minute))
                            .font(Typography.mono(13))
                            .foregroundStyle(on ? Palette.onBone : Palette.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(chipFill(on), in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? .clear : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(PressableCard())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                Button {
                    withAnimation(Motion.settle) { otherTime = true }
                } label: {
                    Text(otherTime ? trainClock(draft.start) : L10n("Other…"))
                        .font(otherTime ? Typography.mono(13) : Typography.data(13, weight: .regular))
                        .foregroundStyle(otherTime ? Palette.onBone : Palette.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(chipFill(otherTime), in: Capsule())
                        .overlay(Capsule().strokeBorder(otherTime ? .clear : Color.white.opacity(0.08)))
                }
                .buttonStyle(PressableCard())
            }
            if otherTime {
                HStack {
                    Text("Pick a time")
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    DatePicker("Starts at", selection: $draft.start, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(Palette.hazeSoft)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .glass(radius: 18, fill: Color.white.opacity(0.04), stroke: Color.white.opacity(0.08))
                .transition(.opacity)
            }
        }
    }

    // MARK: Repeat

    private func setRepeat(_ on: Bool) {
        withAnimation(Motion.settle) {
            draft.repeatDays = on ? [Calendar.current.component(.weekday, from: draft.start)] : []
        }
    }

    private var repeatBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { !draft.repeatDays.isEmpty }, set: setRepeat)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repeat every week")
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(Palette.ink)
                    Text(repeatLine)
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.inkFaint)
                }
                // The whole row flips it, not just the switch.
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { setRepeat(draft.repeatDays.isEmpty) }
            }
            .tint(Palette.haze)
            if !draft.repeatDays.isEmpty {
                HStack {
                    ForEach(weekdayOrder, id: \.self) { weekday in weekdayButton(weekday) }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glass(radius: 20, fill: Color.white.opacity(0.04), stroke: Color.white.opacity(0.08))
    }

    /// Weekdays in the region's order (Sunday first in Israel).
    private var weekdayOrder: [Int] {
        let first = AppLanguage.current.calendar.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private func weekdayButton(_ weekday: Int) -> some View {
        let on = draft.repeatDays.contains(weekday)
        let symbols = AppLanguage.current.calendar.veryShortStandaloneWeekdaySymbols
        let names = AppLanguage.current.calendar.standaloneWeekdaySymbols
        return Button {
            if on {
                guard draft.repeatDays.count > 1 else { return }
                draft.repeatDays.remove(weekday)
            } else {
                draft.repeatDays.insert(weekday)
            }
            Haptics.select()
        } label: {
            Text(symbols[weekday - 1])
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(on ? Color(hex: 0xE0E7FF) : Palette.inkSoft)
                .frame(width: 40, height: 40)
                .background(on ? Palette.haze.opacity(0.22) : Color.white.opacity(0.04), in: Circle())
                .overlay(Circle().strokeBorder(on ? Palette.hazeSoft.opacity(0.8) : Color.white.opacity(0.08), lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(PressableCard())
        .frame(maxWidth: .infinity)
        .accessibilityLabel(L10n("Every \(names[weekday - 1])"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var repeatLine: String {
        guard !draft.repeatDays.isEmpty else { return L10n( "Just this once") }
        let names = Calendar.current.standaloneWeekdaySymbols
        let which = draft.repeatDays.count == 1
            ? L10n( "Every \(names[draft.repeatDays.first! - 1])")
            : L10n( "\(draft.repeatDays.count) days a week")
        if let last = starts.last {
            let until = last.formatted(.dateTime.day().month(.abbreviated).locale(AppLanguage.current.locale))
            return L10n( "\(which) for 8 weeks · until \(until)")
        }
        return L10n( "\(which) for 8 weeks")
    }

    // MARK: Food

    private var foodCard: some View {
        let kcal = foodKcal(kind: draft.kind, durationMin: draft.durationMin, weightKg: weightKg)
        let start = TrainMath.minute(draft.start)
        let title: String = {
            guard addCalories, kcal > 0 else { return L10n( "“Add calories” is off") }
            return starts.count > 1
                ? L10n( "+\(kcal) kcal on each of those days")
                : L10n( "+\(kcal) kcal that day")
        }()
        let line = addCalories
            ? L10n("A snack around \(trainClock(start - 90)), a refuel by \(trainClock(start + draft.durationMin + TrainMath.refuelWindowMin)), and a bigger dinner. I’ll nudge you before if you haven’t eaten.")
            : L10n("The target stays the same, but I’ll still plan a snack before and a refuel by \(trainClock(start + draft.durationMin + TrainMath.refuelWindowMin)).")
        return HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xE0E7FF), Palette.haze], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 6))
                .frame(width: 10, height: 10)
                .shadow(color: Palette.haze.opacity(0.7), radius: 5)
                .padding(.top, 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.ink)
                Text(LocalizedStringKey(line))
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .hintCopy()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.haze.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.hazeSoft.opacity(0.30)))
    }
}

// MARK: - Change a session

/// Change a session before it starts. For a weekly one, "only this" or "this and
/// after" is picked first, so Save and Delete both say what they'll touch.
struct EditSessionSheet: View {
    let session: TrainSession
    /// This session and the later ones in its repeat.
    let followingCount: Int
    let horizonEnd: Date
    let weightKg: Double
    let addCalories: Bool
    let onSave: (SessionDraft, SessionScope) -> Void
    let onDelete: (SessionScope) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: SessionDraft
    @State private var scope: SessionScope = .one
    @State private var showCalendar = false
    @State private var askingDelete = false

    init(session: TrainSession, followingCount: Int, horizonEnd: Date, weightKg: Double, addCalories: Bool, onSave: @escaping (SessionDraft, SessionScope) -> Void, onDelete: @escaping (SessionScope) -> Void) {
        self.session = session
        self.followingCount = followingCount
        self.horizonEnd = horizonEnd
        self.weightKg = weightKg
        self.addCalories = addCalories
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: SessionDraft(kind: session.kind, start: session.start, durationMin: session.durationMin))
    }

    private var dayName: String { session.start.formatted(.dateTime.weekday(.abbreviated).day().locale(AppLanguage.current.locale)) }
    private var changed: Bool { draft.kind != session.kind || draft.start != session.start || draft.durationMin != session.durationMin }
    private var canSave: Bool { changed && draft.start > .now && draft.start < horizonEnd }
    private var count: Int { scope == .following ? followingCount : 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.repeats
                         ? L10n("\(session.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppLanguage.current.locale))) · every \(session.start.formatted(.dateTime.weekday(.wide).locale(AppLanguage.current.locale)))")
                         : L10n("\(session.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppLanguage.current.locale))) · once"))
                        .textCase(.uppercase)
                        .font(Typography.mono(11))
                        .tracking(1.3)
                        .foregroundStyle(Palette.hazeSoft)
                    Headline("Change this session.", tail: "Open until it starts.", size: 30)
                }

                if session.repeats { scopePicker }

                SegmentedPills(options: TrainKind.all, selection: $draft.kind, title: { TrainKind.title($0) })

                GlassList {
                    Button {
                        withAnimation(Motion.settle) { showCalendar.toggle() }
                    } label: {
                        HStack {
                            Text("Day")
                                .font(Typography.data(15, weight: .regular))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text(scope == .following
                                 ? L10n("\(draft.start.formatted(.dateTime.weekday(.wide).locale(AppLanguage.current.locale)))s, from \(draft.start.formatted(.dateTime.day().month(.abbreviated).locale(AppLanguage.current.locale)))")
                                 : draft.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(AppLanguage.current.locale)))
                                .font(Typography.data(15, weight: .regular))
                                .foregroundStyle(Color(hex: 0xD4D4D8))
                            Image(systemName: showCalendar ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .frame(minHeight: 54)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showCalendar {
                        DatePicker("Day", selection: $draft.start, in: Date.now...horizonEnd.addingTimeInterval(-60), displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .tint(Palette.hazeSoft)
                            .transition(.opacity)
                    }
                    ListDivider()
                    HStack {
                        Text("Starts at")
                            .font(Typography.data(15, weight: .regular))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        stepButton("minus", label: "Thirty minutes earlier") { shift(-30) }
                        Text(trainClock(draft.start))
                            .font(Typography.mono(17))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 64)
                            .contentTransition(.numericText())
                        stepButton("plus", label: "Thirty minutes later") { shift(30) }
                    }
                    .frame(minHeight: 54)
                }

                SegmentedPills(options: lengthOptions, selection: $draft.durationMin, title: lengthTitle)

                foodChange

                if !draft.start.isAfterNow && changed {
                    Text("Pick a time that hasn’t passed — a session can only be changed before it starts.")
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button { askingDelete = true } label: {
                    Text(!session.repeats ? L10n("Delete session") : scope == .following ? L10n("Delete \(dayName) and the ones after") : L10n("Delete only \(dayName)"))
                        .font(Typography.data(15, weight: .medium))
                        .foregroundStyle(Palette.amber)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .confirmationDialog(scope == .following ? L10n("Delete \(followingCount) sessions?") : L10n("Delete this session?"), isPresented: $askingDelete, titleVisibility: .visible) {
                    Button(L10n("Delete"), role: .destructive) {
                        onDelete(scope)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
            .padding(Space.gutter)
            .padding(.top, Space.xs)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            ActionButton(title: count > 1 ? L10n("Save · \(count) sessions") : L10n("Save"), kind: .primary, symbol: "checkmark") {
                onSave(draft, scope)
                dismiss()
            }
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.4)
            .padding(.horizontal, Space.gutter)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Palette.sheet)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheet)
        .presentationCornerRadius(32)
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sheetLabel("Change")
            HStack(spacing: 8) {
                scopeCard(.one, title: L10n("Only \(dayName)"), sub: L10n("The others stay"))
                scopeCard(.following, title: L10n("\(dayName) and after"), sub: followingCount == 1 ? L10n("1 session") : L10n("\(followingCount) sessions"))
            }
        }
    }

    private func scopeCard(_ value: SessionScope, title: String, sub: String) -> some View {
        let on = scope == value
        return Button {
            Haptics.select()
            scope = value
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(Typography.data(14, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(LocalizedStringKey(sub))
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(on ? Palette.hazeSoft : Palette.inkFaint)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(.horizontal, 14)
            .background(on ? Palette.haze.opacity(0.16) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? Palette.hazeSoft.opacity(0.7) : Color.white.opacity(0.08), lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(PressableCard())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.06), in: Circle())
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel(LocalizedStringKey(label))
    }

    private func shift(_ minutes: Int) {
        let moved = draft.start.addingTimeInterval(Double(minutes) * 60)
        guard Calendar.current.isDate(moved, inSameDayAs: draft.start) else { return }
        withAnimation(Motion.settle) { draft.start = moved }
        Haptics.select()
    }

    private var foodChange: some View {
        let before = foodKcal(kind: session.kind, durationMin: session.durationMin, weightKg: weightKg)
        let after = foodKcal(kind: draft.kind, durationMin: draft.durationMin, weightKg: weightKg)
        let start = TrainMath.minute(draft.start)
        return HStack(spacing: 14) {
            if after != before {
                VStack(alignment: .leading, spacing: 2) {
                    Text("+\(before)").font(Typography.mono(15)).foregroundStyle(Palette.inkFaint).strikethrough()
                    Text("before").font(Typography.data(11, weight: .regular)).foregroundStyle(Palette.inkFaint)
                }
                Image(systemName: "arrow.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("+\(after)").font(Typography.mono(15)).foregroundStyle(Palette.hazeSoft).contentTransition(.numericText())
                Text(addCalories ? "kcal a day" : "kcal burned").font(Typography.data(11, weight: .regular)).foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 8)
            Text(L10n("Snack around \(trainClock(start - 90)), refuel by \(trainClock(start + draft.durationMin + TrainMath.refuelWindowMin))."))
                .font(Typography.data(12, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.haze.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.hazeSoft.opacity(0.30)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Training settings

struct TrainSettingsSheet: View {
    let addCalories: Bool
    let nudgeMin: Int
    let healthOn: Bool
    let baseKcal: Int
    /// What today's training adds, whatever the switch says; 0 on a rest day.
    let todayTrainingKcal: Int
    let onAddCalories: (Bool) -> Void
    let onNudge: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Headline("Training settings", size: 28)

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(get: { addCalories }, set: onAddCalories)) {
                    Text("Add calories on training days")
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(Palette.ink)
                }
                .tint(Palette.haze)
                HStack(spacing: 10) {
                    Text("Today").foregroundStyle(Palette.inkSoft)
                    Text(baseKcal.formatted()).font(Typography.mono(13)).foregroundStyle(Palette.ink)
                    Image(systemName: "arrow.forward").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                    Text(todayTarget.formatted())
                        .font(Typography.mono(13))
                        .foregroundStyle(addCalories && todayTrainingKcal > 0 ? Palette.amber : Palette.ink)
                        .contentTransition(.numericText())
                    Spacer(minLength: 4)
                    Text(todayNote).foregroundStyle(Palette.inkSoft)
                }
                .font(Typography.data(13, weight: .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .animation(Motion.settle, value: addCalories)
            }
            .padding(16)
            .glass(radius: 20, fill: Color.white.opacity(0.04), stroke: Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 10) {
                Text("Nudge me before a session if I haven’t eaten")
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.ink)
                SegmentedPills(
                    options: [0, 60, 90, 120],
                    selection: Binding(get: { nudgeMin }, set: onNudge),
                    title: { $0 == 0 ? L10n("Off") : $0 == 120 ? L10n("2 h") : L10n("\($0) min") }
                )
            }
            .padding(16)
            .glass(radius: 20, fill: Color.white.opacity(0.04), stroke: Color.white.opacity(0.08))

            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(hex: 0xFF375F))
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Health workouts")
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(Palette.ink)
                    Text(LocalizedStringKey(healthOn ? "Sessions you record come in by themselves" : "Turn it on in You to bring workouts in"))
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.inkFaint)
                }
                Spacer(minLength: 8)
                Text(LocalizedStringKey(healthOn ? "On" : "Off"))
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(healthOn ? Palette.positive : Palette.inkSoft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glass(radius: 20, fill: Color.white.opacity(0.04), stroke: Color.white.opacity(0.08))
        }
        .padding(Space.gutter)
        .padding(.top, Space.sm)
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheet)
        .presentationCornerRadius(32)
    }

    private var todayTarget: Int {
        TrainMath.target(base: baseKcal, bump: todayTrainingKcal, addCalories: addCalories)
    }

    private var todayNote: String {
        guard todayTrainingKcal > 0 else { return L10n( "rest day today") }
        return addCalories ? L10n( "+\(todayTrainingKcal) for training") : L10n( "same as a rest day")
    }
}

/// The suggested pre-session plate — items, not just a name.
struct TrainSnackSheet: View {
    let snack: TrainingWeekResponse.SnackBefore
    var logging = false
    var logged = false
    var onLog: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Snack before").sectionLabelStyle()
            Text(FoodText.name(snack.name))
                .font(Typography.display(28))
                .tracking(-0.6)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(reason)
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                metric("\(snack.kcal)", L10n("kcal"))
                if let protein = snack.proteinG, protein > 0 {
                    metric("\(Int(protein.rounded()))g", L10n("protein"))
                }
            }

            if let items = snack.items, !items.isEmpty {
                GlassList {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { ListDivider() }
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(FoodText.name(item.name))
                                    .font(Typography.data(15, weight: .regular))
                                    .foregroundStyle(Palette.ink)
                                if let quantity = item.quantity, !quantity.isEmpty {
                                    Text(FoodText.serving(quantity))
                                        .font(Typography.data(12, weight: .regular))
                                        .foregroundStyle(Palette.inkFaint)
                                }
                            }
                            Spacer(minLength: 8)
                            Text("\(item.kcal)")
                                .font(Typography.mono(13))
                                .foregroundStyle(Palette.inkSoft)
                        }
                        .padding(.vertical, 12)
                    }
                }
            }

            Spacer(minLength: 8)

            if let onLog {
                ActionButton(
                    title: "Log it",
                    busy: logging,
                    busyTitle: "Logging…",
                    done: logged,
                    doneTitle: "Logged",
                    symbol: "plus"
                ) {
                    dismiss()
                    onLog()
                }
                .disabled(logging || logged)
            }
        }
        .padding(Space.gutter)
        .padding(.top, Space.sm)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheet)
        .presentationCornerRadius(32)
    }

    private var reason: String {
        switch snack.source {
        case "history": return L10n("You’ve had this before a session.")
        case "usual": return L10n("One of your plates.")
        default: return L10n("Light, and it fits what you eat.")
        }
    }

    private func metric(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Typography.mono(18))
                .foregroundStyle(Palette.ink)
            Text(LocalizedStringKey(caption))
                .font(Typography.data(12, weight: .regular))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private extension Date {
    var isAfterNow: Bool { self > .now }
}

/// Lays chips out in rows, wrapping to the next row when one is full.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
