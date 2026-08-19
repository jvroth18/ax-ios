import AVFoundation

/// Speaks replies without hijacking the user's audio. A bare AVSpeechSynthesizer
/// activates its own audio session and never releases it, which leaves the user's
/// podcast/music paused forever. This one uses the app session, ducks others while
/// speaking, and deactivates with notifyOthersOnDeactivation so playback resumes.
final class ReplySpeaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = ReplySpeaker()

    private let synthesizer = AVSpeechSynthesizer()

    override private init() {
        super.init()
        synthesizer.usesApplicationAudioSession = true
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? session.setActive(true)
        synthesizer.speak(AVSpeechUtterance(string: text))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        releaseSessionIfIdle()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        releaseSessionIfIdle()
    }

    private func releaseSessionIfIdle() {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
