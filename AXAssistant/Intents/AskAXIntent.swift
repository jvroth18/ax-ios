import AppIntents

/// The Action Button entry point. iOS cannot cold-start microphone capture from a
/// background intent, so this intent foregrounds the app and leaves the request standing
/// in `pendingListen`. RootView holds it until the model is loaded and then starts
/// recording (see RootView.servicePendingListen) — on a cold start the app becomes active
/// well before the model is ready, so the request has to outlive that moment.
struct AskAXIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask AX"
    static let description = IntentDescription(
        "Records a voice request and lets the on-device model act on it."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.pendingListen = true
        return .result()
    }
}
