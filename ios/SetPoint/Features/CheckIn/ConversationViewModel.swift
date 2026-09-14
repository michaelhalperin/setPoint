import Foundation
import Observation

/// The tier-3 "let's talk" conversation (§2). Bounded on the server — it lands on
/// an `outcome` (adjust the plan, pause check-ins, or point to support) and then
/// `resolved` closes the composer.
@MainActor
@Observable
final class ConversationViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var messages: [ConversationMessage] = []
    private(set) var outcome = "NONE"
    private(set) var resolved = false
    var draft = ""
    private(set) var sending = false
    private(set) var sendError: String?
    private(set) var pendingProposal: ConversationResponse.PlanProposal?
    private(set) var confirming = false

    let checkInID: String
    private let api: APIClient

    init(checkInID: String, api: APIClient) {
        self.checkInID = checkInID
        self.api = api
    }

    func load() async {
        phase = .loading
        do {
            let res: ConversationResponse = try await api.get("/api/checkins/\(checkInID)/conversation")
            apply(res)
            phase = .ready
        } catch {
            phase = .failed(UserFacingError.message(for: error, fallback: "Couldn't load. Try again."))
        }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending, !resolved else { return }
        sending = true
        sendError = nil
        defer { sending = false }

        draft = ""
        messages.append(ConversationMessage(role: "user", content: text, at: nil))

        do {
            let res: ConversationResponse = try await api.post(
                "/api/checkins/\(checkInID)/conversation",
                ConversationRequest(message: text)
            )
            apply(res)
        } catch {
            messages.removeAll { $0.role == "user" && $0.content == text && $0.at == nil }
            draft = text
            sendError = UserFacingError.message(for: error, fallback: "Couldn't send. Try again.")
        }
    }

    func confirmProposal() async {
        guard let kind = pendingProposal?.kind, !confirming else { return }
        confirming = true
        sendError = nil
        defer { confirming = false }
        do {
            struct Body: Encodable { let kind: String }
            let res: ConversationConfirmResponse = try await api.post(
                "/api/checkins/\(checkInID)/conversation/confirm",
                Body(kind: kind)
            )
            outcome = res.outcome
            resolved = res.resolved
            pendingProposal = nil
        } catch {
            sendError = UserFacingError.message(for: error, fallback: "Couldn't apply that change.")
        }
    }

    /// A short line describing where the conversation landed (shown once resolved).
    var outcomeSummary: String? {
        switch outcome {
        case "ADJUST_PLAN", "EASE_TARGET": return "Target lowered. Undo anytime in Goal settings."
        case "DELAY_CHECKINS": return "Meal times shifted 30 minutes later."
        case "PAUSE_CHECKINS": return "Resume anytime in Settings."
        case "SUGGEST_PROFESSIONAL": return "Check-ins paused. Resume anytime in Settings."
        default: return resolved ? "Done." : nil
        }
    }

    var outcomeTitle: String {
        switch outcome {
        case "ADJUST_PLAN", "EASE_TARGET": return "Plan eased"
        case "DELAY_CHECKINS": return "Check-ins moved later"
        case "PAUSE_CHECKINS": return "Check-ins paused"
        case "SUGGEST_PROFESSIONAL": return "Extra support"
        default: return "Sorted"
        }
    }

    var outcomeIcon: String {
        switch outcome {
        case "ADJUST_PLAN", "EASE_TARGET": return "slider.horizontal.3"
        case "DELAY_CHECKINS": return "clock"
        case "PAUSE_CHECKINS": return "pause.circle"
        case "SUGGEST_PROFESSIONAL": return "heart.text.square"
        default: return "checkmark.circle"
        }
    }

    private func apply(_ res: ConversationResponse) {
        messages = res.messages
        outcome = res.outcome
        resolved = res.resolved
        pendingProposal = res.pendingProposal
    }

    #if DEBUG
    static func previewed(resolved: Bool) -> ConversationViewModel {
        let vm = ConversationViewModel(checkInID: "ci_preview", api: AppEnvironment.preview().api)
        vm.messages = [
            ConversationMessage(role: "assistant", content: "A few check-ins in a row didn’t land. What would help?", at: nil),
        ]
        if resolved {
            vm.messages.append(ConversationMessage(role: "user", content: "work has been nuts, I keep missing lunch", at: nil))
            vm.messages.append(ConversationMessage(role: "assistant", content: "Let's push your check-ins later and ease the target for this week. You can fine-tune it in Settings.", at: nil))
            vm.outcome = "ADJUST_PLAN"
            vm.resolved = true
        }
        vm.phase = .ready
        return vm
    }
    #endif
}
