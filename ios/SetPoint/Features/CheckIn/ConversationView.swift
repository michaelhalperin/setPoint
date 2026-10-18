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
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        HStack(spacing: 8) {
                            Circle().fill(Palette.haze).frame(width: 7, height: 7).shadow(color: Palette.haze, radius: 4)
                            Text("Let’s talk").sectionLabelStyle(Palette.hazeSoft)
                        }
                        Spacer()
                        RoundIconButton("xmark", label: "Close", action: onDismiss)
                    }

                    Headline("Rough few days.", tail: "Let’s fix the plan, not you.", size: 40)
                        .appearIn(0, rise: 16)

                    if let opener = model.messages.first, opener.role == "assistant" {
                        Text(opener.content)
                            .font(Typography.display(24))
                            .tracking(-0.6)
                            .foregroundStyle(Color(hex: 0xD4D4D8))
                            .lineSpacing(1)
                            .fixedSize(horizontal: false, vertical: true)
                            .id(opener.id)
                            .appearIn(1)
                    }

                    ForEach(Array(model.messages.dropFirst().enumerated()), id: \.element.id) { index, message in
                        MessageBubble(message: message)
                            .id(message.id)
                            .appearIn(index, rise: 10)
                    }

                    if model.sending {
                        HStack(spacing: 8) {
                            BusyDots(tint: Palette.hazeSoft)
                            Text("Thinking it over")
                                .font(Typography.data(13, weight: .regular))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .id("typing")
                    }

                    if let err = model.sendError {
                        Text(err)
                            .font(Typography.data(13, weight: .regular))
                            .foregroundStyle(Palette.amber)
                    }

                    if let proposal = model.pendingProposal, !model.resolved {
                        CalloutCard(haze: true, spacing: 12) {
                            Text("What I’d change").sectionLabelStyle(Palette.hazeSoft)
                            Headline(proposal.title, size: 24)
                            Text(proposal.summary)
                                .font(Typography.data(14, weight: .regular))
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                Button {
                                    Task { await model.confirmProposal() }
                                } label: {
                                    BusyLabel(title: "Do it", busy: model.confirming, tint: Palette.onBone)
                                        .font(Typography.data(15, weight: .medium))
                                        .foregroundStyle(Palette.onBone)
                                        .frame(maxWidth: .infinity, minHeight: 46)
                                        .background(Palette.ink, in: Capsule())
                                }
                                .buttonStyle(PressableCard())
                                .disabled(model.confirming)
                                Button { composerFocused = true } label: {
                                    Text("Something else")
                                        .font(Typography.data(14, weight: .regular))
                                        .foregroundStyle(Palette.ink)
                                        .frame(maxWidth: .infinity, minHeight: 46)
                                        .glassCapsule(fill: Color.white.opacity(0.06), stroke: Color.white.opacity(0.10))
                                }
                                .buttonStyle(PressableCard())
                            }
                        }
                        .id("proposal")
                        .appearIn()
                    }

                    if model.resolved, let summary = model.outcomeSummary {
                        VStack(spacing: 12) {
                            ZStack {
                                FuelOrb(size: 54, glow: 0.6, haze: true)
                                Image(systemName: model.outcomeIcon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Color(hex: 0x0F0E2A))
                            }
                            Text(model.outcomeTitle)
                                .font(Typography.display(22))
                                .foregroundStyle(Palette.ink)
                                .multilineTextAlignment(.center)
                            Text(summary)
                                .font(Typography.data(14, weight: .regular))
                                .foregroundStyle(Palette.inkSoft)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 22)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(LinearGradient(colors: [Palette.haze.opacity(0.12), Palette.haze.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        }
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hazeSoft.opacity(0.30)))
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
                VStack(alignment: .leading, spacing: 10) {
                    if model.messages.count == 1, !model.sending {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(QuickFix.all, id: \.title) { fix in
                                    Button {
                                        model.draft = fix.message
                                        Task { await model.send() }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: fix.symbol).font(.system(size: 12, weight: .regular))
                                            Text(fix.title).font(Typography.data(13, weight: .regular))
                                        }
                                        .foregroundStyle(Palette.hazeSoft)
                                        .padding(.horizontal, 14)
                                        .frame(height: 36)
                                        .overlay(Capsule().strokeBorder(Palette.hazeSoft.opacity(0.35)))
                                        .contentShape(Capsule())
                                    }
                                    .buttonStyle(PressableCard())
                                    .accessibilityHint(fix.detail)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .transition(.opacity)
                    }
                    composer(model)
                }
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

private struct MessageBubble: View {
    let message: ConversationMessage

    private var isUser: Bool { message.role == "user" }

    /// The manager speaks in big light lines; your reply is a small haze bubble.
    var body: some View {
        if isUser {
            HStack {
                Spacer(minLength: 60)
                Text(message.content)
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Palette.haze.opacity(0.16), in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous))
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous).strokeBorder(Palette.hazeSoft.opacity(0.30)))
            }
        } else {
            Text(message.content)
                .font(Typography.display(22))
                .tracking(-0.5)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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
