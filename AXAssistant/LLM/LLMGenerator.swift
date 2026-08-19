import Foundation
import AXCore
import MLX
import MLXLMCommon

/// Single place that turns ChatMessages into a streamed completion. Used by the agent
/// loop and the debug eval screen.
enum LLMGenerator {
    static func generate(
        container: ModelContainer,
        messages: [ChatMessage],
        maxTokens: Int = 640,
        onPartial: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> String {
        try await container.perform { modelContext in
            let chat = messages.map { message in
                switch message.role {
                case .system: Chat.Message.system(message.content)
                case .user: Chat.Message.user(message.content)
                case .assistant: Chat.Message.assistant(message.content)
                case .tool: Chat.Message.tool(message.content)
                }
            }
            // enable_thinking=false: Qwen3's template otherwise emits a <think> block
            // that can eat the whole token budget before any <tool_call> appears.
            // Templates that don't know the variable ignore it.
            let input = try await modelContext.processor.prepare(
                input: UserInput(chat: chat, additionalContext: ["enable_thinking": false])
            )
            var output = ""
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.2),
                context: modelContext
            )
            let streamStart = Date()
            var timeToFirstToken: TimeInterval?
            var completionInfo: GenerateCompletionInfo?
            for await generation in stream {
                switch generation {
                case .chunk(let chunk):
                    if timeToFirstToken == nil {
                        timeToFirstToken = Date().timeIntervalSince(streamStart)
                    }
                    output += chunk
                    onPartial(output)
                case .info(let info):
                    completionInfo = info
                case .toolCall(let call):
                    // The runtime intercepts well-formed <tool_call> blocks and emits
                    // them as structured events instead of text. Re-serialize so the
                    // AXCore parser validates every call through one path.
                    output += Self.hermesText(for: call)
                    onPartial(output)
                default:
                    break
                }
            }
            if let info = completionInfo {
                let record = GenerationRecord(
                    date: streamStart,
                    modelID: modelContext.configuration.name,
                    promptTokens: info.promptTokenCount,
                    generationTokens: info.generationTokenCount,
                    promptTime: info.promptTime,
                    generateTime: info.generateTime,
                    timeToFirstToken: timeToFirstToken ?? 0,
                    footprintBytes: MetricsStore.processFootprintBytes(),
                    gpuPeakBytes: MLX.GPU.peakMemory
                )
                Task { @MainActor in MetricsStore.shared.record(record) }
            }
            // Release the KV cache and scratch buffers this turn allocated. Without
            // this they accumulate across turns and push a large model past the
            // ~3.4 GB iOS per-process limit → jetsam kill mid-conversation.
            MLX.GPU.clearCache()
            return output
        }
    }

    static func hermesText(for call: MLXLMCommon.ToolCall) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let argsJSON = (try? encoder.encode(call.function.arguments))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "<tool_call>\n{\"name\": \"\(call.function.name)\", \"arguments\": \(argsJSON)}\n</tool_call>"
    }
}
