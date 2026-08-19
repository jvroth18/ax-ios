import Foundation
import Observation
import AVFoundation
import AXCore

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

        let loop = AgentLoop(
            container: container,
            registry: .standard,
            confirmer: self,
            config: AgentConfig(maxToolIterations: appState.settings.maxToolIterations)
        )
        do {
            let turn = try await loop.run(history: history, userText: text) { partial in
                Task { @MainActor [weak self] in self?.thinkingPartial = partial }
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
