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
            phase = .failed(Self.message(error))
        }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending, !resolved else { return }
        sending = true
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
            phase = .failed(Self.message(error))
        }
    }

    /// A short line describing where the conversation landed (shown once resolved).
    var outcomeSummary: String? {
        switch outcome {
        case "ADJUST_PLAN": return "We'll ease the plan. Fine-tune it in Settings."
        case "PAUSE_CHECKINS": return "Check-ins are paused. Turn them back on in Settings anytime."
        case "SUGGEST_PROFESSIONAL": return "SetPoint will keep tracking quietly. Talking to a professional can really help."
        default: return resolved ? "Thanks for talking it through." : nil
        }
    }

    var outcomeTitle: String {
        switch outcome {
        case "ADJUST_PLAN": return "Plan eased"
        case "PAUSE_CHECKINS": return "Check-ins paused"
        case "SUGGEST_PROFESSIONAL": return "Extra support"
        default: return "Sorted"
        }
    }

    var outcomeIcon: String {
        switch outcome {
        case "ADJUST_PLAN": return "slider.horizontal.3"
        case "PAUSE_CHECKINS": return "pause.circle"
        case "SUGGEST_PROFESSIONAL": return "heart.text.square"
        default: return "checkmark.circle"
        }
    }

    private func apply(_ res: ConversationResponse) {
        messages = res.messages
        outcome = res.outcome
        resolved = res.resolved
    }

    private static func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
    }

    #if DEBUG
    static func previewed(resolved: Bool) -> ConversationViewModel {
        let vm = ConversationViewModel(checkInID: "ci_preview", api: AppEnvironment.preview().api)
        vm.messages = [
            ConversationMessage(role: "assistant", content: "The last few days haven't gone to plan. Want to lower the target, shift your check-ins, or pause them for a bit?", at: nil),
            ConversationMessage(role: "user", content: "work has been nuts, I keep missing lunch", at: nil),
        ]
        if resolved {
            vm.messages.append(ConversationMessage(role: "assistant", content: "Let's push your check-ins later and ease the target for this week. You can fine-tune it in Settings.", at: nil))
            vm.outcome = "ADJUST_PLAN"
            vm.resolved = true
        }
        vm.phase = .ready
        return vm
    }
    #endif
}
