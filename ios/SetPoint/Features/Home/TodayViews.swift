import SwiftUI

// Today's lower blocks: the meal log and the log dock. The hero (the day dial,
// or the check-in takeover) lives in TodayHero.swift; HomeContent composes them.

// MARK: - Meal log

/// Today's meals under their usual meal times. Only times that have food — or
/// that passed with nothing logged — get a section; upcoming ones live on the
/// dial. Quiet mode never points at a missed meal.
struct MealLog: View {
    let home: HomeResponse
    let pending: TodayPending?
    var landingNamespace: Namespace.ID?
    var landingCardID: String?
    let onOpenMeal: (MealSummary) -> Void
    let onLogMissed: (HomeResponse.Day.Slot) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion), value: home.meals.map(\.id))
            .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: pending)
    }

    @ViewBuilder
    private var content: some View {
        if let day = home.day {
            let pendingSlotID = pending == nil ? nil : pendingSlot(in: day)
            let sections = day.slots.filter { slot in
                slot.slotState == .logged
                    || (slot.slotState == .missed && home.enforcementEnabled)
                    || slot.id == pendingSlotID
            }
            if sections.isEmpty {
                emptyHint
            } else {
                VStack(alignment: .leading, spacing: Space.md) {
                    ForEach(sections) { slot in
                        section(slot, holdsPending: slot.id == pendingSlotID)
                    }
                }
            }
        } else {
            flatList
        }
    }

    /// Where a meal being logged right now shows up: the slot that's due, else
    /// the latest one with food.
    private func pendingSlot(in day: HomeResponse.Day) -> String? {
        day.slots.first { $0.slotState == .now }?.id
            ?? day.slots.last { $0.slotState == .logged }?.id
            ?? day.slots.last?.id
    }

    private func section(_ slot: HomeResponse.Day.Slot, holdsPending: Bool) -> some View {
        let meals = TodayLayout.meals(in: slot, from: home.meals)
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(slot.meal.title) · \(formatMinutes(slot.atMin))")
                    .sectionLabelStyle()
                Spacer()
                if slot.kcal > 0 {
                    Text("\(slot.kcal.formatted()) kcal")
                        .font(Typography.data(11, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .monospacedDigit()
                }
            }

            ForEach(meals) { meal in
                Button {
                    onOpenMeal(meal)
                } label: {
                    TodayMealRow(meal: meal)
                }
                .buttonStyle(PressableCard())
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            if holdsPending, let pending {
                pendingRow(pending)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if slot.slotState == .missed, meals.isEmpty, !holdsPending {
                missedRow(slot)
            }
        }
    }

    private var flatList: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if !home.meals.isEmpty || pending != nil {
                Text("Meals").sectionLabelStyle()
            }
            ForEach(home.meals) { meal in
                Button {
                    onOpenMeal(meal)
                } label: {
                    TodayMealRow(meal: meal)
                }
                .buttonStyle(PressableCard())
            }
            if let pending {
                pendingRow(pending)
            }
            if home.meals.isEmpty, pending == nil {
                emptyHint
            }
        }
    }

    private var emptyHint: some View {
        Text("Meals you log land here, under their meal time.")
            .font(Typography.data(13))
            .foregroundStyle(Palette.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func pendingRow(_ pending: TodayPending) -> some View {
        switch pending {
        case let .parsing(title):
            TodayMealRow(title: title, detail: "Working it out…", kcal: 640, redacted: true)
                .shimmering(true)
        case let .logged(title, kcal):
            landing(TodayMealRow(title: title, detail: "Just now", kcal: kcal))
        }
    }

    @ViewBuilder
    private func landing<Content: View>(_ content: Content) -> some View {
        if let landingCardID, let landingNamespace {
            content.matchedGeometryEffect(id: landingCardID, in: landingNamespace)
        } else {
            content
        }
    }

    private func missedRow(_ slot: HomeResponse.Day.Slot) -> some View {
        HStack(spacing: Space.sm) {
            Text("Nothing logged")
                .font(Typography.voice(16))
                .foregroundStyle(Palette.inkSoft)
            Spacer(minLength: Space.xs)
            Button {
                onLogMissed(slot)
            } label: {
                Label("Add \(slot.meal.title.lowercased())", systemImage: "plus")
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.accentDeep)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Palette.accentTint, in: Capsule())
            }
            .buttonStyle(PressableCard())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.inkFaint.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }
}

