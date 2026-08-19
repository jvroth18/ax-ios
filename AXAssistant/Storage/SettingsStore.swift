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
    /// How many tool calls the agent may chain in one request (1–8).
    var maxToolIterations: Int {
        didSet { UserDefaults.standard.set(maxToolIterations, forKey: "maxToolIterations") }
    }
    /// Speak replies with Kokoro-82M (open, on-device, natural) instead of the system voice.
    var useKokoroVoice: Bool {
        didSet { UserDefaults.standard.set(useKokoroVoice, forKey: "useKokoroVoice") }
    }
    var kokoroVoice: String {
        didSet { UserDefaults.standard.set(kokoroVoice, forKey: "kokoroVoice") }
    }
    var registeredShortcuts: [String] {
        didSet { UserDefaults.standard.set(registeredShortcuts, forKey: "registeredShortcuts") }
    }
    var endpointConnectors: [EndpointConnector] {
        didSet { Self.saveJSON(endpointConnectors, key: "endpointConnectors") }
    }
    var appSummaryConnectors: [AppSummaryConnector] {
        didSet { Self.saveJSON(appSummaryConnectors, key: "appSummaryConnectors") }
    }

    init() {
        let defaults = UserDefaults.standard
        speakReplies = defaults.object(forKey: "speakReplies") as? Bool ?? true
        silenceTimeout = defaults.object(forKey: "silenceTimeout") as? Double ?? 1.2
        maxToolIterations = defaults.object(forKey: "maxToolIterations") as? Int ?? 3
        useKokoroVoice = defaults.object(forKey: "useKokoroVoice") as? Bool ?? false
        kokoroVoice = defaults.string(forKey: "kokoroVoice") ?? "af_heart"
        registeredShortcuts = defaults.stringArray(forKey: "registeredShortcuts") ?? []
        endpointConnectors = Self.loadJSON(key: "endpointConnectors") ?? []
        appSummaryConnectors = Self.loadJSON(key: "appSummaryConnectors") ?? []
    }

    private static func saveJSON<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadJSON<T: Decodable>(key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
