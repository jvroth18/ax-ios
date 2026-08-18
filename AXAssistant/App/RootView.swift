import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    private let modelManager = ModelManager.shared
    @State private var session: VoiceSession?
    @AppStorage("hasOnboarded") private var hasOnboarded = false

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
        .sheet(isPresented: Binding(get: { !hasOnboarded }, set: { hasOnboarded = !$0 })) {
            OnboardingView(isPresented: Binding(get: { !hasOnboarded }, set: { hasOnboarded = !$0 }))
        }
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
