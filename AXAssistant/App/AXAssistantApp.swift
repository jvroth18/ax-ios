import SwiftUI

@main
struct AXAssistantApp: App {
    @State private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .onOpenURL { url in
                    // x-callback return from the Shortcuts app (run_shortcut tool)
                    ShortcutTool.handleCallback(url: url)
                }
        }
    }
}
