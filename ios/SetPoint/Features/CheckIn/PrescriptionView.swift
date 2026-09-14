import SwiftUI

/// The full check-in, rising as a sheet over a dimmed Today: what slipped, why
/// now, the suggested meal, and every answer on one screen — "I ate this",
/// "I already ate", or a snooze length. A drag down dismisses it.
struct PrescriptionView: View {
    let checkIn: HomeResponse.ActiveCheckIn
    /// "Lunch slipped."
    var headline = "Time to eat."
    /// "Usually 13:00 · nothing since 8:05"
    var whyNow: String?
    /// Minutes until the user's next meal time — powers the "After 19:00" snooze.
    var nextMealMinutes: Int? = nil
    /// Close without answering.
    let onDismiss: () -> Void
    /// Answered (logged, dismissed, or snoozed) — reload Today, then close.
    let onResolved: () -> Void
    /// "I already ate": closed without a log — offer a quick one.
    let onAlreadyAte: () -> Void
    var suggestSmallerDefault = false

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var busy = false
    @State private var error: String?
    @State private var rated: Bool?
    @State private var drag: CGFloat = 0
    @State private var variant = "full"
    @State private var shownPrescription: HomeResponse.ActiveCheckIn.Prescription?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Capsule()
                .fill(Palette.inkFaint.opacity(0.4))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)

            HStack {
                Text("Check-in")
                    .sectionLabelStyle(Palette.accent)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 34, height: 34)
                        .background(Palette.surfaceSunk, in: Circle())
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
                    .background(Palette.surfaceSunk, in: Capsule())
            }

            if let rx = checkIn.prescription {
                if checkIn.tier < 3 {
                    Picker("Size", selection: $variant) {
                        Text("Full meal · \(fullKcal)").tag("full")
                        Text("Smaller · \(smallerKcal) in 3 bites").tag("smaller")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: variant) { _, next in
                        Task { await swapVariant(next) }
                    }
                }
                if suggestSmallerDefault, variant == "full" {
                    Text("Make smaller your default?")
                        .font(Typography.data(13, weight: .semibold))
                        .foregroundStyle(Palette.accentDeep)
                }
                PrescriptionCard(prescription: shownPrescription ?? rx, roomy: true)
            } else if let message = checkIn.message {
                Text(message)
                    .font(Typography.voice(20))
                    .foregroundStyle(Palette.ink)
            }

            VStack(spacing: Space.xs) {
                if checkIn.prescription != nil {
                    ActionButton(title: "I ate this", busy: busy, busyTitle: "Logging") { run(eatThis) }
                }
                ActionButton(title: "I already ate", kind: .secondary) { run(alreadyAte, then: onAlreadyAte) }
            }
            .disabled(busy)

            HStack(spacing: 8) {
                Text("Later")
                    .font(Typography.data(13, weight: .bold))
                    .foregroundStyle(Palette.inkFaint)
                ForEach(CheckInActions.snoozeChoices(nextMealMinutes: nextMealMinutes)) { choice in
                    Button { run { try await snooze(choice.minutes) } } label: {
                        Text(choice.title)
                            .font(Typography.data(14, weight: .bold))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Palette.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.hairline))
                    }
                    .buttonStyle(PressableCard())
                }
            }
            .disabled(busy)

            if let error {
                Text(error)
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.accentDeep)
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
    }

    private func feedbackButton(systemName: String, positive: Bool) -> some View {
        Button {
            Task { await rate(positive) }
        } label: {
            Image(systemName: rated == positive ? "\(systemName).fill" : systemName)
                .font(.system(size: 18))
                .foregroundStyle(rated == positive ? Palette.accent : Palette.inkSoft)
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

    private func eatThis() async throws {
        guard let rx = shownPrescription ?? checkIn.prescription else { return }
        try await CheckInActions.eat(prescriptionID: rx.id, api: env.api)
        Haptics.landed()
        env.changes.mealsChanged()
    }

    private var fullKcal: Int { checkIn.prescription?.totalKcal ?? 0 }
    private var smallerKcal: Int { max(150, Int((Double(fullKcal) / 3.0).rounded() * 3)) }

    private func swapVariant(_ next: String) async {
        struct Body: Encodable { let variant: String }
        struct Reply: Decodable {
            let variant: String
            let prescription: HomeResponse.ActiveCheckIn.Prescription
        }
        do {
            let reply: Reply = try await env.api.post("/api/checkins/\(checkIn.id)/variant", Body(variant: next))
            shownPrescription = reply.prescription
            variant = reply.variant
        } catch {
            self.error = UserFacingError.message(for: error)
        }
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
                drag = y > 0 ? y : y * 0.12 // 1:1 down, heavy resistance up
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
