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

    private static func makeTranscriber() -> SpeechTranscriber {
        SpeechTranscriber(
            locale: .current,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],  // live partial results
            attributeOptions: []
        )
    }

    /// Ensures the current locale's transcription asset is installed (one-time prompt-free
    /// system download; call from onboarding and before first use).
    static func ensureAssetsInstalled() async throws {
        let transcriber = makeTranscriber()
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
                    let transcriber = Self.makeTranscriber()
                    let analyzer = SpeechAnalyzer(modules: [transcriber])
                    self.analyzer = analyzer

                    // The analyzer wants its own audio format; convert the mic's native
                    // buffers on the way in.
                    let analysisFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                        compatibleWith: [transcriber]
                    )
                    let rawAudio = try recorder.start()
                    let audio = Self.converted(rawAudio, from: recorder.inputFormat, to: analysisFormat)
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

    /// Maps raw mic buffers into AnalyzerInput, converting formats when they differ.
    private static func converted(
        _ source: AsyncStream<AVAudioPCMBuffer>,
        from inputFormat: AVAudioFormat?,
        to analysisFormat: AVAudioFormat?
    ) -> AsyncStream<AnalyzerInput> {
        AsyncStream { continuation in
            let converter: AVAudioConverter? = {
                guard let inputFormat, let analysisFormat, inputFormat != analysisFormat else {
                    return nil
                }
                return AVAudioConverter(from: inputFormat, to: analysisFormat)
            }()
            let task = Task {
                for await buffer in source {
                    if let converter, let analysisFormat {
                        let ratio = analysisFormat.sampleRate / buffer.format.sampleRate
                        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
                        guard let out = AVAudioPCMBuffer(
                            pcmFormat: analysisFormat, frameCapacity: capacity
                        ) else { continue }
                        var fed = false
                        var error: NSError?
                        converter.convert(to: out, error: &error) { _, status in
                            if fed {
                                status.pointee = .noDataNow
                                return nil
                            }
                            fed = true
                            status.pointee = .haveData
                            return buffer
                        }
                        if error == nil, out.frameLength > 0 {
                            continuation.yield(AnalyzerInput(buffer: out))
                        }
                    } else {
                        continuation.yield(AnalyzerInput(buffer: buffer))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

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
