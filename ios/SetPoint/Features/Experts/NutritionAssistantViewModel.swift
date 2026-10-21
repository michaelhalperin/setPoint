import Foundation
import Observation

@MainActor
@Observable
final class NutritionAssistantViewModel {
    enum Phase: Equatable {
        case loading
        case consent
        case ready
        case paused(String)
        case ineligible(String)
        case locked(String)
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var messages: [ExpertMessage] = []
    private(set) var chips: [ExpertChip] = []
    private(set) var pendingProposal: ExpertProposalCard?
    private(set) var consent: ExpertConsentCopy?
    private(set) var stages: ExpertStages = .defaults
    private(set) var sending = false
    private(set) var confirming = false
    private(set) var sendError: String?
    private(set) var stageLabel: String?
    /// What's left of today's target, when the server says.
    private(set) var remainingKcal: Int?
    /// The plate just logged from a proposal, shown as a confirmation until the next message.
    private(set) var justLogged: ExpertProposalCard?
    var draft = ""
    var reviewConsent = false

    private let api: APIClient
    private var stageTask: Task<Void, Never>?

    init(api: APIClient) {
        self.api = api
    }

    private var lang: String { AppLanguage.current.rawValue }

    func load() async {
        phase = .loading
        do {
            let res: ExpertThreadResponse = try await api.get("/api/experts/nutrition", query: ["lang": lang])
            apply(res)
        } catch {
            phase = .failed(UserFacingError.message(for: error, fallback: L10n("Couldn't load. Try again.")))
        }
    }

    func acceptConsent() async {
        do {
            struct Body: Encodable {
                let accept: Bool
                let reviewConsent: Bool
                let lang: String
            }
            let res: ExpertThreadResponse = try await api.post(
                "/api/experts/nutrition/consent",
                Body(accept: true, reviewConsent: reviewConsent, lang: lang)
            )
            apply(res)
        } catch {
            phase = .failed(UserFacingError.message(for: error, fallback: L10n("Couldn't load. Try again.")))
        }
    }

    func send(prefilled: String? = nil) async {
        let text = (prefilled ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        sendError = nil
        justLogged = nil
        if prefilled == nil { draft = "" }
        messages.append(ExpertMessage(role: "user", content: text, at: nil))
        startStages()
        defer {
            sending = false
            stopStages()
        }
        do {
            struct Body: Encodable { let message: String; let lang: String }
            let res: ExpertThreadResponse = try await api.post(
                "/api/experts/nutrition",
                Body(message: text, lang: lang)
            )
            apply(res)
        } catch let error as APIError {
            if case let .http(status, _) = error, status == 429 {
                sendError = L10n("Too many requests right now. Try again in a bit.")
            } else {
                sendError = UserFacingError.message(for: error, fallback: L10n("Couldn't send. Try again."))
            }
            messages.removeAll { $0.role == "user" && $0.content == text && $0.at == nil }
            if prefilled == nil { draft = text }
        } catch {
            sendError = UserFacingError.message(for: error, fallback: L10n("Couldn't send. Try again."))
            messages.removeAll { $0.role == "user" && $0.content == text && $0.at == nil }
            if prefilled == nil { draft = text }
        }
    }

    func confirm() async {
        guard let proposal = pendingProposal, !confirming else { return }
        let id = proposal.id
        confirming = true
        sendError = nil
        defer { confirming = false }
        do {
            struct Body: Encodable { let proposalId: String; let lang: String }
            let _: ExpertConfirmResponse = try await api.post(
                "/api/experts/nutrition/confirm",
                Body(proposalId: id, lang: lang)
            )
            pendingProposal = nil
            justLogged = proposal
            await load()
        } catch {
            sendError = UserFacingError.message(for: error, fallback: L10n("Couldn't apply that change."))
        }
    }

    func dismissProposal() async {
        guard let id = pendingProposal?.id else { return }
        pendingProposal = nil
        struct Body: Encodable { let proposalId: String }
        try? await api.post("/api/experts/nutrition/dismiss", Body(proposalId: id))
    }

    func clear() async {
        try? await api.post("/api/experts/nutrition/clear")
        await load()
    }

    private func apply(_ res: ExpertThreadResponse) {
        messages = res.messages ?? []
        chips = res.chips ?? []
        pendingProposal = res.pendingProposal
        consent = res.consent
        if let left = res.remainingKcal { remainingKcal = left }
        if let s = res.stages { stages = s }
        switch res.state {
        case "needs_consent": phase = .consent
        case "ready": phase = .ready
        case "paused", "off": phase = .paused(res.message ?? L10n("This is paused."))
        case "ineligible": phase = .ineligible(res.message ?? "")
        case "locked": phase = .locked(res.message ?? "")
        default: phase = .ready
        }
    }

    private func startStages() {
        let labels = [stages.look, stages.plate, stages.check]
        stageLabel = labels.first
        stageTask?.cancel()
        stageTask = Task {
            var i = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                i = min(i + 1, labels.count - 1)
                stageLabel = labels[i]
            }
        }
    }

