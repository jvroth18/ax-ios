import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @State private var modelManager = ModelManager()
    @State private var session: VoiceSession?

    var body: some View {
        NavigationStack {
            Group {
                switch modelManager.state {
                case .ready:
                    ChatView(modelManager: modelManager, session: $session)
                default:
                    ModelDownloadView(modelManager: modelManager)
                }
            }
            .navigationTitle("AX")
            .toolbar {
                NavigationLink("Settings") { SettingsView(modelManager: modelManager) }
            }
        }
        .task { await modelManager.loadIfDownloaded() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, appState.pendingListen else { return }
            appState.pendingListen = false
            startListening()
        }
    }

    private func startListening() {
        guard case .ready = modelManager.state else { return }
        session?.cancel()
        session = VoiceSession(modelManager: modelManager, appState: appState)
        session?.start()
    }
}
