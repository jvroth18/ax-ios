import Foundation
import Speech

/// On-device speech-to-text using the iOS 26 SpeechAnalyzer / SpeechTranscriber API.
/// The OS downloads and manages the locale's transcription model via AssetInventory —
/// nothing ships in the app bundle and no audio ever leaves the device.
final class Transcriber {

    struct Update {
        let text: String
        let isFinal: Bool
    }

    private let recorder = AudioRecorder()
    private var analyzer: SpeechAnalyzer?
    private var silenceTask: Task<Void, Never>?

    /// Ensures the current locale's transcription asset is installed (one-time prompt-free
    /// system download; call from onboarding and before first use).
    static func ensureAssetsInstalled() async throws {
        let transcriber = SpeechTranscriber(locale: .current, preset: .progressiveLiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    /// Streams live transcription updates. Finishes after `silenceTimeout` seconds of
    /// near-silence following the first speech, or when `stop()` is called.
    func transcribe(silenceTimeout: TimeInterval) -> AsyncThrowingStream<Update, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let transcriber = SpeechTranscriber(
                        locale: .current,
                        preset: .progressiveLiveTranscription
                    )
                    let analyzer = SpeechAnalyzer(modules: [transcriber])
                    self.analyzer = analyzer

                    let audio = try recorder.start()
                    try await analyzer.start(inputSequence: audio)
                    startSilenceWatchdog(timeout: silenceTimeout)

                    var finalText = ""
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        if result.isFinal {
                            finalText += text
                            continuation.yield(Update(text: finalText, isFinal: false))
                        } else {
                            continuation.yield(Update(text: finalText + text, isFinal: false))
                        }
                    }
                    continuation.yield(Update(text: finalText, isFinal: true))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                self.stop()
            }
        }
    }

    func stop() {
        silenceTask?.cancel()
        silenceTask = nil
        recorder.stop()
        let analyzer = self.analyzer
        self.analyzer = nil
        Task { try? await analyzer?.finalizeAndFinishThroughEndOfInput() }
    }

    var currentLevel: Float { recorder.currentLevel }

    /// Ends the session after `timeout` seconds of continuous near-silence, but only
    /// once some speech has been heard (so slow starters aren't cut off).
    private func startSilenceWatchdog(timeout: TimeInterval) {
        silenceTask = Task { [weak self] in
            let threshold: Float = 0.008
            var heardSpeech = false
            var quietFor: TimeInterval = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                let loud = self.currentLevel > threshold
                if loud { heardSpeech = true; quietFor = 0 } else { quietFor += 0.1 }
                if heardSpeech && quietFor >= timeout {
                    self.stop()
                    return
                }
            }
        }
    }
}
