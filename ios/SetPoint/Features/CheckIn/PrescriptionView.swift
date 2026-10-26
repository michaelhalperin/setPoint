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

            Headline(headline, tail: notHungry ? "Two ways to get it in." : nil, size: 40)

            if let whyNow {
                Label(whyNow, systemImage: "clock")
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }

            if checkIn.prescription != nil {
                plateTiles
                Spacer(minLength: 0)
                primaryActions
            } else if let message = checkIn.message {
                Text(LocalizedStringKey(message))
                    .font(Typography.voice(20))
                    .foregroundStyle(Palette.ink)
                ActionButton(title: "I already ate", kind: .secondary) { run(alreadyAte, then: onAlreadyAte) }
            }

            if let error {
                Text(LocalizedStringKey(error))
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.amber)
            }

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
                .overlay(alignment: .top) {
                    AmbientGlow(tone: .ember, strength: 0.8, height: 360)
                        .offset(y: -120)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous))
                }
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

    /// The two plates side by side as pictures: a full plate to chew, or a glass and
    /// a banana to drink. The chosen one lights; its foods sit underneath.
    private var plateTiles: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                plateTile(smaller: false, plate: fullPlate)
                plateTile(smaller: true, plate: smallerPlate)
            }
            .fixedSize(horizontal: false, vertical: true)
            if let plate = activePrescription {
                FlexWrap(spacing: 8, lineSpacing: 8) {
                    ForEach(plate.items) { item in
                        HStack(spacing: 8) {
                            Text(item.quantity > 1 ? "\(Int(item.quantity))× \(FoodText.name(item.name))" : FoodText.name(item.name))
                                .font(Typography.data(13, weight: .regular))
                                .foregroundStyle(Palette.ink)
                            Text("\(item.kcal)")
                                .font(Typography.mono(11))
                                .foregroundStyle(Palette.amber)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .glassCapsule()
                    }
                }
                .frame(maxWidth: .infinity)
                .id(notHungry)
                .transition(.opacity)
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity, minHeight: 40)
            }
        }
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: notHungry)
    }

    private func plateTile(smaller: Bool, plate: HomeResponse.ActiveCheckIn.Prescription?) -> some View {
        let on = notHungry == smaller
        return Button { select(notHungry: smaller) } label: {
            VStack(spacing: 4) {
                Group {
                    if smaller { DrinkPicture() } else { PlatePicture() }
                }
                .frame(height: 150)
                Text(smaller ? "Drink · 2 min" : "Chew · 15 min")
                    .sectionLabelStyle(on ? Palette.amber : Palette.inkFaint)
                Text(smaller ? "Easier to get down" : "Full plate")
                    .font(Typography.data(16, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                if let plate {
                    Text("\(plate.totalKcal.formatted()) kcal")
                        .font(Typography.mono(12))
                        .foregroundStyle(Palette.inkSoft)
                    Text("\(Int(plate.totalProteinG.rounded())) g protein")
                        .font(Typography.data(11, weight: .regular))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(on
                          ? AnyShapeStyle(LinearGradient(colors: [Palette.ember.opacity(0.13), Palette.ember.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(0.02)))
            }
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(on ? Color(hex: 0xFF8A50, opacity: 0.55) : Color.white.opacity(0.07)))
            .shadow(color: Palette.ember.opacity(on ? 0.16 : 0), radius: 20)
            .scaleEffect(on ? 1 : 0.94)
            .opacity(on ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel((smaller ? L10n("Easier to get down") : L10n("Full plate")) + (plate.map { L10n(", \($0.totalKcal) calories") } ?? ""))
        .accessibilityAddTraits(on ? .isSelected : [])
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
                Text(LocalizedStringKey(title))
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
        guard let plate = notHungry ? smallerPlate : fullPlate else { return L10n( "I’ll have this") }
        return L10n( "I’ll have this · \(plate.totalKcal) kcal")
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
        .accessibilityLabel(positive ? L10n("Good timing") : L10n("Bad timing"))
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
                self.error = UserFacingError.message(for: error, fallback: L10n( "Couldn't do that. Try again."))
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
            self.error = UserFacingError.message(for: error, fallback: L10n( "Couldn’t load the other plate. The one above still works."))
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
            self.error = UserFacingError.message(for: error, fallback: L10n( "Couldn’t switch plates. Try again."))
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

/// A full plate, drawn: rice, chicken and greens on a dark plate.
struct PlatePicture: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(stops: [
                    .init(color: Color(hex: 0x2A2723), location: 0.58), .init(color: Color(hex: 0x3A3631), location: 0.6),
                    .init(color: Color(hex: 0x3A3631), location: 0.66), .init(color: Color(hex: 0x1B1917), location: 0.68),
                ], center: .center, startRadius: 0, endRadius: 70))
                .frame(width: 140, height: 140)
                .shadow(color: .black.opacity(0.7), radius: 25, y: 18)
            blob(Color(hex: 0xE7D7B4), Color(hex: 0xB79B6A), w: 62, h: 52, x: -19, y: -22)
            blob(Color(hex: 0xD97A45), Color(hex: 0x8E3D1C), w: 58, h: 50, x: 25, y: -2)
            blob(Color(hex: 0x5E7A3E), Color(hex: 0x2F4420), w: 56, h: 34, x: -6, y: 31)
        }
        .accessibilityHidden(true)
    }

    private func blob(_ a: Color, _ b: Color, w: CGFloat, h: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Ellipse()
            .fill(RadialGradient(colors: [a, b], center: UnitPoint(x: 0.4, y: 0.4), startRadius: 0, endRadius: w * 0.6))
            .frame(width: w, height: h)
            .blur(radius: 1.2)
            .offset(x: x, y: y)
    }
}

/// The easier plate, drawn: a shake with a straw and a banana.
struct DrinkPicture: View {
    var body: some View {
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 18, bottomTrailingRadius: 18, topTrailingRadius: 10, style: .continuous)
                .fill(LinearGradient(stops: [
                    .init(color: .clear, location: 0), .init(color: .clear, location: 0.22),
                    .init(color: Color(hex: 0xFDE6CF), location: 0.22), .init(color: Palette.amber, location: 0.62), .init(color: Palette.emberDeep, location: 1),
                ], startPoint: .top, endPoint: .bottom))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 18, bottomTrailingRadius: 18, topTrailingRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1.5)
                )
                .frame(width: 52, height: 112)
                .shadow(color: Palette.ember.opacity(0.35), radius: 22)
                .offset(x: -20, y: 6)
            Capsule().fill(Palette.ink).frame(width: 4, height: 44)
                .rotationEffect(.degrees(14))
                .offset(x: -24, y: -48)
            UnevenRoundedRectangle(bottomLeadingRadius: 60, bottomTrailingRadius: 60, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFCD34D), Color(hex: 0xCA8A04)], startPoint: .top, endPoint: .bottom))
                .frame(width: 72, height: 26)
                .rotationEffect(.degrees(-18))
                .shadow(color: .black.opacity(0.4), radius: 9, y: 6)
                .offset(x: 30, y: 44)
        }
        .accessibilityHidden(true)
    }
}
