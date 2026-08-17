import AppIntents

/// The Action Button entry point. iOS cannot cold-start microphone capture from a
/// background intent, so this intent foregrounds the app, which begins recording
/// immediately (see RootView.onChange(of: scenePhase)).
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
