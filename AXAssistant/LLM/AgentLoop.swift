import Foundation
import AXCore
import MLXLMCommon

/// Runs the transcribe → generate → execute-tool → feed-back loop against the loaded model.
///
/// The loop is bounded by AgentConfig.maxToolIterations. `.confirm`-risk tools suspend the
/// loop until the user approves or rejects via the ConfirmSheet (see `Confirmer`).
struct AgentLoop {

    /// UI hook that presents ConfirmSheet and resumes with the user's decision.
    protocol Confirmer {
        @MainActor func confirm(call: ToolCall, spec: ToolSpec) async -> Bool
    }

    let container: ModelContainer
    let registry: ToolRegistry
    let confirmer: any Confirmer
    let config = AgentConfig()

    struct Turn {
        let reply: String
        let toolCalls: [ToolCall]
        let toolResults: [ToolResult]
    }

    func run(userText: String, onPartial: @escaping @Sendable (String) -> Void) async throws -> Turn {
        let context = PromptBuilder.Context(
            currentDateTime: Self.formattedNow(),
            registeredShortcuts: await MainActor.run { AppState.shared.settings.registeredShortcuts }
        )
        var messages: [ChatMessage] = [
            .init(role: .system, content: PromptBuilder.systemPrompt(tools: registry.specs, context: context)),
            .init(role: .user, content: userText),
        ]

        var allCalls: [ToolCall] = []
        var allResults: [ToolResult] = []

        for iteration in 0...config.maxToolIterations {
            let completion = try await generate(messages: messages, onPartial: onPartial)

            let parsed: ParsedCompletion
            do {
                parsed = try ToolCallParser.parse(completion, tools: registry.specs)
            } catch {
                // Malformed call: tell the model what went wrong and let it retry once.
                guard iteration < config.maxToolIterations else { throw error }
                messages.append(.init(role: .assistant, content: completion))
                messages.append(.init(
                    role: .tool,
                    content: PromptBuilder.toolResponse(.failure("Invalid tool call: \(error)"))
                ))
                continue
            }

            guard !parsed.toolCalls.isEmpty, iteration < config.maxToolIterations else {
                return Turn(reply: parsed.text, toolCalls: allCalls, toolResults: allResults)
            }

            messages.append(.init(role: .assistant, content: completion))
            for call in parsed.toolCalls {
                let result = await execute(call)
                allCalls.append(call)
                allResults.append(result)
                // Turn-ending tools (e.g. summarize_app, which swaps models in memory)
                // speak their result directly instead of another model round-trip.
                if let tool = registry.tool(named: call.name), tool.endsTurn, result.success {
                    return Turn(reply: result.content, toolCalls: allCalls, toolResults: allResults)
                }
                messages.append(.init(role: .tool, content: PromptBuilder.toolResponse(result)))
            }
        }

        return Turn(reply: "", toolCalls: allCalls, toolResults: allResults)
    }

    private func execute(_ call: ToolCall) async -> ToolResult {
        guard let tool = registry.tool(named: call.name) else {
            return .failure("Unknown tool \(call.name)")
        }
        if tool.spec.risk == .confirm {
            let approved = await confirmer.confirm(call: call, spec: tool.spec)
            guard approved else { return .failure("The user declined this action.") }
        }
        do {
            return try await tool.run(call)
        } catch {
            return .failure("\(call.name) failed: \(error.localizedDescription)")
        }
    }

    private func generate(
        messages: [ChatMessage],
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await LLMGenerator.generate(container: container, messages: messages, onPartial: onPartial)
    }

    static func formattedNow() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE yyyy-MM-dd HH:mm"
        return "\(formatter.string(from: Date())), \(TimeZone.current.identifier)"
    }
}
