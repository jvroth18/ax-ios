import Foundation
import Observation
import AVFoundation
import AXCore
import MLXLMCommon

/// One ongoing chat thread. Voice requests and typed messages both land here, so the
/// model keeps context across turns ("what's on my calendar?" … "move the first one").
@Observable @MainActor
final class Conversation {

    struct DisplayMessage: Identifiable, Equatable {
        enum Role { case user, assistant, tool }
        let id = UUID()
        let role: Role
        let text: String
    }

    private(set) var messages: [DisplayMessage] = []
    /// Non-nil while the model is streaming a response.
    private(set) var thinkingPartial: String?

    /// Bridges ConfirmSheet: set here, awaited by the agent loop.
    var pendingConfirmation: (call: ToolCall, spec: ToolSpec, resume: (Bool) -> Void)?

    /// Model-facing history: final user/assistant turns only (tool internals stay out
    /// to preserve the 4k context budget). Trimmed to the most recent exchanges.
    private var history: [ChatMessage] = []
    private static let maxHistoryMessages = 12


    func send(_ text: String, modelManager: ModelManager, appState: AppState) async {
        messages.append(DisplayMessage(role: .user, text: text))

        guard let container = modelManager.container else {
            messages.append(DisplayMessage(role: .assistant, text: "The model isn't loaded yet."))
            return
        }

        appState.mode = .thinking
        thinkingPartial = ""
        defer {
            thinkingPartial = nil
            appState.mode = .idle
        }

        do {
            let turn: AgentLoop.Turn
            if appState.settings.toolsMode {
                let loop = AgentLoop(
                    container: container,
                    registry: .standard,
                    confirmer: self,
                    config: AgentConfig(maxToolIterations: appState.settings.maxToolIterations),
                    profile: PromptProfile.forModel(modelManager.choice.id)
                )
                turn = try await loop.run(history: history, userText: text) { partial in
                    Task { @MainActor [weak self] in self?.thinkingPartial = partial }
                }
            } else {
                // Mode 1 — plain chat: no tool schemas in the prompt, no agent loop.
                turn = try await Self.plainChatTurn(
                    container: container, history: history, userText: text
                ) { partial in
                    Task { @MainActor [weak self] in self?.thinkingPartial = partial }
                }
            }
            for (call, result) in zip(turn.toolCalls, turn.toolResults) {
                messages.append(DisplayMessage(role: .tool, text: "\(call.name) → \(result.content)"))
            }
            if !turn.reply.isEmpty {
                messages.append(DisplayMessage(role: .assistant, text: turn.reply))
            }

            history.append(ChatMessage(role: .user, content: text))
            history.append(ChatMessage(role: .assistant, content: turn.reply))
            if history.count > Self.maxHistoryMessages {
                history.removeFirst(history.count - Self.maxHistoryMessages)
            }

            HistoryStore.record(transcript: text, turn: turn)
            if appState.settings.speakReplies, !turn.reply.isEmpty {
                if appState.settings.useKokoroVoice {
                    let voice = appState.settings.kokoroVoice
                    let reply = turn.reply
                    Task.detached { await KokoroSpeaker.shared.speak(reply, voice: voice) }
                } else {
                    ReplySpeaker.shared.speak(turn.reply)
                }
            }
        } catch {
            messages.append(DisplayMessage(role: .assistant, text: "Something went wrong: \(error.localizedDescription)"))
        }
    }

    func clear() {
        messages = []
        history = []
    }

    /// Mode 1: conversation without the tool machinery — a lean prompt, one
    /// generation, think-blocks stripped.
    private static func plainChatTurn(
        container: ModelContainer,
        history: [ChatMessage],
        userText: String,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> AgentLoop.Turn {
        let system = """
        You are AX, a voice assistant running entirely on the user's iPhone. \
        Give helpful conversational answers; keep spoken-style replies natural. \
        Current date and time: \(AgentLoop.formattedNow())
        """
        var messages: [ChatMessage] = [.init(role: .system, content: system)]
        messages.append(contentsOf: history)
        messages.append(.init(role: .user, content: userText))
        let completion = try await LLMGenerator.generate(
            container: container, messages: messages, onPartial: onPartial
        )
        let reply = (try? ToolCallParser.parse(completion, tools: []))?.text ?? completion
        return AgentLoop.Turn(reply: reply, toolCalls: [], toolResults: [])
    }
}

extension Conversation: AgentLoop.Confirmer {
    func confirm(call: ToolCall, spec: ToolSpec) async -> Bool {
        await withCheckedContinuation { continuation in
            pendingConfirmation = (call, spec, { approved in
                self.pendingConfirmation = nil
                continuation.resume(returning: approved)
            })
        }
    }
}
