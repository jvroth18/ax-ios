import Foundation
import Observation

/// Global app state. The Action Button intent flips `pendingListen` before the app
/// foregrounds; RootView holds that request until the model can service it, then starts
/// the voice pipeline.
@Observable @MainActor
final class AppState {
    static let shared = AppState()

    enum Mode: Equatable {
        case idle
        /// The Action Button fired before the model was resident. The request is being
        /// held, not dropped, until it can be serviced (RootView.servicePendingListen).
        case preparing
        case listening
        case thinking
        case awaitingConfirmation
    }

    var mode: Mode = .idle
    /// Set by AskAXIntent so the app starts recording the moment it becomes active.
    /// Stays set until the request is actually serviced — on a cold start the app becomes
    /// active a second or more before the model finishes loading, and consuming the flag
    /// at that moment is what used to make the Action Button do nothing at all.
    var pendingListen = false
    /// Why a held Action Button request couldn't be honored (no weights, load failed).
    /// Shown in the chat window; the alternative is silence, which reads as a broken app.
    var actionButtonNotice: String?

    var settings = SettingsStore()

    private init() {}
}
