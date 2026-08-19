import AVFoundation
import Foundation
import HuggingFace
import MLX
import MLXAudioTTS

/// Speaks replies with Kokoro-82M — an 82M-parameter open TTS model that sounds
/// dramatically better than AVSpeechSynthesizer. Small enough (~330 MB bf16) to sit
/// beside the resident LLM; weights download once into the shared Documents hub store.
///
/// Streaming: Kokoro synthesizes whole utterances (the package's generateStream is a
/// single-chunk wrapper), so we pipeline at sentence granularity — sentence 1 starts
/// playing while sentence 2 synthesizes, buffers queued gaplessly on one player node.
final class KokoroSpeaker {
    static let shared = KokoroSpeaker()

    static let modelRepo = "mlx-community/Kokoro-82M-bf16"

    /// A curated slice of Kokoro's 54 voices, id → display name.
    static let voices: [(id: String, label: String)] = [
        ("af_heart", "Heart (US female)"),
        ("af_bella", "Bella (US female)"),
        ("af_nova", "Nova (US female)"),
        ("am_adam", "Adam (US male)"),
        ("am_michael", "Michael (US male)"),
        ("am_puck", "Puck (US male)"),
        ("bf_emma", "Emma (UK female)"),
        ("bm_george", "George (UK male)"),
        ("bm_fable", "Fable (UK male)"),
    ]

    private var model: KokoroModel?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var engineWired = false

    /// Bumped by stop(); an in-flight speak loop aborts when its id goes stale.
    private var generationID = UUID()
    private let stateLock = NSLock()
    private var pendingBuffers = 0
    private var doneGenerating = false

    private init() {}

    /// Generate and play, sentence-pipelined. Downloads + loads the model on first
    /// use; falls back to the system voice if anything fails so the reply is never
    /// silently dropped.
    func speak(_ text: String, voice: String) async {
        let myID = UUID()
        stateLock.withLock {
            generationID = myID
            pendingBuffers = 0
            doneGenerating = false
        }
        do {
            let model = try await loadedModel()
            var startedPlayback = false
            for sentence in Self.sentences(of: text) {
                guard stateLock.withLock({ generationID == myID }) else { return }
                let samples = try await model.generate(
                    text: sentence, voice: voice, refAudio: nil, refText: nil, language: nil
                )
                guard stateLock.withLock({ generationID == myID }) else { return }
                if !startedPlayback {
                    try startSession(rate: Double(model.sampleRate))
                    startedPlayback = true
                }
                schedule(samples: samples.asArray(Float.self), rate: Double(model.sampleRate))
            }
            let releaseNow: Bool = stateLock.withLock {
                doneGenerating = true
                return pendingBuffers == 0
            }
            if releaseNow { releaseSession() }
        } catch {
            await MainActor.run { ReplySpeaker.shared.speak(text) }
        }
    }

    func stop() {
        stateLock.withLock { generationID = UUID() }
        player.stop()
        releaseSession()
    }

    /// Drop the voice model to free ~350 MB before a large LLM loads. It reloads
    /// lazily on the next spoken reply.
    func freeModel() {
        stop()
        model = nil
    }

    // MARK: - Internals

    private func loadedModel() async throws -> KokoroModel {
        if let model { return model }
        // The text processor is REQUIRED for real speech: without it the package
        // tokenizes raw text against a phoneme vocabulary and emits silence.
        let loaded = try await KokoroModel.fromPretrained(
            Self.modelRepo,
            textProcessor: KokoroMultilingualProcessor(),
            cache: HubCache(cacheDirectory: ModelManager.hubRoot)
        )
        model = loaded
        return loaded
    }

    /// Sentence-ish chunks: split on terminal punctuation, merge fragments shorter
    /// than a beat so we don't synthesize "Hi." alone when "Hi. Two things…" flows
    /// better, and hard-cap chunk length for the model's token limit.
    static func sentences(of text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if ".!?…\n".contains(character), current.count >= 40 {
                chunks.append(current)
                current = ""
            } else if current.count >= 300 {
                chunks.append(current)
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(current)
        }
        return chunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func startSession(rate: Double) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try session.setActive(true)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
        if !engineWired {
            engine.attach(player)
            engineWired = true
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        if !engine.isRunning { try engine.start() }
        player.play()
    }

    private func schedule(samples: [Float], rate: Double) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = buffer.floatChannelData?[0]
        else { return }
        for index in samples.indices { channel[index] = samples[index] }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        stateLock.withLock { pendingBuffers += 1 }
        player.scheduleBuffer(buffer) { [weak self] in
            guard let self else { return }
            let releaseNow: Bool = self.stateLock.withLock {
                self.pendingBuffers -= 1
                return self.pendingBuffers == 0 && self.doneGenerating
            }
            if releaseNow { self.releaseSession() }
        }
    }

    private func releaseSession() {
        // Resume the user's podcast/music once we're done talking.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
