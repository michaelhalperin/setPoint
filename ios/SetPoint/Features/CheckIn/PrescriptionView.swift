import SwiftUI

/// The full-screen check-in the Home card morphs into (§5a — like a listing →
/// detail transition). The card lifts off the home surface (which dims and sits
/// behind), the actions cascade in once it settles, and a rubber-banded drag
/// down dismisses it.
struct PrescriptionView: View {
    let checkIn: HomeResponse.ActiveCheckIn
    /// Minutes until the user's next meal anchor — powers the "after my next
    /// meal" snooze option. Nil hides that choice.
    var nextMealMinutes: Int? = nil
    let namespace: Namespace.ID
    let geometryID: String
    /// Close the morph (spring back to the card).
    let onDismiss: () -> Void
    /// A meal was logged / the check-in was deferred — reload Home, then close.
    let onResolved: () -> Void
    /// Open the free-text meal logger instead.
    let onLogSomethingElse: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var busy = false
    @State private var error: String?
    @State private var rated: Bool?
    @State private var settled = false
    @State private var drag: CGFloat = 0
    @State private var choosingSnooze = false

    private var dismissProgress: CGFloat { min(1, max(0, drag / 240)) }

    var body: some View {
        ZStack(alignment: .top) {
            Palette.background
                .opacity(1.0 - Double(dismissProgress) * 0.5)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: Space.md) {
                Capsule()
                    .fill(Palette.inkFaint.opacity(0.4))
                    .frame(width: 36 + dismissProgress * 12, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.xs)

                CheckInContent(checkIn: checkIn, expanded: true)
                    .matchedGeometryEffect(id: geometryID, in: namespace)

                actions

                if let error {
                    Text(error).font(Typography.data(13)).foregroundStyle(Palette.accent)
                        .staggerReveal(settled, index: 3)
                }

                Spacer(minLength: 0)

                feedbackRow
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xs)
            .offset(y: drag)
            .scaleEffect(1.0 - dismissProgress * 0.04, anchor: .top)
        }
        .contentShape(Rectangle())
        .gesture(dismissDrag)
        .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion), value: settled)
        .task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 260))
            settled = true
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: Space.xs + 2) {
            if checkIn.prescription != nil {
                ActionButton(title: busy ? "Logging…" : "I ate this") { run { try await eatThis() } }
                    .staggerReveal(settled, index: 0)
            }
            ActionButton(title: "Something else", kind: .secondary) {
                guard !busy else { return }
                onLogSomethingElse()
            }
            .staggerReveal(settled, index: 1)

            Button("Not now") {
                guard !busy else { return }
                choosingSnooze = true
            }
                .font(Typography.data(15, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
                .padding(.top, 2)
                .staggerReveal(settled, index: 2)
        }
        .disabled(busy)
        .confirmationDialog("Snooze this check-in", isPresented: $choosingSnooze, titleVisibility: .visible) {
            ForEach(CheckInActions.snoozeChoices(nextMealMinutes: nextMealMinutes)) { choice in
                Button(choice.title) { run { try await deferCheckIn(minutes: choice.minutes) } }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var feedbackRow: some View {
        HStack(spacing: Space.sm) {
            Text("Good timing?")
                .font(Typography.data(12))
                .foregroundStyle(Palette.inkFaint)
            Spacer()
            feedbackButton(systemName: "hand.thumbsup", positive: true)
            feedbackButton(systemName: "hand.thumbsdown", positive: false)
        }
        .padding(.top, 2)
        .padding(.bottom, Space.xs)
        .staggerReveal(settled, index: 4)
    }

    private func feedbackButton(systemName: String, positive: Bool) -> some View {
        Button {
            Task { await rate(positive) }
        } label: {
            Image(systemName: rated == positive ? "\(systemName).fill" : systemName)
                .font(.system(size: 16))
                .foregroundStyle(rated == positive ? Palette.accent : Palette.inkFaint)
        }
        .disabled(rated != nil)
    }

    // MARK: Networking

    private func run(_ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            do {
                try await work()
                onResolved()
            } catch {
            self.error = UserFacingError.message(for: error, fallback: "Couldn't do that. Try again.")
            }
            busy = false
        }
    }

    private func eatThis() async throws {
        guard let rx = checkIn.prescription else { return }
        try await CheckInActions.eat(prescriptionID: rx.id, api: env.api)
        env.changes.mealsChanged()
    }

    private func deferCheckIn(minutes: Int? = nil) async throws {
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
