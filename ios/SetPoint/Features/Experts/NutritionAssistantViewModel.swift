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
        guard let id = pendingProposal?.id, !confirming else { return }
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
