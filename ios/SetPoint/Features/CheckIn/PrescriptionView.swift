import SwiftUI

/// The full check-in sheet: Full plate | Not hungry, both prescriptions as
/// cards, then "I'll have {first item}" with snooze / already-ate underneath.
struct PrescriptionView: View {
    let checkIn: HomeResponse.ActiveCheckIn
    /// "Lunch slipped."
    var headline = "Time to eat."
    /// "Usually 13:00 · nothing since 8:05"
    var whyNow: String?
    /// Minutes until the user's next meal time — feeds the snooze sheet choices.
    var nextMealMinutes: Int? = nil
    /// Close without answering.
    let onDismiss: () -> Void
    /// Answered (logged, dismissed, or snoozed) — reload Today, then close.
    let onResolved: () -> Void
    /// "I already ate": closed without a log — offer a quick one.
    let onAlreadyAte: () -> Void
    var suggestSmallerDefault = false
    /// Today's appetite level — LOW also opens on "Not hungry".
    var appetiteLevel: String? = nil
    /// Preview both plates without hitting the network (uiStub).
    var previewVariants: VariantsPayload? = nil

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var busy = false
    @State private var error: String?
    @State private var rated: Bool?
    @State private var drag: CGFloat = 0
    @State private var choosingSnooze = false
    @State private var notHungry: Bool
    @State private var fullPlate: HomeResponse.ActiveCheckIn.Prescription?
    @State private var smallerPlate: HomeResponse.ActiveCheckIn.Prescription?
    @State private var loaded = false

    init(
        checkIn: HomeResponse.ActiveCheckIn,
        headline: String = "Time to eat.",
        whyNow: String? = nil,
        nextMealMinutes: Int? = nil,
        onDismiss: @escaping () -> Void,
        onResolved: @escaping () -> Void,
        onAlreadyAte: @escaping () -> Void,
        suggestSmallerDefault: Bool = false,
        appetiteLevel: String? = nil,
        previewVariants: VariantsPayload? = nil
    ) {
        self.checkIn = checkIn
        self.headline = headline
        self.whyNow = whyNow
        self.nextMealMinutes = nextMealMinutes
        self.onDismiss = onDismiss
        self.onResolved = onResolved
        self.onAlreadyAte = onAlreadyAte
        self.suggestSmallerDefault = suggestSmallerDefault
        self.appetiteLevel = appetiteLevel
        self.previewVariants = previewVariants
        let preferSmaller = suggestSmallerDefault || appetiteLevel == "LOW" || checkIn.variant == "smaller"
        _notHungry = State(initialValue: preferSmaller)
        if let preview = previewVariants {
            _fullPlate = State(initialValue: preview.full)
            _smallerPlate = State(initialValue: preview.smaller)
            _loaded = State(initialValue: true)
        } else if let rx = checkIn.prescription {
            _fullPlate = State(initialValue: preferSmaller ? nil : rx)
            _smallerPlate = State(initialValue: preferSmaller ? rx : nil)
        }
    }

    struct VariantsPayload {
        var full: HomeResponse.ActiveCheckIn.Prescription
        var smaller: HomeResponse.ActiveCheckIn.Prescription
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Capsule()
                .fill(Palette.inkFaint.opacity(0.4))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)

            HStack {
                Text("Check-in")
                    .sectionLabelStyle(Palette.ember)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .accessibilityLabel("Close")
            }