    private func stopStages() {
        stageTask?.cancel()
        stageTask = nil
        stageLabel = nil
    }
}

#if DEBUG
extension NutritionAssistantViewModel {
    /// Previews: "chat" (a plate on the table), "empty" (first open), "consent".
    static func previewed(_ state: String) -> NutritionAssistantViewModel {
        let vm = NutritionAssistantViewModel(api: AppEnvironment.preview().api)
        let chips = #"[{"id":"next","title":"What should I eat next?","message":"What should I eat next?"},{"id":"easy","title":"Something easy to get down","message":"I'm not hungry. What's easy to eat?"},{"id":"protein","title":"I need more protein","message":"How do I get more protein today?"},{"id":"dinner","title":"Plan my dinner","message":"Plan my dinner."}]"#
        let json: String
        switch state {
        case "consent":
            json = #"{"state":"needs_consent","consent":{"title":"Meet your nutrition assistant","body":"Ask what to eat and it builds a plate from foods you like, sized to what's left today.","review":"Let SetPoint review this chat to keep it safe.","accept":"Continue","decline":"Not now"}}"#
        case "empty":
            json = #"{"state":"ready","remainingKcal":1240,"messages":[],"chips":"# + chips + "}"
        default:
            json = #"{"state":"ready","remainingKcal":1240,"chips":"# + chips + #","messages":[{"role":"user","content":"I trained this morning and I'm not that hungry. What should I eat for lunch?","at":"2026-10-21T11:02:00Z"},{"role":"assistant","content":"After a morning session your body wants protein and carbs back. Since your appetite is low, go for something soft and easy to eat rather than a big plate. Here's one that fits what's left today:","at":"2026-10-21T11:02:06Z"}],"pendingProposal":{"id":"p1","kind":"MEAL","title":"Easy lunch","summary":"Greek yogurt bowl with granola and banana, plus a chocolate milk.","localDate":"2026-10-21","timezone":"Asia/Jerusalem","expiresAt":"2026-10-21T14:00:00Z","items":[{"slug":"greek-yogurt","name":"Greek yogurt 5%","servingDesc":"1 cup, 250 g","quantity":1,"kcal":240,"proteinG":22,"carbsG":10,"fatG":12},{"slug":"granola","name":"Granola","servingDesc":"½ cup","quantity":1,"kcal":260,"proteinG":6,"carbsG":38,"fatG":9},{"slug":"banana","name":"Banana","servingDesc":"1 medium","quantity":1,"kcal":105,"proteinG":1,"carbsG":27,"fatG":0},{"slug":"choc-milk","name":"Chocolate milk","servingDesc":"1 bottle, 500 ml","quantity":1,"kcal":330,"proteinG":17,"carbsG":52,"fatG":6}],"totals":{"kcal":935,"proteinG":46,"carbsG":127,"fatG":27}}}"#
        }
        if let res = try? JSONDecoder().decode(ExpertThreadResponse.self, from: Data(json.utf8)) {
            vm.apply(res)
        }
        return vm
    }
}
#endif
