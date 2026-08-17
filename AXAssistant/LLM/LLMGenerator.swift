import Foundation
import AXCore
import MLXLMCommon

/// Single place that turns ChatMessages into a streamed completion. Used by the agent
/// loop and the debug eval screen.
enum LLMGenerator {
    static func generate(
        container: ModelContainer,
        messages: [ChatMessage],
        maxTokens: Int = 512,
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
            let input = try await modelContext.processor.prepare(input: UserInput(chat: chat))
            var output = ""
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.2),
                context: modelContext
            )
            for await generation in stream {
                if case .chunk(let chunk) = generation {
                    output += chunk
                    onPartial(output)
                }
            }
            return output
        }
    }
}
