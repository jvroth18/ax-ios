import AppIntents

/// Registers "Ask AX" with the system so it appears in the Shortcuts app and can be
/// assigned to the Action Button (Settings > Action Button > Shortcut > Ask AX).
struct AXAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskAXIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "\(.applicationName) listen",
            ],
            shortTitle: "Ask AX",
            systemImageName: "waveform.circle"
        )
    }
}
