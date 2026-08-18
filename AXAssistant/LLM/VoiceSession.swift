import Foundation
import Observation
import AXCore

/// One Action-Button recording: capture → transcribe → hand off to the Conversation.
/// All model work, history, confirmation, and speech output live in Conversation.
@Observable @MainActor
final class VoiceSession {

    enum Phase: Equatable {
        case recording(partial: String)
        case handedOff
        case failed(String)
    }

    private(set) var phase: Phase = .recording(partial: "")
    private(set) var transcript: String = ""

    private let conversation: Conversation
    private let modelManager: ModelManager
    private let appState: AppState
    private let transcriber = Transcriber()
    private var task: Task<Void, Never>?

    init(conversation: Conversation, modelManager: ModelManager, appState: AppState) {
        self.conversation = conversation
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
                phase = .handedOff
                await conversation.send(transcript, modelManager: modelManager, appState: appState)
            } catch {
                phase = .failed(error.localizedDescription)
                appState.mode = .idle
            }
        }
    }

    func cancel() {
        task?.cancel()
        transcriber.stop()
        appState.mode = .idle
    }
}
