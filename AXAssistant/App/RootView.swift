import SwiftUI

struct RootView: View {
    enum Dest: Hashable {
        case library, monitor, settings
        #if DEBUG
        case eval
        #endif
    }

    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    private let modelManager = ModelManager.shared
    @State private var conversation = Conversation()
    @State private var session: VoiceSession?
    @State private var path = NavigationPath()
    @State private var openMenu: String?
    @State private var minimized = false
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                W95Desktop()
                if minimized {
                    desktop
                } else {
                    W95Window(
                        title: "AX — \(modelManager.choice.name)",
                        onMinimize: { minimized = true }
                    ) {
                        VStack(spacing: 0) {
                            menuBar
                            ZStack(alignment: .top) {
                                Group {
                                    switch modelManager.state {
                                    case .ready:
                                        ChatView(modelManager: modelManager, conversation: conversation, session: $session)
                                    default:
                                        ModelDownloadView(modelManager: modelManager)
                                    }
                                }
                                // Tap-away closes an open menu before anything else happens.
                                if openMenu != nil {
                                    Color.black.opacity(0.001)
                                        .onTapGesture { openMenu = nil }
                                }
                            }
                        }
                    }
                    .padding(6)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Dest.self) { dest in
                switch dest {
                case .library: ModelLibraryView(modelManager: modelManager)
                case .monitor: MetricsView()
                case .settings: SettingsView(modelManager: modelManager)
                #if DEBUG
                case .eval: EvalView(modelManager: modelManager)
                #endif
                }
            }
        }
        .tint(W95.navy)
        .preferredColorScheme(.light)
        .task {
            MetricsStore.shared.startSampling()
            await modelManager.loadIfDownloaded()
        }
        .sheet(isPresented: Binding(get: { !hasOnboarded }, set: { hasOnboarded = !$0 })) {
            OnboardingView(isPresented: Binding(get: { !hasOnboarded }, set: { hasOnboarded = !$0 }))
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, appState.pendingListen else { return }
            appState.pendingListen = false
            startListening()
        }
    }

    // MARK: - Desktop (minimized state)

    /// The whole phone becomes the machine: minimizing AX lands on a desktop with
    /// icons, a Start menu, and a taskbar showing the one running app.
    private var desktop: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                W95DesktopIcon(glyph: "🖥️", label: "AX") { minimized = false }
                W95DesktopIcon(glyph: "💾", label: "Models") { open(.library) }
                W95DesktopIcon(glyph: "📈", label: "Monitor") { open(.monitor) }
                W95DesktopIcon(glyph: "⚙️", label: "Settings") { open(.settings) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Taskbar
            HStack(spacing: 6) {
                Menu {
                    Button("AX") { minimized = false }
                    Button("Model Library") { open(.library) }
                    Button("System Monitor") { open(.monitor) }
                    Button("Settings") { open(.settings) }
                } label: {
                    HStack(spacing: 4) {
                        Text("▞").font(.system(size: 12, weight: .black)).foregroundStyle(W95.navy)
                        Text("Start").font(W95.ui(13, bold: true)).foregroundStyle(W95.text)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(W95.face)
                    .overlay(W95BevelOverlay())
                }
                Button {
                    minimized = false
                } label: {
                    Text("AX — \(modelManager.choice.name)")
                        .font(W95.ui(12))
                        .foregroundStyle(W95.text)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(W95.face)
                        .overlay(W95BevelOverlay(sunken: true))
                }
                .buttonStyle(.plain)
                Spacer()
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(W95.ui(12))
                        .foregroundStyle(W95.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .overlay(W95BevelOverlay(sunken: true))
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity)
            .background(W95.face)
            .overlay(Rectangle().fill(W95.white).frame(height: 1), alignment: .top)
        }
    }

    private func open(_ dest: Dest) {
        minimized = false
        path.append(dest)
    }

    // MARK: - Menu bar

    private var menuBar: some View {
        HStack(spacing: 0) {
            menu("File") {
                menuItem("New Chat") { conversation.clear() }
            }
            menu("Models") {
                menuItem("Model Library…") { push(.library) }
                menuSeparator
                if installedModels.isEmpty {
                    menuItem("(none installed)") {}
                } else {
                    ForEach(installedModels) { model in
                        menuItem(model == modelManager.choice ? "✓ \(model.name)" : "   \(model.name)") {
                            Task { await modelManager.switchTo(model) }
                        }
                    }
                }
            }
            menu("Tools") {
                menuItem("System Monitor") { push(.monitor) }
                #if DEBUG
                menuItem("Tool-call Eval") { push(.eval) }
                #endif
                menuSeparator
                menuItem("Settings…") { push(.settings) }
            }
            Spacer()
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .background(W95.face)
        .zIndex(10)
    }

    /// A menu-bar title that drops its items below itself when open.
    private func menu(_ title: String, @ViewBuilder items: @escaping () -> some View) -> some View {
        Button {
            openMenu = openMenu == title ? nil : title
        } label: {
            Text(title)
                .font(W95.ui(13))
                .foregroundStyle(openMenu == title ? .white : W95.text)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(openMenu == title ? W95.navy : .clear)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if openMenu == title {
                VStack(alignment: .leading, spacing: 0) {
                    items()
                }
                .frame(minWidth: 180, alignment: .leading)
                .background(W95.face)
                .overlay(W95BevelOverlay())
                .fixedSize()
                .offset(y: 25)
                .shadow(color: .black.opacity(0.4), radius: 3, x: 2, y: 2)
            }
        }
        .zIndex(openMenu == title ? 20 : 0)
    }

    private func menuItem(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            openMenu = nil
            action()
        } label: {
            Text(title)
                .font(W95.ui(13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .buttonStyle(W95MenuItemStyle())
    }

    private var menuSeparator: some View {
        VStack(spacing: 0) {
            Rectangle().fill(W95.shadow).frame(height: 1)
            Rectangle().fill(W95.white).frame(height: 1)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    private var installedModels: [CatalogModel] {
        ModelCatalog.all.filter(modelManager.isDownloaded)
    }

    private func push(_ dest: Dest) {
        path.append(dest)
    }

    private func startListening() {
        guard case .ready = modelManager.state else { return }
        session?.cancel()
        session = VoiceSession(conversation: conversation, modelManager: modelManager, appState: appState)
        session?.start()
    }
}

/// Dropdown item: navy highlight while pressed, like hovering a 95 menu.
struct W95MenuItemStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? .white : W95.text)
            .background(configuration.isPressed ? W95.navy : .clear)
    }
}
