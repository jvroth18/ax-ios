import Foundation
import Observation

/// User preferences, persisted to UserDefaults.
@Observable @MainActor
final class SettingsStore {
    var speakReplies: Bool {
        didSet { UserDefaults.standard.set(speakReplies, forKey: "speakReplies") }
    }
    var silenceTimeout: Double {
        didSet { UserDefaults.standard.set(silenceTimeout, forKey: "silenceTimeout") }
    }
    var registeredShortcuts: [String] {
        didSet { UserDefaults.standard.set(registeredShortcuts, forKey: "registeredShortcuts") }
    }

    init() {
        let defaults = UserDefaults.standard
        speakReplies = defaults.object(forKey: "speakReplies") as? Bool ?? true
        silenceTimeout = defaults.object(forKey: "silenceTimeout") as? Double ?? 1.2
        registeredShortcuts = defaults.stringArray(forKey: "registeredShortcuts") ?? []
    }
}
