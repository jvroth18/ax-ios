#if DEBUG
import SwiftUI
import AXCore

/// Golden-transcript eval: canned spoken requests with the tool call we expect the model
/// to choose. Runs generation only (no tool execution) and scores tool-name + argument
/// matches. Use this after prompt or model changes to catch tool-selection regressions.
struct EvalCase: Identifiable {
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

struct EvalView: View {
    let modelManager: ModelManager

    enum Outcome: Equatable {
        case pending, running
        case pass
        case wrongTool(String)
        case wrongArgs(String)
        case noCall(String)
        case error(String)
    }

    @State private var outcomes: [UUID: Outcome] = [:]
    @State private var running = false

    var body: some View {
        List {
            Section {
                Button(running ? "Running…" : "Run all") { Task { await runAll() } }
                    .disabled(running || modelManager.container == nil)
                if let score {
                    Text("Score: \(score.passed)/\(score.total)")
                        .font(.headline)
                }
            }
            Section("Cases") {
                ForEach(EvalCase.golden) { evalCase in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("“\(evalCase.transcript)”")
                        Text("expects \(evalCase.expectedTool)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        outcomeLabel(outcomes[evalCase.id] ?? .pending)
                    }
                }
            }
        }
        .navigationTitle("Tool-call eval")
    }

    private var score: (passed: Int, total: Int)? {
        let finished = outcomes.values.filter { $0 != .pending && $0 != .running }
        guard finished.count == EvalCase.golden.count else { return nil }
        return (finished.filter { $0 == .pass }.count, finished.count)
    }

    @ViewBuilder
    private func outcomeLabel(_ outcome: Outcome) -> some View {
        switch outcome {
        case .pending: Label("pending", systemImage: "circle.dotted").foregroundStyle(.tertiary)
        case .running: ProgressView()
        case .pass: Label("pass", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .wrongTool(let got): Label("wrong tool: \(got)", systemImage: "xmark.circle").foregroundStyle(.red)
        case .wrongArgs(let why): Label("args: \(why)", systemImage: "xmark.circle").foregroundStyle(.orange)
        case .noCall(let text): Label("no call: \(text.prefix(60))", systemImage: "xmark.circle").foregroundStyle(.red)
        case .error(let message): Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
    }

    private func runAll() async {
        guard let container = modelManager.container else { return }
        running = true
        defer { running = false }

        let registry = ToolRegistry.standard
        let context = PromptBuilder.Context(
            currentDateTime: AgentLoop.formattedNow(),
            registeredShortcuts: ["Goodnight"]  // fixed so run_shortcut cases are stable
        )
        let system = PromptBuilder.systemPrompt(tools: registry.specs, context: context)

        for evalCase in EvalCase.golden {
            outcomes[evalCase.id] = .running
            do {
                let completion = try await LLMGenerator.generate(
                    container: container,
                    messages: [
                        ChatMessage(role: .system, content: system),
                        ChatMessage(role: .user, content: evalCase.transcript),
                    ]
                )
                outcomes[evalCase.id] = judge(evalCase, completion: completion, registry: registry)
            } catch {
                outcomes[evalCase.id] = .error(error.localizedDescription)
            }
        }
    }

    private func judge(_ evalCase: EvalCase, completion: String, registry: ToolRegistry) -> Outcome {
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
            if let expected, value.stringValue?.lowercased() != expected.lowercased() {
                return .wrongArgs("\(key)=\(value.stringValue ?? "?") ≠ \(expected)")
            }
        }
        return .pass
    }
}
#endif
