import AVFoundation
import Speech

/// Captures microphone audio via AVAudioEngine as raw PCM buffers (in the input node's
/// native format — the Transcriber converts to the analyzer's preferred format). Also
/// computes a rolling RMS level for the waveform UI and silence detection.
/// @unchecked Sendable: currentLevel is a torn-read-tolerant level meter; engine state is
/// only touched from start()/stop().
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    /// 0...1-ish input level, updated on the audio thread; read by the UI timer.
    private(set) var currentLevel: Float = 0

    /// The mic's native format; valid after start().
    private(set) var inputFormat: AVAudioFormat?

    func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let (stream, continuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
        self.continuation = continuation

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        inputFormat = format
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.currentLevel = Self.rms(of: buffer)
            continuation.yield(buffer)
        }

        engine.prepare()
        try engine.start()
        return stream
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        return (sum / Float(count)).squareRoot()
    }
}
