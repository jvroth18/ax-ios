import AVFoundation
import Foundation
import HuggingFace
import MLX
import MLXAudioTTS

/// Speaks replies with Kokoro-82M — an 82M-parameter open TTS model that sounds
/// dramatically better than AVSpeechSynthesizer. Small enough (~330 MB bf16) to sit
/// beside the resident LLM. Weights download once into the shared Documents hub store.
/// Same audio-session discipline as ReplySpeaker: duck others, release on finish.
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

    private init() {}

    /// Generate and play. Downloads + loads the model on first use; falls back to
    /// the system voice if anything fails so the reply is never silently dropped.
    func speak(_ text: String, voice: String) async {
        do {
            let model = try await loadedModel()
            let samples = try await model.generate(
                text: text, voice: voice, refAudio: nil, refText: nil, language: nil
            )
            try play(samples: samples.asArray(Float.self), rate: Double(model.sampleRate))
        } catch {
            await MainActor.run { ReplySpeaker.shared.speak(text) }
        }
    }

    func stop() {
        player.stop()
        releaseSession()
    }

    // MARK: - Internals

    private func loadedModel() async throws -> KokoroModel {
        if let model { return model }
        let loaded = try await KokoroModel.fromPretrained(
            Self.modelRepo,
            cache: HubCache(cacheDirectory: ModelManager.hubRoot)
        )
        model = loaded
        return loaded
    }

    private func play(samples: [Float], rate: Double) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = buffer.floatChannelData?[0]
        else { return }
        for index in samples.indices { channel[index] = samples[index] }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try session.setActive(true)

        if !engineWired {
            engine.attach(player)
            engineWired = true
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        if !engine.isRunning { try engine.start() }

        player.scheduleBuffer(buffer) { [weak self] in
            self?.releaseSession()
        }
        player.play()
    }

    private func releaseSession() {
        // Resume the user's podcast/music once we're done talking.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
