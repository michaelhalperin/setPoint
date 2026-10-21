import SwiftUI

struct NutritionAssistantView: View {
    var previewModel: NutritionAssistantViewModel?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: NutritionAssistantViewModel?
    @FocusState private var composerFocused: Bool
    @State private var drag: CGFloat = 0

    private var dismissProgress: CGFloat { min(1, max(0, drag / 260)) }

    var body: some View {
        ZStack(alignment: .top) {
            Palette.background
                .opacity(1.0 - Double(dismissProgress) * 0.4)
                .ignoresSafeArea()
            AmbientGlow(tone: .ember, strength: 0.8, height: 380)
                .offset(x: -60, y: -80)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 40, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                if let model {
                    body(model)
                } else {
                    ProgressView().tint(Palette.ember).frame(maxHeight: .infinity)
                }
            }
            .offset(y: drag)
            .scaleEffect(1.0 - dismissProgress * 0.04, anchor: .top)
        }
        .gesture(dismissDrag)
        .trackScreen("nutrition_assistant")
        .task {
            if model == nil {
                if let previewModel {
                    model = previewModel
                    return
                }
                let vm = NutritionAssistantViewModel(api: env.api)
                model = vm
                await vm.load()
            }
        }
    }

    @ViewBuilder
    private func body(_ model: NutritionAssistantViewModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView().tint(Palette.ember).frame(maxHeight: .infinity)
        case let .failed(message), let .paused(message), let .ineligible(message), let .locked(message):
            Spacer()
            VStack(spacing: 14) {
                Text(L10n("Nutrition assistant · AI"))
                    .font(Typography.data(13, weight: .medium))
                    .foregroundStyle(Palette.amber)
                Text(message)
                    .font(Typography.data(15))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                if case .failed = model.phase {
                    ActionButton(title: "Try again", kind: .secondary) { Task { await model.load() } }
                        .frame(maxWidth: 200)
                }
                Button(L10n("Close")) { dismiss() }
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }
            .padding(28)
            Spacer()
        case .consent:
            consent(model)
        case .ready:
            conversation(model)
        }
    }

    private func consent(_ model: NutritionAssistantViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Text(model.consent?.title ?? L10n("Nutrition assistant · AI"))
                    .font(Typography.display(28))
                    .foregroundStyle(Palette.ink)
                Text(model.consent?.body ?? "")
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(isOn: Binding(get: { model.reviewConsent }, set: { model.reviewConsent = $0 })) {
                    Text(model.consent?.review ?? L10n("SetPoint may read this whole chat to check it is safe."))
                        .font(Typography.data(14, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                }
                .tint(Palette.ember)
                ActionButton(title: model.consent?.accept ?? L10n("Continue")) {
                    Task { await model.acceptConsent() }
                }
                Button(model.consent?.decline ?? L10n("Not now")) { dismiss() }
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func conversation(_ model: NutritionAssistantViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    Headline(L10n("Nutrition assistant"), tail: L10n("AI — not a dietitian."), size: 36)
                    ForEach(model.messages, id: \.id) { message in
                        expertBubble(message)
                            .id(message.id)
                    }
                    if model.sending {
                        HStack(spacing: 8) {
                            BusyDots(tint: Palette.amber)
                            Text(model.stageLabel ?? model.stages.look)
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
                    if let proposal = model.pendingProposal {
                        CalloutCard(spacing: 12) {
                            Text(proposal.title).sectionLabelStyle(Palette.amber)
                            Text(proposal.summary)
                                .font(Typography.data(16, weight: .regular))
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(proposal.totals.kcal.formatted()) kcal · \(proposal.localDate)")
                                .font(Typography.mono(12))
                                .foregroundStyle(Palette.inkSoft)
                            HStack(spacing: 8) {
                                Button { Task { await model.confirm() } } label: {
                                    BusyLabel(title: L10n("Log it"), busy: model.confirming, tint: Palette.onEmber)
                                        .font(Typography.data(15, weight: .medium))
                                        .foregroundStyle(Palette.onEmber)
                                        .frame(maxWidth: .infinity, minHeight: 46)
                                        .background(Palette.ember, in: Capsule())
                                }
                                .buttonStyle(PressableCard())
                                .disabled(model.confirming)
                                Button { Task { await model.dismissProposal() } } label: {
                                    Text(L10n("Something else"))
                                        .font(Typography.data(14, weight: .regular))
                                        .foregroundStyle(Palette.ink)
                                        .frame(maxWidth: .infinity, minHeight: 46)
                                        .glassCapsule(fill: Color.white.opacity(0.06), stroke: Color.white.opacity(0.10))
                                }
                                .buttonStyle(PressableCard())
                            }
                        }
                        .id("proposal")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _, _ in
                withAnimation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(model.messages.last?.id, anchor: .bottom)
                }
            }
        }
        VStack(alignment: .leading, spacing: 10) {
            if !model.sending, model.pendingProposal == nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.chips, id: \.id) { chip in
                            Button {
                                Task { await model.send(prefilled: chip.message) }
                            } label: {
                                Text(chip.title)
                                    .font(Typography.data(13, weight: .regular))
                                    .foregroundStyle(Palette.amber)
                                    .padding(.horizontal, 14)
                                    .frame(height: 36)
                                    .overlay(Capsule().strokeBorder(Palette.ember.opacity(0.35)))
                            }
                            .buttonStyle(PressableCard())
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            composer(model)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                FuelOrb(size: 18, breathing: false, glow: 0.35)
                Text(L10n("Nutrition assistant · AI")).sectionLabelStyle(Palette.amber)
            }
            Spacer()
            RoundIconButton("xmark", label: L10n("Close"), action: { dismiss() })
        }
    }

    private func expertBubble(_ message: ExpertMessage) -> some View {
        let isUser = message.role == "user"
        return Group {
            if isUser {
                HStack {
                    Spacer(minLength: 60)
                    Text(message.content)
                        .font(Typography.data(14, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Palette.ember.opacity(0.16), in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous))
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
        .environment(\.layoutDirection, AppLanguage.current == .he ? .rightToLeft : .leftToRight)
    }

    private func composer(_ model: NutritionAssistantViewModel) -> some View {
        HStack(spacing: 10) {
            TextField(L10n("Ask about today’s food…"), text: Binding(get: { model.draft }, set: { model.draft = $0 }), axis: .vertical)
                .font(Typography.data(15, weight: .regular))
                .lineLimit(1 ... 4)
                .focused($composerFocused)
            Button {
                composerFocused = false
                Task { await model.send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canSend(model) ? Palette.onEmber : Palette.inkFaint)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(canSend(model) ? Palette.ember : Color.white.opacity(0.10)))
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

    private func canSend(_ model: NutritionAssistantViewModel) -> Bool {
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
                    dismiss()
                } else {
                    withAnimation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion)) { drag = 0 }
                }
            }
    }
}