/// A logged meal on Today: optional photo, name, time, kcal.
struct TodayMealRow: View {
    let title: String
    let detail: String
    let kcal: Int
    let meal: MealSummary?
    let redacted: Bool

    @State private var photo: UIImage?

    init(meal: MealSummary) {
        title = meal.title
        detail = MealFormat.time(meal.loggedAt)
        kcal = meal.kcal
        self.meal = meal
        redacted = false
    }

    init(title: String, detail: String, kcal: Int, redacted: Bool = false) {
        self.title = title
        self.detail = detail
        self.kcal = kcal
        meal = nil
        self.redacted = redacted
    }

    var body: some View {
        HStack(spacing: Space.sm) {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .transition(.opacity)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.data(16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if !detail.isEmpty {
                    Text(detail)
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            Spacer(minLength: 8)
            Text("\(kcal) kcal")
                .font(Typography.data(14, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(kcal)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.hairline)
        )
        .elevation(.resting)
        .redacted(reason: redacted ? .placeholder : [])
        .task(id: meal?.photoUrl) {
            guard let meal else { return }
            photo = await MealPhotoCache.shared.image(for: meal)
        }
    }
}

// MARK: - Log dock

/// Logging, always in the same place: pinned above the tab bar and rising with
/// the keyboard. It shows what's being worked out and, when filling in a
/// missed meal time, which one.
struct LogDock: View {
    @Bindable var logger: LogMealViewModel
    var focused: FocusState<Bool>.Binding
    let photoNamespace: Namespace.ID
    let photoGeometryID: String
    let onSubmit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            status

            if showsRecents {
                recentsRow
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            SearchComposer(
                model: logger,
                focused: focused,
                onSubmit: onSubmit,
                photoNamespace: photoNamespace,
                photoGeometryID: photoGeometryID,
                prompt: prompt
            )
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Palette.background.opacity(0.84))
                .overlay(alignment: .top) {
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: logger.phase)
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: logger.backdate)
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: showsRecents)
    }

    /// "Again?" — recent meals as one-tap chips while the field is open and empty.
    private var showsRecents: Bool {
        focused.wrappedValue && logger.phase == .compose && logger.text.isEmpty
            && logger.photo == nil && !logger.recents.isEmpty
    }

    private var recentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Again?")
                    .sectionLabelStyle()
                ForEach(logger.recents) { meal in
                    Button {
                        focused.wrappedValue = false
                        Task { await logger.logAgain(meal) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(meal.summary ?? "")
                                .lineLimit(1)
                            Text("\(meal.kcal)")
                                .foregroundStyle(Palette.inkFaint)
                                .monospacedDigit()
                        }
                        .font(Typography.data(14, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Palette.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Palette.hairline))
                    }
                    .buttonStyle(PressableCard())
                    .accessibilityLabel("Log \(meal.summary ?? "this") again, \(meal.kcal) calories")
                }
            }
        }
        .scrollClipDisabled()
    }

    private var prompt: String {
        if let backdate = logger.backdate {
            return "What was \(backdate.slot.title.lowercased())?"
        }
        return "What did you eat?"
    }

    @ViewBuilder
    private var status: some View {
        switch logger.phase {
        case .parsing:
            statusLine(
                symbol: nil,
                text: logger.submittedPrompt.isEmpty ? "Working it out…" : "Working out “\(logger.submittedPrompt)”…",
                working: true
            )
        case let .logged(logged) where !logger.confirmingPhoto:
            statusLine(
                symbol: "checkmark",
                text: "Logged · \(logged.kcal) kcal" + (logged.resolvedCheckIn ? " · check-in answered" : ""),
                working: false
            )
        default:
            if let backdate = logger.backdate {
                HStack(spacing: 6) {
                    Image(systemName: backdate.slot.symbol)
                    Text("Adding to \(backdate.slot.title.lowercased()) · \(backdate.at.formatted(date: .omitted, time: .shortened))")
                    Button {
                        logger.backdate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.accentDeep.opacity(0.6))
                    }
                    .accessibilityLabel("Log it for now instead")
                }
                .font(Typography.data(12, weight: .semibold))
                .foregroundStyle(Palette.accentDeep)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Palette.accentTint, in: Capsule())
                .transition(.opacity)
            }
        }
    }

    private func statusLine(symbol: String?, text: String, working: Bool) -> some View {
        HStack(spacing: 8) {
            if working {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Palette.accent)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.dayOnTrack)
            }
            Text(text)
                .font(Typography.data(13, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .transition(.opacity)
    }
}
