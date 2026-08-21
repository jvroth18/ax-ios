import Foundation

/// Builds the system prompt (Hermes/Qwen tool-calling convention) and tool-response turns.
public enum PromptBuilder {

    /// Context injected into the system prompt so the model can resolve relative dates
    /// and knows which user Shortcuts it may call.
    public struct Context: Sendable {
        public let currentDateTime: String   // e.g. "Monday 2026-08-17 14:03, America/New_York"
        public let registeredShortcuts: [String]
        /// Durable facts the user has told the assistant. Kept short deliberately: every
        /// one of these is re-read on every generation.
        public let memories: [String]

        public init(
            currentDateTime: String,
            registeredShortcuts: [String] = [],
            memories: [String] = []
        ) {
            self.currentDateTime = currentDateTime
            self.registeredShortcuts = registeredShortcuts
            self.memories = memories
        }
    }

    public static func systemPrompt(
        tools: [ToolSpec],
        context: Context,
        profile: PromptProfile = .standard
    ) -> String {
        var lines: [String] = []
        lines.append("""
        You are Morse, a voice assistant that runs entirely on the user's iPhone. \
        You receive a transcribed spoken request and either answer directly or call a tool.

        Current date and time: \(context.currentDateTime)
        """)

        if !context.memories.isEmpty {
            lines.append("""
            What you know about the user:
            \(context.memories.map { "- \($0)" }.joined(separator: "\n"))
            """)
        }

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

        if tools.contains(where: { $0.name == "signal_morse_code" }) {
            lines.append("""
            # Morse signaling

            ONLY call signal_morse_code when the user's request explicitly asks for Morse \
            code or dot-and-dash flashlight signaling. Never use it for ordinary text, \
            greetings, explanations, or creative requests. When it does apply, pass only \
            the source message being converted — strip command words such as "turn", \
            "signal", and "into Morse code". Do not translate the source into dots and \
            dashes yourself; the tool performs exact encoding and flashlight timing.

            Example — "Use the flashlight to signal SOS in Morse code":
            <tool_call>
            {"name": "signal_morse_code", "arguments": {"text": "SOS"}}
            </tool_call>

            Example — "Turn Meet at 5 into Morse code":
            <tool_call>
            {"name": "signal_morse_code", "arguments": {"text": "Meet at 5"}}
            </tool_call>

            Counterexample — "Tell me a joke about penguins" has no Morse request, so \
            answer with a joke in plain language and do not call signal_morse_code.
            """)
        }

        if profile.includeWorkflowGuidance {
            var workflow = """
            # Repetition

            When a request repeats an action ("ten times", "back and forth", "with a pause \
            between"), do NOT emit the same call over and over — call repeat_steps once and \
            let it run the whole sequence. Use wait for a pause between actions.

            You may also use repeat_steps with times=1 for an ordered sequence of safe \
            one-argument tools. Put each action in `steps` in the user's exact order.

            A successful repeat_steps result means every inner step and repetition already \
            finished. NEVER call an inner tool from that completed workflow again. If the \
            original request said "and then" another action, call only that next action.
            """
            if profile.includeWorkflowExample {
                workflow += """


                Example — "flash the light on and off ten times, pausing in between":
                <tool_call>
                {"name": "repeat_steps", "arguments": {"steps": "toggle_flashlight:on, wait:0.5, toggle_flashlight:off, wait:0.5", "times": 10}}
                </tool_call>

                Anything the workflow can't cover — an action needing confirmation, or one \
                with more than one argument — you call directly, in a later step.

                Example — "Turn the flashlight on and off 5 times":
                <tool_call>
                {"name": "repeat_steps", "arguments": {"steps": "toggle_flashlight:on, wait:0.25, toggle_flashlight:off, wait:0.25", "times": 5}}
                </tool_call>

                Example — "Blink the flashlight 10 times, then call 6316452763":
                <tool_call>
                {"name": "repeat_steps", "arguments": {"steps": "toggle_flashlight:on, wait:0.25, toggle_flashlight:off, wait:0.25", "times": 10}}
                </tool_call>
                <tool_call>
                {"name": "call_number", "arguments": {"number": "6316452763"}}
                </tool_call>

                Example — "Turn on the flashlight, then pause the music, then set a timer for 2 minutes":
                <tool_call>
                {"name": "repeat_steps", "arguments": {"steps": "toggle_flashlight:on, play_music:pause, set_timer:2", "times": 1}}
                </tool_call>
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
        - Greetings and small talk never use a tool. "Hi", "hello", and "hey" get a short plain-language reply.
        - For an explicitly repeated sequence, generate one repeat_steps call. Put one full cycle in "steps" and the requested repetition count in "times".
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
