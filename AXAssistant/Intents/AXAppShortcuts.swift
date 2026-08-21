import AppIntents

/// Registers "Ask Morse" with the system so it appears in the Shortcuts app and can be
/// assigned to the Action Button (Settings > Action Button > Shortcut > Ask Morse).
struct AXAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskAXIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "\(.applicationName) listen",
            ],
            shortTitle: "Ask Morse",
            systemImageName: "waveform.circle"
        )
    }
}