            Text(headline)
                .font(Typography.display(40))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)

            if let whyNow {
                Label(whyNow, systemImage: "clock")
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }

            if checkIn.prescription != nil {
                sizeControl
                plateCards
                primaryActions
            } else if let message = checkIn.message {
                Text(message)
                    .font(Typography.voice(20))
                    .foregroundStyle(Palette.ink)
                ActionButton(title: "I already ate", kind: .secondary) { run(alreadyAte, then: onAlreadyAte) }
            }

            if let error {
                Text(error)
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.amber)
            }

            Spacer(minLength: 0)

            HStack(spacing: Space.sm) {
                Text("Right time?")
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
                Spacer()
                feedbackButton(systemName: "hand.thumbsup", positive: true)
                feedbackButton(systemName: "hand.thumbsdown", positive: false)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
        .padding(.bottom, Space.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                .fill(Palette.background)
                .shadow(color: Palette.ink.opacity(0.12), radius: 20, y: -6)
                .ignoresSafeArea(edges: .bottom)
        }
        .padding(.top, Space.xl)
        .offset(y: drag)
        .gesture(dismissDrag)
        .task { await loadVariants() }
        .sheet(isPresented: $choosingSnooze) {
            let choices = CheckInActions.snoozeChoices(nextMealMinutes: nextMealMinutes)
            SnoozeSheet(choices: choices) { minutes in
                run { try await snooze(minutes) }
            }
            .presentationDetents([.height(SnoozeSheet.height(for: choices.count))])
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.sheet)
            .presentationCornerRadius(32)
        }
    }

    private var sizeControl: some View {
        HStack(spacing: 0) {
            segment("Full plate", selected: !notHungry) { select(notHungry: false) }
            segment("Not hungry", selected: notHungry) { select(notHungry: true) }
        }
        .padding(4)
        .glassCapsule(fill: Color.white.opacity(0.05), stroke: Color.white.opacity(0.08))
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typography.data(14, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Palette.onBone : Palette.inkSoft)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background {
                    if selected {
                        Capsule().fill(Palette.ink)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    @ViewBuilder
    private var plateCards: some View {
        let chosen = notHungry ? smallerPlate : fullPlate
        let other = notHungry ? fullPlate : smallerPlate
        VStack(spacing: 10) {
            if let chosen {
                plateCard(
                    label: notHungry ? "EASIER TO GET DOWN" : "FULL PLATE",
                    prescription: chosen,
                    emphasized: true
                )
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            }
            if let other {
                plateCard(
                    label: notHungry ? "FULL PLATE" : "EASIER TO GET DOWN",
                    prescription: other,
                    emphasized: false
                )
            }
        }
    }

    private func plateCard(
        label: String,
        prescription: HomeResponse.ActiveCheckIn.Prescription,
        emphasized: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label)
                    .sectionLabelStyle(emphasized ? Palette.amber : Palette.inkFaint)
                Spacer()
                Text("\(prescription.totalKcal.formatted()) kcal")
                    .font(Typography.mono(13))
                    .foregroundStyle(Palette.ink)
            }
            ForEach(prescription.items) { item in
                HStack(spacing: 10) {
                    Text(item.quantity > 1 ? "\(Int(item.quantity))× \(item.name)" : item.name)
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    Text("\(item.kcal)")
                        .font(Typography.mono(13))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
        }
        .padding(16)
        .glass(
            radius: 22,
            fill: emphasized ? Palette.ember.opacity(0.07) : Palette.glass,
            stroke: emphasized ? Palette.amber.opacity(0.45) : Palette.hairline
        )
    }

    private var primaryActions: some View {
        VStack(spacing: Space.sm) {
            ActionButton(title: primaryTitle, busy: busy, busyTitle: "Logging") {
                run(eatThis)
            }
            HStack(spacing: 10) {
                secondaryAction(title: "Snooze", symbol: "zzz") {
                    choosingSnooze = true
                }
                secondaryAction(title: "I already ate") {
                    run(alreadyAte, then: onAlreadyAte)
                }
            }
            .disabled(busy)
        }
    }

    private func secondaryAction(title: String, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(Typography.data(15, weight: .bold))
            }
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(PressableCard())
    }

    /// Logs the whole plate, so the button names the plate, not its first item.
    private var primaryTitle: String {
        guard let plate = notHungry ? smallerPlate : fullPlate else { return "I’ll have this" }
        return "I’ll have this · \(plate.totalKcal) kcal"
    }

    private var activePrescription: HomeResponse.ActiveCheckIn.Prescription? {
        notHungry ? smallerPlate : fullPlate
    }

    private func select(notHungry next: Bool) {
        guard next != notHungry else { return }
        notHungry = next
        Task { await persistVariant(next ? "smaller" : "full") }
    }

    private func feedbackButton(systemName: String, positive: Bool) -> some View {
        Button {
            Task { await rate(positive) }
        } label: {
            Image(systemName: rated == positive ? "\(systemName).fill" : systemName)
                .font(.system(size: 18))
                .foregroundStyle(rated == positive ? Palette.ember : Palette.inkSoft)
                .frame(width: 44, height: 44)
        }
        .disabled(rated != nil)
        .accessibilityLabel(positive ? "Good timing" : "Bad timing")
    }

    // MARK: Networking

    private func run(_ work: @escaping () async throws -> Void, then done: (() -> Void)? = nil) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            do {
                try await work()
                (done ?? onResolved)()
            } catch {
                self.error = UserFacingError.message(for: error, fallback: "Couldn't do that. Try again.")
            }
            busy = false
        }
    }

    private func loadVariants() async {
        if previewVariants != nil {
            loaded = true
            return
        }
        struct Reply: Decodable {
            let full: HomeResponse.ActiveCheckIn.Prescription
            let smaller: HomeResponse.ActiveCheckIn.Prescription
        }
        do {
            let reply: Reply = try await env.api.get("/api/checkins/\(checkIn.id)/variants")
            fullPlate = reply.full
            smallerPlate = reply.smaller
            loaded = true
            let want = notHungry ? "smaller" : "full"
            if checkIn.variant != want {
                await persistVariant(want)
            }
        } catch {
            loaded = true
            self.error = UserFacingError.message(for: error, fallback: "Couldn’t load the other plate. The one above still works.")
        }
    }

    private func persistVariant(_ variant: String) async {
        if previewVariants != nil { return }
        struct Body: Encodable { let variant: String }
        struct Reply: Decodable {
            let variant: String
            let prescription: HomeResponse.ActiveCheckIn.Prescription
        }
        do {
            let reply: Reply = try await env.api.post("/api/checkins/\(checkIn.id)/variant", Body(variant: variant))
            if reply.variant == "smaller" {
                smallerPlate = reply.prescription
            } else {
                fullPlate = reply.prescription
            }
        } catch {
            self.error = UserFacingError.message(for: error, fallback: "Couldn’t switch plates. Try again.")
        }
    }

    private func eatThis() async throws {
        guard let rx = activePrescription else { return }
        try await CheckInActions.eat(prescriptionID: rx.id, api: env.api)
        Haptics.landed()
        env.changes.mealsChanged()
    }

    private func alreadyAte() async throws {
        try await CheckInActions.alreadyAte(checkInID: checkIn.id, api: env.api)
    }

    private func snooze(_ minutes: Int) async throws {
        try await CheckInActions.snooze(checkInID: checkIn.id, minutes: minutes, api: env.api)
    }

    private func rate(_ positive: Bool) async {
        rated = positive
        try? await env.api.post("/api/checkins/\(checkIn.id)/feedback", FeedbackBody(positive: positive))
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let y = value.translation.height
                drag = y > 0 ? y : y * 0.12
            }
            .onEnded { value in
                if value.translation.height > 110 || value.predictedEndTranslation.height > 260 {
                    onDismiss()
                } else {
                    withAnimation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion)) { drag = 0 }
                }
            }
    }
}

private struct FeedbackBody: Encodable {
    let positive: Bool
}
