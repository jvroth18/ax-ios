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

    public static func systemPrompt(
        tools: [ToolSpec],
        context: Context,
        profile: PromptProfile = .standard
    ) -> String {
        var lines: [String] = []
        lines.append("""
        You are AX, a voice assistant that runs entirely on the user's iPhone. \
        You receive a transcribed spoken request and either answer directly or call a tool.

        Current date and time: \(context.currentDateTime)
        """)

        if !context.registeredShortcuts.isEmpty {
            lines.append("Shortcuts the user has registered for run_shortcut: " +
                         context.registeredShortcuts.map { "\"\($0)\"" }.joined(separator: ", ") +
                         ". Only call run_shortcut when the user explicitly asks to run a shortcut" +
                         " — for reminders, timers, and other requests use the matching tool instead.")
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
        """)

        if profile.includeWorkedExample {
            lines.append("""
            Example — the user says "Turn off the flashlight" and you reply with exactly:
            <tool_call>
            {"name": "toggle_flashlight", "arguments": {"state": "off"}}
            </tool_call>
            """)
        }

        if profile.includeWorkflowGuidance {
            var workflow = """
            # Repetition

            When a request repeats an action ("ten times", "back and forth", "with a pause \
            between"), do NOT emit the same call over and over — call repeat_steps once and \
            let it run the whole sequence. Use wait for a pause between actions.
            """
            if profile.includeWorkflowExample {
                workflow += """


                Example — "flash the light on and off ten times, pausing in between":
                <tool_call>
                {"name": "repeat_steps", "arguments": {"steps": "toggle_flashlight:on, wait:0.5, toggle_flashlight:off, wait:0.5", "times": 10}}
                </tool_call>

                Anything the workflow can't cover — an action needing confirmation, or one \
                with more than one argument — you call directly, in a later step.
                """
            }
            lines.append(workflow)
        }

        lines.append("""
        Rules:
        - When a tool fits, ALWAYS reply with a <tool_call> block as shown — \
        never with an empty message, and never with the tool name outside the JSON.
        - Write every date-time as absolute local ISO 8601 with NO timezone suffix: \
        "YYYY-MM-DDTHH:MM:SS" (e.g. 2026-08-17T17:00:00), meaning the user's own clock. \
        Resolve "tomorrow at 9" against the current date above; use "YYYY-MM-DD" on its \
        own when the user gave a day but no time. Never write a relative phrase as an argument.
        - "Remind me…" requests are create_reminder, never set_timer — timers are only for \
        counting down a duration ("set a timer for 10 minutes").
        - If the request is ambiguous, ask a short clarifying question instead of guessing.
        - If no tool fits, answer briefly in plain language. Keep spoken-style answers to one or two sentences.
        - Never invent tool names or shortcut names that are not listed.
        """)

        if !profile.extraRules.isEmpty {
            lines.append(profile.extraRules.map { "- \($0)" }.joined(separator: "\n"))
        }

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
