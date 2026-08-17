import Foundation
import Observation
import AXCore
import AVFoundation

/// One Action-Button interaction: record → transcribe → agent loop → (optionally) speak.
@Observable @MainActor
final class VoiceSession {

    enum Phase: Equatable {
        case recording(partial: String)
        case thinking(partial: String)
        case done(reply: String)
        case failed(String)
    }

    private(set) var phase: Phase = .recording(partial: "")
    var transcript: String = ""

    private let modelManager: ModelManager
    private let appState: AppState
    private let transcriber = Transcriber()
    private let synthesizer = AVSpeechSynthesizer()
    private var task: Task<Void, Never>?

    /// Bridges ConfirmSheet: set by ChatView, awaited by the agent loop.
    var pendingConfirmation: (call: ToolCall, spec: ToolSpec, resume: (Bool) -> Void)?

    init(modelManager: ModelManager, appState: AppState) {
        self.modelManager = modelManager
        self.appState = appState
    }

    func start() {
        appState.mode = .listening
        task = Task {
            do {
                for try await update in transcriber.transcribe(
                    silenceTimeout: appState.settings.silenceTimeout
                ) {
                    transcript = update.text
                    phase = .recording(partial: update.text)
                }
                guard !transcript.isEmpty else {
                    phase = .failed("I didn't catch anything.")
                    appState.mode = .idle
                    return
                }
                try await respond(to: transcript)
            } catch {
                phase = .failed(error.localizedDescription)
                appState.mode = .idle
            }
        }
    }

    func respond(to text: String) async throws {
        appState.mode = .thinking
        phase = .thinking(partial: "")

        guard let container = modelManager.container else {
            throw NSError(domain: "AX", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }
        let loop = AgentLoop(container: container, registry: .standard, confirmer: self)
        let turn = try await loop.run(userText: text) { partial in
            Task { @MainActor [weak self] in self?.phase = .thinking(partial: partial) }
        }

        phase = .done(reply: turn.reply)
        appState.mode = .idle
        HistoryStore.record(transcript: text, turn: turn)

        if appState.settings.speakReplies, !turn.reply.isEmpty {
            synthesizer.speak(AVSpeechUtterance(string: turn.reply))
        }
    }

    func cancel() {
        task?.cancel()
        transcriber.stop()
        appState.mode = .idle
    }
}

extension VoiceSession: AgentLoop.Confirmer {
    func confirm(call: ToolCall, spec: ToolSpec) async -> Bool {
        appState.mode = .awaitingConfirmation
        return await withCheckedContinuation { continuation in
            pendingConfirmation = (call, spec, { approved in
                self.pendingConfirmation = nil
                self.appState.mode = .thinking
                continuation.resume(returning: approved)
            })
        }
    }
}
