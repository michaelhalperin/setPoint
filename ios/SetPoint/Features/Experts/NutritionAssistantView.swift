import SwiftUI

/// The Nutrition assistant: a chat about today's food that can suggest a plate
/// to log. A compact header and today's calories left on top, the conversation
/// in readable text, plates as cards you can log in one tap, the composer below.
struct NutritionAssistantView: View {
    var previewModel: NutritionAssistantViewModel?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: NutritionAssistantViewModel?
    @FocusState private var composerFocused: Bool
    @State private var drag: CGFloat = 0
    @State private var confirmingClear = false

    private var dismissProgress: CGFloat { min(1, max(0, drag / 260)) }

    var body: some View {
        ZStack(alignment: .top) {
            Palette.background
                .opacity(1.0 - Double(dismissProgress) * 0.4)
                .ignoresSafeArea()
            AmbientGlow(tone: .ember, strength: 0.55, height: 320)
                .offset(x: -60, y: -110)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 40, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .accessibilityHidden(true)
                header
                if let model {
                    content(model)
                } else {
                    Spacer()
                    BusyDots(tint: Palette.amber)
                    Spacer()
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
        .confirmationDialog(L10n("Clear this chat?"), isPresented: $confirmingClear, titleVisibility: .visible) {
            Button(L10n("Clear chat"), role: .destructive) { Task { await model?.clear() } }
            Button(L10n("Cancel"), role: .cancel) {}
        }
    }

    // MARK: Header

    /// The first screens (consent, and an empty chat) carry their own title; the
    /// title row only shows once there's a conversation.
    private var showsTitle: Bool {
        guard let model, case .ready = model.phase else { return false }
        return !model.messages.isEmpty || model.sending
    }

    private var header: some View {
        HStack(spacing: 12) {
            if showsTitle {
                FuelOrb(size: 34, breathing: !reduceMotion, glow: 0.45)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n("Nutrition assistant"))
                        .font(Typography.data(16, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text(L10n("AI · not a dietitian"))
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.inkFaint)
                }
                .transition(.opacity)
            }
            Spacer(minLength: 8)
            if case .ready = model?.phase, !(model?.messages.isEmpty ?? true) {
                Menu {
                    Button(role: .destructive) { confirmingClear = true } label: {
                        Label(L10n("Clear chat"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .accessibilityLabel(L10n("More"))
            }
            RoundIconButton("xmark", label: L10n("Close"), action: { dismiss() })
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    // MARK: Phases

    @ViewBuilder
    private func content(_ model: NutritionAssistantViewModel) -> some View {
        switch model.phase {
        case .loading:
            Spacer()
            BusyDots(tint: Palette.amber)
            Spacer()
        case let .failed(message):
            stateCard(symbol: "wifi.exclamationmark", title: L10n("Couldn’t reach the assistant"), message: message) {
                ActionButton(title: "Try again", kind: .secondary) { Task { await model.load() } }
            }
        case let .paused(message):
            stateCard(symbol: "pause.circle", title: L10n("The assistant is paused"), message: message) { EmptyView() }
        case let .ineligible(message):
            stateCard(symbol: "hand.raised", title: L10n("Not available for you yet"), message: message) { EmptyView() }
        case let .locked(message):
            stateCard(symbol: "lock", title: L10n("Part of Pro"), message: message) { EmptyView() }
        case .consent:
            consent(model)
        case .ready:
            conversation(model)
        }
    }

    private func stateCard(symbol: String, title: String, message: String, @ViewBuilder action: () -> some View) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Palette.amber)
                    .frame(width: 52, height: 52)
                    .background(Palette.ember.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(Typography.data(18, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                if !message.isEmpty {
                    Text(message)
                        .font(Typography.data(14, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                action()
                    .frame(maxWidth: 220)
                Button(L10n("Close")) { dismiss() }
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(minHeight: 44)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .glass(radius: 28, fill: Color.white.opacity(0.04), stroke: Color.white.opacity(0.09))
            .padding(.horizontal, 20)
            Spacer()
            Spacer()
        }
    }

    // MARK: Consent

    private func consent(_ model: NutritionAssistantViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FuelOrb(size: 88, breathing: !reduceMotion, glow: 0.55)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
                Text(model.consent?.title ?? L10n("Nutrition assistant · AI"))
                    .font(Typography.display(30))
                    .tracking(-0.6)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let body = model.consent?.body, !body.isEmpty {
                    Text(body)
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 14) {
                    point("fork.knife", L10n("It sees today’s meals and your targets."))
                    point("checkmark.circle", L10n("It suggests a plate. Nothing is logged until you tap Log it."))
                    point("stethoscope", L10n("It’s AI, not a dietitian. For medical questions, ask a professional."))
                }
                .padding(16)
                .glass(radius: 22, fill: Color.white.opacity(0.04), stroke: Color.white.opacity(0.08))

                Toggle(isOn: Binding(get: { model.reviewConsent }, set: { model.reviewConsent = $0 })) {
                    Text(model.consent?.review ?? L10n("SetPoint may read this whole chat to check it is safe."))
                        .font(Typography.data(14, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(Palette.ember)

                ActionButton(title: model.consent?.accept ?? L10n("Continue")) {
                    Task { await model.acceptConsent() }
                }
                Button(model.consent?.decline ?? L10n("Not now")) { dismiss() }
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.amber)
                .frame(width: 28, height: 28)
                .background(Palette.ember.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    // MARK: Conversation

    @ViewBuilder
    private func conversation(_ model: NutritionAssistantViewModel) -> some View {
        if let left = model.remainingKcal, showsTitle {
            todayStrip(left)
        }
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.messages.isEmpty && !model.sending {
                        welcome(model)
                    }
                    ForEach(model.messages, id: \.id) { message in
                        bubble(message)
                            .id(message.id)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if model.sending {
                        thinking(model).id("thinking")
                    }
                    if let err = model.sendError {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(Palette.amber)
                                .accessibilityHidden(true)
                            Text(err)
                                .font(Typography.data(13, weight: .regular))
                                .foregroundStyle(Palette.amber)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .id("error")
                    }
                    if let proposal = model.pendingProposal {
                        plateCard(proposal, model: model).id("proposal")
                    } else if let logged = model.justLogged {
                        loggedRow(logged).id("logged")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: model.messages.count)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { scrollToEnd(proxy, model) }
            .onChange(of: model.messages.count) { _, _ in scrollToEnd(proxy, model) }
            .onChange(of: model.sending) { _, _ in scrollToEnd(proxy, model) }
            .onChange(of: model.pendingProposal?.id) { _, _ in scrollToEnd(proxy, model) }
        }
        bottomBar(model)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, _ model: NutritionAssistantViewModel) {
        let target: String? = model.pendingProposal != nil ? "proposal" : model.sending ? "thinking" : model.messages.last?.id
        guard let target else { return }
        withAnimation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion)) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    private func todayStrip(_ left: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Palette.amber).frame(width: 6, height: 6)
            Text(L10n("Today"))
                .font(Typography.mono(11))
                .tracking(1)
                .foregroundStyle(Palette.inkFaint)
            Text(left > 0 ? L10n("\(left.formatted()) kcal left") : L10n("Today’s target is met"))
                .font(Typography.data(13, weight: .medium))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .glassCapsule(fill: Color.white.opacity(0.05), stroke: Color.white.opacity(0.09))
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }

    private func welcome(_ model: NutritionAssistantViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n("What should I eat next?"))
                .font(Typography.display(30))
                .tracking(-0.6)
                .foregroundStyle(Palette.ink)
            Text(model.remainingKcal.map { $0 > 0 ? L10n("\($0.formatted()) kcal left today. Ask about food, or start with one of these.") : L10n("Today’s target is met. Ask about food, or start with one of these.") } ?? L10n("Ask about today’s food, or start with one of these."))
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(model.chips.prefix(4), id: \.id) { chip in
                    Button { Task { await model.send(prefilled: chip.message) } } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.amber)
                            Text(chip.title)
                                .font(Typography.data(14, weight: .regular))
                                .foregroundStyle(Palette.ink)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                        .glass(radius: 20, fill: Color.white.opacity(0.04), stroke: Color.white.opacity(0.09))
                    }
                    .buttonStyle(PressableCard())
                }
            }
        }
        .padding(.top, 8)
    }

    private func bubble(_ message: ExpertMessage) -> some View {
        Group {
            if message.role == "user" {
                HStack {
                    Spacer(minLength: 56)
                    Text(message.content)
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Palette.ember.opacity(0.18), in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous))
                        .overlay(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous).strokeBorder(Palette.ember.opacity(0.30)))
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    FuelOrb(size: 20, breathing: false, glow: 0.3)
                        .frame(width: 24, height: 24)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    Text(message.content)
                        .font(Typography.data(16, weight: .regular))
                        .lineSpacing(3)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .environment(\.layoutDirection, AppLanguage.current == .he ? .rightToLeft : .leftToRight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.role == "user" ? L10n("You: \(message.content)") : message.content)
    }

    /// The three steps the assistant goes through, the current one lit.
    private func thinking(_ model: NutritionAssistantViewModel) -> some View {
        let steps = [model.stages.look, model.stages.plate, model.stages.check]
        let current = steps.firstIndex(of: model.stageLabel ?? steps[0]) ?? 0
        return HStack(alignment: .top, spacing: 10) {
            FuelOrb(size: 20, breathing: !reduceMotion, glow: 0.5)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 8) {
                        ZStack {
                            if index < current {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Palette.onEmber)
                                    .frame(width: 16, height: 16)
                                    .background(Palette.amber, in: Circle())
                            } else if index == current {
                                Circle().strokeBorder(Palette.amber, lineWidth: 2).frame(width: 16, height: 16)
                                    .shadow(color: Palette.ember.opacity(0.7), radius: 5)
                            } else {
                                Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5).frame(width: 16, height: 16)
                            }
                        }
                        Text(step)
                            .font(Typography.data(13, weight: index == current ? .medium : .regular))
                            .foregroundStyle(index == current ? Palette.ink : Palette.inkFaint)
                    }
                }
            }
            .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: current)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(steps[current])
    }

    // MARK: Plates

    private func plateCard(_ p: ExpertProposalCard, model: NutritionAssistantViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Circle().fill(Palette.amber).frame(width: 6, height: 6)
                Text(p.title.uppercased())
                    .font(Typography.mono(10))
                    .tracking(1.2)
                    .foregroundStyle(Palette.amber)
                Spacer(minLength: 8)
                Text("\(p.totals.kcal.formatted()) kcal")
                    .font(Typography.mono(13))
                    .foregroundStyle(Palette.ink)
            }
            Text(p.summary)
                .font(Typography.data(16, weight: .regular))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !p.items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(p.items.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.quantity > 1 ? "\(item.quantity) × \(item.name)" : item.name)
                                    .font(Typography.data(14, weight: .regular))
                                    .foregroundStyle(Palette.ink)
                                Text(item.servingDesc)
                                    .font(Typography.data(12, weight: .regular))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                            Spacer(minLength: 8)
                            Text(item.kcal.formatted())
                                .font(Typography.mono(12))
                                .foregroundStyle(Palette.inkSoft)
                        }
                        .padding(.vertical, 9)
                    }
                }
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            macroBar(p.totals)

            if let left = model.remainingKcal, left > 0 {
                Text(L10n("Fits \(p.totals.kcal.formatted()) of your \(left.formatted()) kcal left"))
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }

            HStack(spacing: 8) {
                Button { Task { await model.confirm() } } label: {
                    BusyLabel(title: L10n("Log it"), busy: model.confirming, tint: Palette.onEmber)
                        .font(Typography.data(15, weight: .medium))
                        .foregroundStyle(Palette.onEmber)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Palette.ember, in: Capsule())
                }
                .buttonStyle(PressableCard())
                .disabled(model.confirming)
                Button { Task { await model.dismissProposal() } } label: {
                    Text(L10n("Something else"))
                        .font(Typography.data(14, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .glassCapsule(fill: Color.white.opacity(0.06), stroke: Color.white.opacity(0.10))
                }
                .buttonStyle(PressableCard())
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Palette.ember.opacity(0.14), Color.white.opacity(0.03)], startPoint: .topLeading, endPoint: UnitPoint(x: 0.6, y: 0.9)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.ember.opacity(0.40))
        }
        .shadow(color: Palette.ember.opacity(0.12), radius: 24, y: 12)
        .padding(.leading, 34)
    }

    private func macroBar(_ t: ExpertProposalCard.Totals) -> some View {
        let p = t.proteinG * 4, c = t.carbsG * 4, f = t.fatG * 9
        let total = max(1, p + c + f)
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width - 4
                HStack(spacing: 2) {
                    Capsule().fill(Palette.amber).frame(width: max(4, w * p / total))
                    Capsule().fill(Color(hex: 0xD4D4D8)).frame(width: max(4, w * c / total))
                    Capsule().fill(Palette.ember.opacity(0.55)).frame(width: max(4, w * f / total))
                }
            }
            .frame(height: 6)
            HStack(spacing: 14) {
                macro(Palette.amber, "\(Int(t.proteinG.rounded())) g", L10n("protein"))
                macro(Color(hex: 0xD4D4D8), "\(Int(t.carbsG.rounded())) g", L10n("carbs"))
                macro(Palette.ember.opacity(0.55), "\(Int(t.fatG.rounded())) g", L10n("fat"))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n("\(Int(t.proteinG.rounded())) grams protein, \(Int(t.carbsG.rounded())) carbs, \(Int(t.fatG.rounded())) fat"))
    }

    private func macro(_ color: Color, _ value: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            (Text(value).foregroundColor(Palette.ink) + Text(" \(label)").foregroundColor(Palette.inkFaint))
                .font(Typography.data(12, weight: .regular))
        }
    }

    private func loggedRow(_ p: ExpertProposalCard) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.onBone)
                .frame(width: 22, height: 22)
                .background(Palette.positive, in: Circle())
                .accessibilityHidden(true)
            Text(L10n("Logged · \(p.totals.kcal.formatted()) kcal"))
                .font(Typography.data(14, weight: .medium))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            Text(p.title)
                .font(Typography.data(12, weight: .regular))
                .foregroundStyle(Palette.inkFaint)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Palette.positive.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.positive.opacity(0.35)))
        .padding(.leading, 34)
        .transition(.opacity)
    }

    // MARK: Composer

    private func bottomBar(_ model: NutritionAssistantViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.sending, model.pendingProposal == nil, !model.messages.isEmpty, !model.chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.chips, id: \.id) { chip in
                            Button { Task { await model.send(prefilled: chip.message) } } label: {
                                Text(chip.title)
                                    .font(Typography.data(13, weight: .regular))
                                    .foregroundStyle(Palette.ink)
                                    .padding(.horizontal, 14)
                                    .frame(height: 36)
                                    .glassCapsule(fill: Palette.ember.opacity(0.10), stroke: Palette.ember.opacity(0.35))
                            }
                            .buttonStyle(PressableCard())
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(L10n("Ask about today’s food…"), text: Binding(get: { model.draft }, set: { model.draft = $0 }), axis: .vertical)
                    .font(Typography.data(15, weight: .regular))
                    .lineLimit(1 ... 4)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .padding(.vertical, 8)
                Button {
                    composerFocused = false
                    Task { await model.send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(canSend(model) ? Palette.onEmber : Palette.inkFaint)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(canSend(model) ? Palette.ember : Color.white.opacity(0.10)))
                        .animation(Motion.snappy, value: canSend(model))
                }
                .disabled(!canSend(model))
                .accessibilityLabel(L10n("Send"))
            }
            .padding(.leading, 18)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .glass(radius: 26, fill: Color.white.opacity(0.05), stroke: composerFocused ? Palette.ember.opacity(0.45) : Color.white.opacity(0.10))
            .padding(.horizontal, 16)

            Text(L10n("AI can be wrong. Not medical advice."))
                .font(Typography.data(11, weight: .regular))
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
        }
        .padding(.top, 8)
        .background(
            LinearGradient(colors: [Palette.background.opacity(0), Palette.background], startPoint: .top, endPoint: .init(x: 0.5, y: 0.3))
                .ignoresSafeArea()
        )
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
