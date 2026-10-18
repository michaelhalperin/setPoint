import SwiftUI

/// The full-screen tier-3 conversation (§2). "Rough few days." — the manager's
/// opener, then three concrete fixes to tap (or a reply in your own words). A
/// short, bounded exchange, never open-ended chat. Drag down to dismiss; once the
/// backend lands on an outcome the composer closes and "Done" reloads Home.
struct ConversationView: View {
    let checkInID: String
    let onDismiss: () -> Void
    let onResolved: () -> Void
    var previewModel: ConversationViewModel?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: ConversationViewModel?
    @FocusState private var composerFocused: Bool
    @State private var drag: CGFloat = 0

    private var dismissProgress: CGFloat { min(1, max(0, drag / 260)) }

    var body: some View {
        ZStack(alignment: .top) {
            Palette.background
                .opacity(1.0 - Double(dismissProgress) * 0.4)
                .ignoresSafeArea()
            AmbientGlow(tone: .haze, strength: 0.8, height: 380)
                .offset(x: -60, y: -80)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                grabber
                if let model {
                    body(model)
                } else {
                    ConversationSkeletonView()
                }
            }
            .offset(y: drag)
            .scaleEffect(1.0 - dismissProgress * 0.04, anchor: .top)
        }
        .gesture(dismissDrag)
        .task {
            if model == nil {
                if let previewModel {
                    model = previewModel
                    return
                }
                let vm = ConversationViewModel(checkInID: checkInID, api: env.api)
                model = vm
                await vm.load()
            }
        }
    }

    private var grabber: some View {
        Capsule()
            .fill(Color.white.opacity(0.18))
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private func body(_ model: ConversationViewModel) -> some View {
        switch model.phase {
        case .loading:
            ConversationSkeletonView()

        case let .failed(message):
            Spacer()
            VStack(spacing: 14) {
                Text(message)
                    .font(Typography.data(15))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                ActionButton(title: "Try again", kind: .secondary) { Task { await model.load() } }
                    .frame(maxWidth: 200)
            }
            .padding(28)
            Spacer()

        case .ready:
            conversation(model)
        }
    }

    @ViewBuilder
    private func conversation(_ model: ConversationViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Let’s talk").sectionLabelStyle()
                        Spacer()
                        RoundIconButton("xmark", label: "Close", action: onDismiss)
                    }

                    Headline("Rough few days.", tail: "A few check-ins didn’t land.", size: 42)
                        .appearIn(0, rise: 16)

                    if let opener = model.messages.first, opener.role == "assistant" {
                        Text(opener.content)
                            .font(Typography.data(15, weight: .regular))
                            .foregroundStyle(Color(hex: 0xD4D4D8))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .id(opener.id)
                            .appearIn(1)
                    }

                    if model.messages.count == 1, !model.resolved, !model.sending {
                        VStack(spacing: 10) {
                            ForEach(Array(QuickFix.all.enumerated()), id: \.element.title) { index, fix in
                                Button {
                                    model.draft = fix.message
                                    Task { await model.send() }
                                } label: {
                                    QuickFixCard(fix: fix)
                                }
                                .buttonStyle(PressableCard())
                                .appearIn(2 + index)
                            }
                        }
                        .padding(.top, 4)
                        .transition(.opacity)
                    }

                    ForEach(Array(model.messages.dropFirst().enumerated()), id: \.element.id) { index, message in
                        MessageBubble(message: message)
                            .id(message.id)
                            .appearIn(index, rise: 10)
                    }

                    if model.sending {
                        MessageBubble(message: ConversationMessage(role: "assistant", content: "…", at: nil))
                            .redacted(reason: .placeholder)
                            .id("typing")
                    }

                    if let err = model.sendError {
                        Text(err)
                            .font(Typography.data(13, weight: .semibold))
                            .foregroundStyle(Palette.amber)
                    }

                    if let proposal = model.pendingProposal, !model.resolved {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(proposal.title)
                                .font(Typography.data(16, weight: .medium))
                                .foregroundStyle(Palette.ink)
                            Text(proposal.summary)
                                .font(Typography.data(14))
                                .foregroundStyle(Palette.inkSoft)
                            ActionButton(title: "Apply this", busy: model.confirming) {
                                Task { await model.confirmProposal() }
                            }
                        }
                        .padding(16)
                        .glass(radius: 22)
                        .id("proposal")
                    }

                    if model.resolved, let summary = model.outcomeSummary {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: model.outcomeIcon)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Palette.hazeSoft)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.outcomeTitle)
                                    .font(Typography.data(16, weight: .medium))
                                    .foregroundStyle(Palette.ink)
                                Text(summary)
                                    .font(Typography.data(14))
                                    .foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glass(radius: 24, fill: Color(hex: 0xA5B4FC, opacity: 0.08), stroke: Color(hex: 0xA5B4FC, opacity: 0.25))
                        .padding(.top, 8)
                        .appearIn()
                        .id("outcome")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages) { _, _ in
                withAnimation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(model.resolved ? "outcome" : model.messages.last?.id, anchor: .bottom)
                }
            }
        }

        Group {
            if model.resolved {
                ActionButton(title: "Back to today") { onResolved() }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                composer(model)
                    .transition(.opacity)
            }
        }
        .animation(Motion.adaptive(Motion.morph, reduceMotion: reduceMotion), value: model.resolved)
    }

    @ViewBuilder
    private func composer(_ model: ConversationViewModel) -> some View {
        HStack(spacing: 10) {
            TextField(model.messages.count == 1 ? "Or tell me what’s going on…" : "Reply…", text: Binding(get: { model.draft }, set: { model.draft = $0 }), axis: .vertical)
                .font(Typography.data(15, weight: .regular))
                .lineLimit(1 ... 4)
                .focused($composerFocused)

            Button {
                composerFocused = false
                Task { await model.send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canSend(model) ? Palette.onBone : Palette.inkFaint)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(canSend(model) ? Palette.ink : Color.white.opacity(0.10)))
            }
            .disabled(!canSend(model))
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glass(radius: 26, fill: Color.white.opacity(0.05), stroke: Color.white.opacity(0.10))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func canSend(_ model: ConversationViewModel) -> Bool {
        !model.sending && !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard value.translation.height > 0 else { return }
                drag = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > 120 || value.predictedEndTranslation.height > 260 {
                    onDismiss()
                } else {
                    withAnimation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion)) { drag = 0 }
                }
            }
    }
}

