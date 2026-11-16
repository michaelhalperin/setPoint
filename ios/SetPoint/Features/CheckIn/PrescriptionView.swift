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
    /// Open on the drink plate (the takeover's "Drink it instead").
    var startOnDrink = false

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
    @State private var swapping: HomeResponse.ActiveCheckIn.Prescription.Item?

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
        previewVariants: VariantsPayload? = nil,
        startOnDrink: Bool = false
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
        self.startOnDrink = startOnDrink
        let preferSmaller = startOnDrink || suggestSmallerDefault || appetiteLevel == "LOW" || checkIn.variant == "smaller"
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
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Palette.inkFaint.opacity(0.4))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)

            HStack {
                Text(sheetLabel)
                    .sectionLabelStyle(Palette.ember)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.06), in: Circle())
                        .frame(width: 44, height: 44)
                }
                .padding(.trailing, -10)
                .accessibilityLabel("Close")
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Headline(headline, tail: nil, size: 38)
                if let whyNow {
                    Text(whyNow)
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            .padding(.top, 4)

            if checkIn.prescription != nil {
                modeCards.padding(.top, 22)
                foodList.padding(.top, 14)
                Spacer(minLength: 12)
                primaryActions
            } else if let message = checkIn.message {
                Text(LocalizedStringKey(message))
                    .font(Typography.voice(20))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 18)
                ActionButton(title: "I already ate", kind: .secondary) { run(alreadyAte, then: onAlreadyAte) }
                    .padding(.top, 12)
                Spacer(minLength: 0)
            }

            if let error {
                Text(LocalizedStringKey(error))
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.amber)
                    .padding(.top, 8)
            }

            HStack(spacing: 2) {
                Spacer()
                Text("Right time?")
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkFaint)
                feedbackButton(systemName: "hand.thumbsup", positive: true)
                feedbackButton(systemName: "hand.thumbsdown", positive: false)
                Spacer()
            }
            .padding(.top, 2)
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
        .sheet(item: $swapping) { item in
            SwapFoodSheet(checkInID: checkIn.id, item: item, preview: previewVariants != nil) { rx in
                if notHungry { smallerPlate = rx } else { fullPlate = rx }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.sheet)
            .presentationCornerRadius(32)
        }
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

    private var sheetLabel: String {
        if let slot = checkIn.slot { return L10n("Check-in · \(TodayCopy.slotTitle(slot))") }
        return L10n("Check-in")
    }

    /// Eat it or drink it: two compact cards, the chosen one lit.
    private var modeCards: some View {
        HStack(spacing: 10) {
            modeCard(smaller: false, plate: fullPlate)
            modeCard(smaller: true, plate: smallerPlate)
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: notHungry)
    }

    private func modeCard(smaller: Bool, plate: HomeResponse.ActiveCheckIn.Prescription?) -> some View {
        let on = notHungry == smaller
        return Button { select(notHungry: smaller) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: smaller ? "cup.and.saucer" : "fork.knife")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(on ? Palette.amber : Palette.inkSoft)
                    Spacer(minLength: 4)
                    Text(L10n("\(smaller ? 2 : 15) min"))
                        .font(Typography.mono(10))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(on ? Palette.amber : Palette.inkFaint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(smaller ? "Drink" : "Eat"))
                        .font(Typography.data(16, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    if let plate {
                        Text(L10n("\(plate.totalKcal.formatted()) kcal · \(Int(plate.totalProteinG.rounded())) g"))
                            .font(Typography.data(12, weight: .regular))
                            .foregroundStyle(on ? Palette.ink.opacity(0.8) : Palette.inkFaint)
                    } else {
                        Text(" ").font(Typography.data(12))
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(on
                          ? AnyShapeStyle(LinearGradient(colors: [Palette.ember.opacity(0.14), Palette.ember.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(0.03)))
            }
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(on ? Color(hex: 0xFF8A50, opacity: 0.6) : Color.white.opacity(0.08)))
            .shadow(color: Palette.ember.opacity(on ? 0.16 : 0), radius: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel((smaller ? L10n("Drink") : L10n("Eat")) + (plate.map { L10n(", \($0.totalKcal) calories") } ?? ""))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// What's in the chosen plate; each food can be swapped for another of the same kind.
    private var foodList: some View {
        VStack(spacing: 0) {
            if let plate = activePrescription {
                ForEach(plate.items) { item in
                    HStack(spacing: 12) {
                        Text(foodLine(item))
                            .font(Typography.data(16, weight: .regular))
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 8)
                        Text("\(item.kcal)")
                            .font(Typography.mono(13))
                            .foregroundStyle(Palette.inkSoft)
                        Button {
                            Haptics.select()
                            swapping = item
                        } label: {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Palette.inkSoft)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.06), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        .accessibilityLabel(L10n("Swap \(FoodText.name(item.name))"))
                    }
                    .frame(minHeight: 56)
                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
                }
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .id(notHungry)
        .transition(.opacity)
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: notHungry)
    }

    private func foodLine(_ item: HomeResponse.ActiveCheckIn.Prescription.Item) -> String {
        let name = FoodText.name(item.name)
        guard item.quantity != 1 else { return name }
        return "\(item.quantity.formatted(.number.precision(.fractionLength(0 ... 1))))× \(name)"
    }

    private var primaryActions: some View {
        VStack(spacing: 4) {
            ActionButton(title: primaryTitle, busy: busy, busyTitle: "Logging") {
                run(eatThis)
            }
            HStack(spacing: 0) {
                textAction("Snooze") { choosingSnooze = true }
                textAction("I already ate") { run(alreadyAte, then: onAlreadyAte) }
            }
            .disabled(busy)
        }
    }

    private func textAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(Typography.data(15, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

/// Swap one food on the plate for another of the same kind (a drink for a drink), each sized to
/// roughly the same calories, with what the swap does to the total.
struct SwapFoodSheet: View {
    let checkInID: String
    let item: HomeResponse.ActiveCheckIn.Prescription.Item
    var preview = false
    let onSwapped: (HomeResponse.ActiveCheckIn.Prescription) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var alternatives: [Alternative] = []
    @State private var loading = true
    @State private var error: String?
    @State private var swappingSlug: String?

    struct Alternative: Decodable, Identifiable {
        let slug: String
        let name: String
        let servingDesc: String
        let quantity: Double
        let kcal: Int
        let proteinG: Double
        let deltaKcal: Int
        var id: String { slug }
    }

    private struct ListReply: Decodable { let alternatives: [Alternative] }
    private struct SwapBody: Encodable { let item: String; let slug: String }
    private struct SwapReply: Decodable { let prescription: HomeResponse.ActiveCheckIn.Prescription }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n("Swap · \(FoodText.name(item.name))")).sectionLabelStyle(Palette.amber)
                Text("Something else.")
                    .font(Typography.display(28))
                    .tracking(-0.9)
                    .foregroundStyle(Palette.ink)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, 22)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 0) {
                    currentRow
                    if loading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                    }
                    ForEach(alternatives) { alt in
                        Button { Task { await swap(to: alt) } } label: { row(alt) }
                            .buttonStyle(.plain)
                            .disabled(swappingSlug != nil)
                    }
                    if let error {
                        Text(LocalizedStringKey(error))
                            .font(Typography.data(13)).foregroundStyle(Palette.amber)
                            .padding(.top, 12)
                    } else if !loading, alternatives.isEmpty {
                        Text("Nothing else fits here.")
                            .font(Typography.data(14)).foregroundStyle(Palette.inkSoft)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.lg)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .task { await load() }
    }

    private var currentRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.onBone)
                .frame(width: 30, height: 30)
                .background(Palette.ink, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(FoodText.name(item.name)).font(Typography.data(15, weight: .regular)).foregroundStyle(Palette.ink)
                Text("On your plate now").font(Typography.data(12)).foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 8)
            Text("\(item.kcal)").font(Typography.mono(12)).foregroundStyle(Palette.ink)
            Color.clear.frame(width: 40)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 60)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func row(_ alt: Alternative) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().strokeBorder(Color.white.opacity(0.14))
                if swappingSlug == alt.slug { ProgressView().controlSize(.small) }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(FoodText.name(alt.name)).font(Typography.data(15, weight: .regular)).foregroundStyle(Palette.ink)
                Text(L10n("\(FoodText.serving(alt.servingDesc)) · \(Int(alt.proteinG.rounded())) g protein"))
                    .font(Typography.data(12)).foregroundStyle(Palette.inkFaint).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(alt.kcal)").font(Typography.mono(12)).foregroundStyle(Palette.inkSoft)
            Text(delta(alt.deltaKcal))
                .font(Typography.mono(11))
                .foregroundStyle(alt.deltaKcal > 0 ? Color(hex: 0x86EFAC) : Palette.inkFaint)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 60)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
        .contentShape(Rectangle())
    }

    private func delta(_ d: Int) -> String {
        d == 0 ? "=" : d > 0 ? "+\(d)" : "−\(abs(d))"
    }

    private func load() async {
        if preview {
            alternatives = [
                Alternative(slug: "whole-milk", name: "Whole milk", servingDesc: "1 glass", quantity: 1, kcal: 150, proteinG: 8, deltaKcal: -60),
                Alternative(slug: "kefir", name: "Kefir", servingDesc: "1 glass", quantity: 1, kcal: 110, proteinG: 9, deltaKcal: -100),
                Alternative(slug: "fruit-smoothie", name: "Fruit smoothie", servingDesc: "1 glass", quantity: 1, kcal: 240, proteinG: 4, deltaKcal: 30),
            ]
            loading = false
            return
        }
        do {
            let reply: ListReply = try await env.api.get("/api/checkins/\(checkInID)/alternatives", query: ["item": item.name])
            alternatives = reply.alternatives
        } catch {
            self.error = UserFacingError.message(for: error, fallback: L10n("Couldn’t load other foods. Try again."))
        }
        loading = false
    }

    private func swap(to alt: Alternative) async {
        guard swappingSlug == nil else { return }
        swappingSlug = alt.slug
        error = nil
        defer { swappingSlug = nil }
        if preview { dismiss(); return }
        do {
            let reply: SwapReply = try await env.api.post("/api/checkins/\(checkInID)/swap", SwapBody(item: item.name, slug: alt.slug))
            Haptics.landed()
            onSwapped(reply.prescription)
            dismiss()
        } catch {
            self.error = UserFacingError.message(for: error, fallback: L10n("Couldn’t swap that. Try again."))
        }
    }
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
