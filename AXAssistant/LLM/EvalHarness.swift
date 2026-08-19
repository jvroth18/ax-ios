import Foundation
import AXCore
import MLXLMCommon

/// Golden-transcript eval cases and scoring, shared by the debug eval screen and the
/// debug eval screen. Generation only — no tool execution.
struct EvalCase: Identifiable, Sendable {
    let id = UUID()
    let transcript: String
    let expectedTool: String
    /// Argument keys/values that must appear (string compare; keys only when value is nil).
    let expectedArgs: [String: String?]

    static let golden: [EvalCase] = [
        EvalCase(
            transcript: "Remind me to call mom at 5pm today",
            expectedTool: "create_reminder",
            expectedArgs: ["title": nil, "due": nil]
        ),
        EvalCase(
            transcript: "Put lunch with Sarah on my calendar tomorrow at noon",
            expectedTool: "create_calendar_event",
            expectedArgs: ["title": nil, "start": nil]
        ),
        EvalCase(
            transcript: "What's on my calendar today?",
            expectedTool: "read_next_events",
            expectedArgs: [:]
        ),
        EvalCase(
            transcript: "Turn on the flashlight",
            expectedTool: "toggle_flashlight",
            expectedArgs: ["state": "on"]
        ),
        EvalCase(
            transcript: "Pause the music",
            expectedTool: "play_music",
            expectedArgs: ["action": "pause"]
        ),
        EvalCase(
            transcript: "Set a timer for 10 minutes",
            expectedTool: "set_timer",
            expectedArgs: ["minutes": "10"]
        ),
        EvalCase(
            transcript: "Open Maps",
            expectedTool: "open_app",
            expectedArgs: ["app": "maps"]
        ),
        EvalCase(
            transcript: "What's Dave's phone number?",
            expectedTool: "find_contact",
            expectedArgs: ["name": nil]
        ),
        EvalCase(
            transcript: "Run my Goodnight shortcut",
            expectedTool: "run_shortcut",
            expectedArgs: ["name": "Goodnight"]
        ),
    ]
}

enum EvalHarness {
    enum Outcome: Equatable, Sendable {
        case pass
        case wrongTool(String)
        case wrongArgs(String)
        case noCall(String)
        case error(String)

        var passed: Bool { self == .pass }
        var label: String {
            switch self {
            case .pass: return "pass"
            case .wrongTool(let got): return "wrong tool: \(got)"
            case .wrongArgs(let why): return "args: \(why)"
            case .noCall(let text): return "no call: \(text.prefix(120))"
            case .error(let message): return "error: \(message)"
            }
        }
    }

    @MainActor
    static func systemPrompt() -> String {
        let registry = ToolRegistry.standard
        let context = PromptBuilder.Context(
            currentDateTime: AgentLoop.formattedNow(),
            registeredShortcuts: ["Goodnight"]  // fixed so run_shortcut cases are stable
        )
        return PromptBuilder.systemPrompt(tools: registry.specs, context: context)
    }

    /// Runs one case against a loaded container and scores the completion.
    static func run(
        _ evalCase: EvalCase,
        container: ModelContainer,
        system: String,
        registry: ToolRegistry
    ) async -> Outcome {
        let completion: String
        do {
            completion = try await LLMGenerator.generate(
                container: container,
                messages: [
                    ChatMessage(role: .system, content: system),
                    ChatMessage(role: .user, content: evalCase.transcript),
                ]
            )
        } catch {
            return .error(error.localizedDescription)
        }
        return judge(evalCase, completion: completion, registry: registry)
    }

    static func judge(_ evalCase: EvalCase, completion: String, registry: ToolRegistry) -> Outcome {
        let parsed: ParsedCompletion
        do {
            parsed = try ToolCallParser.parse(completion, tools: registry.specs)
        } catch {
            return .error("parse: \(error)")
        }
        guard let call = parsed.toolCalls.first else { return .noCall(parsed.text) }
        guard call.name == evalCase.expectedTool else { return .wrongTool(call.name) }
        for (key, expected) in evalCase.expectedArgs {
            guard let value = call.arguments[key] else { return .wrongArgs("missing \(key)") }
            if let expected {
                let actual = value.stringValue
                    ?? value.numberValue.map { number in
                        number == number.rounded() ? String(Int(number)) : String(number)
                    }
                    ?? "?"
                if actual.lowercased() != expected.lowercased() {
                    return .wrongArgs("\(key)=\(actual) ≠ \(expected)")
                }
            }
        }
        return .pass
    }
}
