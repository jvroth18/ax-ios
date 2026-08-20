import Foundation
import AXCore

/// Lets the model write a durable fact about the user.
///
/// Scoped to things the user stated about themselves — names, preferences, routines — and
/// explicitly not to transient task content, because a memory that fills with "wants a
/// timer for pasta" stops being useful within a day and costs prompt budget forever.
struct RememberTool: AXTool {
    let spec = ToolSpec(
        name: "remember",
        description: """
        Save a durable fact the user told you about themselves — a relationship ("mom is \
        Sarah Chen"), a preference, or a routine. Use it only when the user states \
        something worth knowing next week; never for the details of the current task.
        """,
        parameters: JSONSchema(
            type: .object,
            properties: [
                "fact": JSONSchema(
                    type: .string,
                    description: "One short sentence, written so it makes sense on its own"
                ),
            ],
            required: ["fact"]
        ),
        risk: .safe
    )

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let fact = call.string("fact"), !fact.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AXToolError.missingArgument("fact")
        }
        let stored = await MainActor.run { UserMemoryStore.shared.remember(fact) }
        return .ok(stored ? "Got it — I'll remember that." : "I already knew that.")
    }
}
