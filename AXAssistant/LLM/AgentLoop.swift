import Foundation
import AXCore
import MLXLMCommon

/// Runs the transcribe → generate → execute-tool → feed-back loop against the loaded model.
///
/// The loop is bounded by AgentConfig.maxToolIterations, which caps how many times the
/// model may hand control back to a tool. A tool call on the last allowed iteration is
/// still executed — there's just no generation left to phrase the outcome, so the tool's
/// own result text is spoken instead. `.confirm`-risk tools suspend the loop until the
/// user approves or rejects via the ConfirmSheet (see `Confirmer`).
struct AgentLoop {

    /// UI hook that presents ConfirmSheet and resumes with the user's decision.
    protocol Confirmer {
        @MainActor func confirm(call: ToolCall, spec: ToolSpec) async -> Bool
    }

    let container: ModelContainer
    let registry: ToolRegistry
    let confirmer: any Confirmer
    var config = AgentConfig()
    /// Per-model prompt tuning. Defaults to the one-size prompt every model used to get.
    var profile: PromptProfile = .standard

    struct Turn {
        let reply: String
        let toolCalls: [ToolCall]
        let toolResults: [ToolResult]
    }

    func run(
        history: [ChatMessage] = [],
        userText: String,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> Turn {
        let context = PromptBuilder.Context(
            currentDateTime: Self.formattedNow(),
            registeredShortcuts: await MainActor.run { AppState.shared.settings.registeredShortcuts }
        )
        var messages: [ChatMessage] = [
            .init(role: .system, content: PromptBuilder.systemPrompt(
                tools: registry.specs, context: context, profile: profile
            ))
        ]
        messages.append(contentsOf: history)
        messages.append(.init(role: .user, content: userText))

        var allCalls: [ToolCall] = []
        var allResults: [ToolResult] = []

        for iteration in 0...config.maxToolIterations {
            let completion = try await generate(messages: messages, onPartial: onPartial)

            let parsed: ParsedCompletion
            do {
                parsed = try ToolCallParser.parse(completion, tools: registry.specs)
            } catch {
                // Malformed call: tell the model what went wrong and let it retry once.
                if iteration < config.maxToolIterations {
                    messages.append(.init(role: .assistant, content: completion))
                    messages.append(.init(
                        role: .tool,
                        content: PromptBuilder.toolResponse(.failure("Invalid tool call: \(error)"))
                    ))
                    continue
                }
                // Out of retries: surface whatever the model said as a plain reply
                // instead of erroring the turn. Weak/finetuned models emit broken
                // calls often; the user should still see the response.
                let fallback = completion.isEmpty
                    ? "(The model didn't produce a usable reply — try rephrasing, or switch models.)"
                    : completion
                return Turn(reply: fallback, toolCalls: allCalls, toolResults: allResults)
            }

            guard !parsed.toolCalls.isEmpty else {
                return Turn(reply: parsed.text, toolCalls: allCalls, toolResults: allResults)
            }

            // On the last allowed iteration the model asked for another tool instead of
            // answering. Run it anyway: dropping it would silently do nothing, and
            // `parsed.text` is empty here (the parser strips the <tool_call> block), so
            // returning it hands the user a blank reply — the two failures compound into
            // "the button did nothing". There's no budget left for the model to phrase
            // the outcome, so the tools' own result text becomes the answer, exactly as
            // for `endsTurn` tools below.
            let isFinalIteration = iteration == config.maxToolIterations
            let resultsBefore = allResults.count

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

            if isFinalIteration {
                return Turn(
                    reply: Self.finalIterationReply(
                        modelText: parsed.text,
                        results: Array(allResults[resultsBefore...])
                    ),
                    toolCalls: allCalls,
                    toolResults: allResults
                )
            }
        }

        // Unreachable: `0...maxToolIterations` always has at least one element and the
        // final iteration always returns above. Swift still needs a value here; make it
        // an honest one rather than the empty string that used to sit here, which the UI
        // renders as no reply at all.
        return Turn(
            reply: "I couldn't finish that one — try asking again.",
            toolCalls: allCalls,
            toolResults: allResults
        )
    }

    /// What to say when the iteration budget ran out on a turn that still called tools.
    /// The calls have already run, so report what they did; only claim nothing happened
    /// when there is genuinely nothing to report.
    private static func finalIterationReply(modelText: String, results: [ToolResult]) -> String {
        let spoken = modelText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !spoken.isEmpty { return spoken }
        let contents = results.map(\.content).filter { !$0.isEmpty }
        guard !contents.isEmpty else {
            return "That needed more steps than I'm allowed to take in one go — try asking for one thing at a time."
        }
        return contents.joined(separator: " ")
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
