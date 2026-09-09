import SwiftUI

/// The full-screen check-in the Home card morphs into (§5a — like a listing →
/// detail transition). Actions: eat the prescription, log something else, or
/// defer. A drag-down dismisses.
struct PrescriptionView: View {
    let checkIn: HomeResponse.ActiveCheckIn
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

    private var dismissProgress: CGFloat { min(1, max(0, drag / 260)) }

    var body: some View {
        ZStack(alignment: .top) {
            Palette.background
                .opacity(1.0 - Double(dismissProgress) * 0.4)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                Capsule()
                    .fill(Palette.inkFaint.opacity(0.4))
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                CheckInContent(checkIn: checkIn, expanded: true)
                    .matchedGeometryEffect(id: geometryID, in: namespace)

                VStack(alignment: .leading, spacing: 18) {
                    actions
                    feedbackRow
                    if let error {
                        Text(error).font(Typography.data(13)).foregroundStyle(Palette.accent)
                    }
                }
                .opacity(settled ? 1 : 0)
                .offset(y: settled ? 0 : 10)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .offset(y: drag)
            .scaleEffect(1.0 - dismissProgress * 0.04, anchor: .top)
        }
        .contentShape(Rectangle())
        .gesture(dismissDrag)
        .animation(Motion.adaptive(Motion.sheet, reduceMotion: reduceMotion), value: settled)
        .task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 240))
            settled = true
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if checkIn.prescription != nil {
                ActionButton(title: busy ? "Logging…" : "I ate this") { run { try await eatThis() } }
            }
            ActionButton(title: "Something else", kind: .secondary) {
                guard !busy else { return }
                onLogSomethingElse()
            }
            Button("Not now") { run { try await deferCheckIn() } }
                .font(Typography.data(15, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
                .padding(.top, 2)
        }
        .disabled(busy)
    }

    @ViewBuilder
    private var feedbackRow: some View {
        HStack(spacing: 12) {
            Text("Was this the right moment?")
                .font(Typography.data(12))
                .foregroundStyle(Palette.inkFaint)
            Spacer()
            feedbackButton(systemName: "hand.thumbsup", positive: true)
            feedbackButton(systemName: "hand.thumbsdown", positive: false)
        }
        .padding(.top, 2)
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
                self.error = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
            }
            busy = false
        }
    }

    private func eatThis() async throws {
        guard let rx = checkIn.prescription else { return }
        let _: LogMealResponse = try await env.api.post(
            "/api/meals",
            LogMealRequest(text: nil, macros: nil, prescriptionId: rx.id)
        )
    }

    private func deferCheckIn() async throws {
        try await env.api.post("/api/checkins/\(checkIn.id)/defer")
    }

    private func rate(_ positive: Bool) async {
        rated = positive
        try? await env.api.post("/api/checkins/\(checkIn.id)/feedback", FeedbackBody(positive: positive))
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in drag = max(0, value.translation.height) }
            .onEnded { value in
                if value.translation.height > 120 || value.predictedEndTranslation.height > 260 {
                    onDismiss()
                } else {
                    withAnimation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion)) { drag = 0 }
                }
            }
    }
}

private struct FeedbackBody: Encodable {
    let positive: Bool
}
