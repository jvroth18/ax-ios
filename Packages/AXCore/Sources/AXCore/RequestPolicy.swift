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
        let tokens = request.lowercased().split { !$0.isLetter }.map(String.init)
        let words = Set(tokens)
        switch name {
        case "compose_message":
            // "Tell me a joke" and "write me a poem" are conversation, not permission
            // to open Messages. "Explain this error message" uses the same noun, so
            // `message` only authorizes when it is clearly used as the request's verb.
            if !words.isDisjoint(with: ["text", "send", "sms"]) { return true }
            guard let index = tokens.firstIndex(of: "message") else { return false }
            return index == 0 || ["please", "you"].contains(tokens[index - 1])
        case "call_number":
            return !words.isDisjoint(with: ["call", "dial", "ring"])
        case "signal_morse_code":
            // A text-shaped argument makes this tool tempting to small models. Require
            // the user's own request to name Morse (or the equivalent dot/dash signal),
            // so a joke or explanation can never flash the hardware by accident.
            if words.contains("morse") { return true }
            return words.contains("flashlight")
                && words.contains("signal")
                && words.contains("dots")
                && words.contains("dashes")
        default:
            return true
        }
    }
}
