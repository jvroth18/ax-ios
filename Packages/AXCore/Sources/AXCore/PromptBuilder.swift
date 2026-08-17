import Foundation

/// Builds the system prompt (Hermes/Qwen tool-calling convention) and tool-response turns.
public enum PromptBuilder {

    /// Context injected into the system prompt so the model can resolve relative dates
    /// and knows which user Shortcuts it may call.
    public struct Context: Sendable {
        public let currentDateTime: String   // e.g. "Monday 2026-08-17 14:03, America/New_York"
        public let registeredShortcuts: [String]

        public init(currentDateTime: String, registeredShortcuts: [String] = []) {
            self.currentDateTime = currentDateTime
            self.registeredShortcuts = registeredShortcuts
        }
    }

    public static func systemPrompt(tools: [ToolSpec], context: Context) -> String {
        var lines: [String] = []
        lines.append("""
        You are AX, a voice assistant that runs entirely on the user's iPhone. \
        You receive a transcribed spoken request and either answer directly or call a tool.

        Current date and time: \(context.currentDateTime)
        """)

        if !context.registeredShortcuts.isEmpty {
            lines.append("Shortcuts the user has registered for run_shortcut: " +
                         context.registeredShortcuts.map { "\"\($0)\"" }.joined(separator: ", "))
        }

        lines.append("""
        # Tools

        You may call one or more functions to assist with the user request.
        You are provided with function signatures within <tools></tools> XML tags:
        <tools>
        \(tools.map { toolJSON($0) }.joined(separator: "\n"))
        </tools>

        For each function call, return a json object with function name and arguments \
        within <tool_call></tool_call> XML tags:
        <tool_call>
        {"name": <function-name>, "arguments": <args-json-object>}
        </tool_call>

        Rules:
        - Use absolute ISO 8601 date-times (resolve "tomorrow at 9" using the current date above).
        - If the request is ambiguous, ask a short clarifying question instead of guessing.
        - If no tool fits, answer briefly in plain language. Keep spoken-style answers to one or two sentences.
        - Never invent tool names or shortcut names that are not listed.
        """)

        return lines.joined(separator: "\n\n")
    }

    /// Formats a tool's result as the `<tool_response>` turn fed back to the model.
    public static func toolResponse(_ result: ToolResult) -> String {
        let payload = ["success": JSONValue.bool(result.success), "content": JSONValue.string(result.content)]
        return "<tool_response>\n\(encodeJSON(payload))\n</tool_response>"
    }

    // MARK: - Encoding

    private static func toolJSON(_ tool: ToolSpec) -> String {
        // Standard Hermes format: {"type": "function", "function": {...}}
        struct Function: Encodable {
            let name: String
            let description: String
            let parameters: JSONSchema
        }
        struct Entry: Encodable {
            let type = "function"
            let function: Function
        }
        let entry = Entry(function: Function(
            name: tool.name, description: tool.description, parameters: tool.parameters
        ))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(entry), let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private static func encodeJSON(_ object: [String: JSONValue]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(object), let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
