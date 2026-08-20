import Foundation

/// Deterministic handling for requests where allowing a small model to guess at a tool
/// is strictly worse than answering directly.
public enum RequestPolicy {
    /// A standalone greeting never authorizes an action. Keep this deliberately narrow:
    /// "Hi, text Sam" must still reach the agent and execute the requested workflow.
    public static func directReply(for request: String) -> String? {
        let normalized = request
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let greetings: Set<String> = [
            "hi", "hello", "hey", "hi there", "hello there", "hey there",
            "good morning", "good afternoon", "good evening",
        ]
        guard greetings.contains(normalized) else { return nil }
        return "Hi! What can I help you with?"
    }

    /// Models may propose tools; only the user's words authorize consequential intent.
    /// This is intentionally stricter for communication tools because an accidental
    /// draft is confusing even though iOS still requires the user to tap Send.
    public static func allows(tool name: String, for request: String) -> Bool {
        let words = Set(request.lowercased().split { !$0.isLetter }.map(String.init))
        switch name {
        case "compose_message":
            return !words.isDisjoint(with: ["text", "message", "send", "tell", "write"])
        case "call_number":
            return !words.isDisjoint(with: ["call", "dial", "phone", "ring"])
        default:
            return true
        }
    }
}
