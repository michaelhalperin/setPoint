import SwiftUI

/// The full-screen tier-3 conversation (§2). A short, bounded exchange in the
/// manager's voice — never open-ended chat. Drag down to dismiss; once the
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

            VStack(spacing: 0) {
                grabber
                if let model {
                    body(model)
                } else {
                    Spacer()
                    ProgressView()
                    Spacer()
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
            .fill(Palette.inkFaint.opacity(0.4))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private func body(_ model: ConversationViewModel) -> some View {
        switch model.phase {
        case .loading:
            Spacer()
            ProgressView()
            Spacer()

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
                    Text("Let's talk")
                        .sectionLabelStyle()
                        .foregroundStyle(Palette.accent)
                        .padding(.bottom, 2)

                    ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                        MessageBubble(message: message)
                            .id(message.id)
                            .appearIn(index, rise: 10)
                    }

                    if model.sending {
                        MessageBubble(message: ConversationMessage(role: "assistant", content: "…", at: nil))
                            .redacted(reason: .placeholder)
                            .id("typing")
                    }

                    if model.resolved, let summary = model.outcomeSummary {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: model.outcomeIcon)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Palette.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.outcomeTitle)
                                    .sectionLabelStyle()
                                    .foregroundStyle(Palette.accent)
                                Text(summary)
                                    .font(Typography.data(14))
                                    .foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surfaceSunk.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                ActionButton(title: "Done") { onResolved() }
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
            TextField("Type a reply…", text: Binding(get: { model.draft }, set: { model.draft = $0 }), axis: .vertical)
                .font(Typography.data(15))
                .lineLimit(1 ... 4)
                .padding(12)
                .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .focused($composerFocused)

            Button {
                composerFocused = false
                Task { await model.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend(model) ? Palette.accent : Palette.inkFaint)
            }
            .disabled(!canSend(model))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Palette.background)
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

private struct MessageBubble: View {
    let message: ConversationMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.content)
                .font(isUser ? Typography.data(15) : Typography.voice(17))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser ? Palette.accentSoft.opacity(0.6) : Palette.surface,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Palette.ink.opacity(isUser ? 0 : 0.05))
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
#endif