private struct ConversationSkeletonView: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SkeletonBlock(width: 72, height: 12)
                    Spacer()
                    Circle().fill(Color.white.opacity(0.06)).frame(width: 34, height: 34)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBlock(width: 220, height: 40, radius: 10)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBlock(height: 19, radius: 6)
                    SkeletonBlock(width: 240, height: 19, radius: 6)
                }

                VStack(spacing: 10) {
                    quickFix
                    quickFix
                    quickFix
                }
                .padding(.top, 4)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            HStack(spacing: 10) {
                SkeletonBlock(height: 44, radius: 14)
                Circle().fill(Color.white.opacity(0.06)).frame(width: 30, height: 30)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Palette.background)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .skeletonLoading()
    }

    private var quickFix: some View {
        HStack(spacing: 14) {
            Circle().fill(Color.white.opacity(0.06)).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(width: 132, height: 16)
                SkeletonBlock(width: 188, height: 13)
            }
            Spacer(minLength: 0)
            SkeletonBlock(width: 12, height: 14, radius: 3)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.hairline))
        }
    }
}

/// One tap on a concrete change, sent to the manager as the user's reply.
private struct QuickFix {
    let symbol: String
    let title: String
    let detail: String
    let message: String

    static let all = [
        QuickFix(symbol: "clock", title: "Check in later", detail: "More time before a meal counts as slipped",
                 message: "Can you check in later? I need more time around my meals."),
        QuickFix(symbol: "slider.horizontal.3", title: "Ease the target", detail: "A lower number for a while",
                 message: "Can we ease my target for a while?"),
        QuickFix(symbol: "pause", title: "Pause for a few days", detail: "I’ll pick it back up",
                 message: "Can we pause check-ins for a few days?"),
    ]
}

private struct QuickFixCard: View {
    let fix: QuickFix

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: fix.symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Palette.hazeSoft)
                .frame(width: 40, height: 40)
                .background(Palette.haze.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(fix.title)
                    .font(Typography.data(16, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(fix.detail)
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(16)
        .glass(radius: 22)
    }
}

private struct MessageBubble: View {
    let message: ConversationMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.content)
                .font(Typography.data(15, weight: .regular))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser ? Palette.haze.opacity(0.18) : Palette.glass,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isUser ? Palette.haze.opacity(0.3) : Palette.hairline)
                )
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

#if DEBUG
#Preview("Mid-conversation") {
    ConversationView(checkInID: "ci_1", onDismiss: {}, onResolved: {}, previewModel: .previewed(resolved: false))
        .environment(AppEnvironment.preview())
}

#Preview("Resolved") {
    ConversationView(checkInID: "ci_1", onDismiss: {}, onResolved: {}, previewModel: .previewed(resolved: true))
        .environment(AppEnvironment.preview())
}

#Preview("Skeleton") {
    ConversationSkeletonView()
}
#endif
