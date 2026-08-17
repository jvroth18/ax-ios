import Foundation
import Observation

/// Global app state. The Action Button intent flips `pendingListen` before the app
/// foregrounds; RootView observes it and starts the voice pipeline.
@Observable @MainActor
final class AppState {
    static let shared = AppState()

    enum Mode: Equatable {
        case idle
        case listening
        case thinking
        case awaitingConfirmation
    }

    var mode: Mode = .idle
    /// Set by AskAXIntent so the app starts recording the moment it becomes active.
    var pendingListen = false

    var settings = SettingsStore()

    private init() {}
}
