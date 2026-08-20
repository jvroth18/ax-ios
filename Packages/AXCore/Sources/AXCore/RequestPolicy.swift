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
}
