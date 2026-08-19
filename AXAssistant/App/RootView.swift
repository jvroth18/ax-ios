import SwiftUI

/// The Windows-95 shell: a permanent desktop, windows that open instantly on top of
/// it, and an always-present taskbar. No iOS navigation pushes, no slide animations,
/// no swipe-back — windows are opened, activated, minimized, and closed.
struct RootView: View {
    enum AppWindow: String, CaseIterable, Identifiable {
        case chat, library, monitor, settings

        var id: String { rawValue }
        var title: String {
            switch self {
            case .chat: return "AX"
            case .library: return "Model Library"
            case .monitor: return "System Monitor"
            case .settings: return "Settings"
            }
        }
        var glyph: String {
            switch self {
            case .chat: return "🖥️"
            case .library: return "💾"
            case .monitor: return "📈"
            case .settings: return "⚙️"
            }
        }
    }

    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    private let modelManager = ModelManager.shared
    @State private var conversation = Conversation()
    @State private var session: VoiceSession?
    @State private var openMenu: String?
    /// Open windows in open-order (their taskbar buttons), and the one on top.
    /// active == nil with windows open means "everything minimized" — bare desktop.
    @State private var openWindows: [AppWindow] = [.chat]
    @State private var active: AppWindow? = .chat
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                W95Desktop()
                desktopIcons
                if let active {
                    windowBody(for: active)
                        .padding(4)
                }
            }
            taskbar
        }
        .background(W95.desktop)
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
            open(.chat)
            startListening()
        }
    }

    // MARK: - Window management

    private func open(_ window: AppWindow) {
        if !openWindows.contains(window) { openWindows.append(window) }
        active = window
    }

    private func minimize(_ window: AppWindow) {
        if active == window { active = nil }
    }

    private func close(_ window: AppWindow) {
        openWindows.removeAll { $0 == window }
        if active == window { active = openWindows.last }
    }

    // MARK: - Windows

    @ViewBuilder
    private func windowBody(for window: AppWindow) -> some View {
        switch window {
        case .chat:
            W95Window(
                title: "AX — \(modelManager.choice.name)",
                onClose: { close(.chat) },
                onMinimize: { minimize(.chat) }
            ) {
                VStack(spacing: 0) {
                    menuBar
                    ZStack(alignment: .top) {
                        Group {
                            switch modelManager.state {
                            case .ready:
                                ChatView(modelManager: modelManager, conversation: conversation, session: $session)
                            default:
                                ModelDownloadView(
                                    modelManager: modelManager,
                                    onOpenLibrary: { open(.library) }
                                )
                            }
                        }
                        if openMenu != nil {
                            Color.black.opacity(0.001)
                                .onTapGesture { openMenu = nil }
                        }
                    }
                }
            }
        case .library:
            ModelLibraryView(
                modelManager: modelManager,
                onClose: { close(.library) },
                onMinimize: { minimize(.library) }
            )
        case .monitor:
            MetricsView(
                onClose: { close(.monitor) },
                onMinimize: { minimize(.monitor) }
            )
        case .settings:
            SettingsView(
                modelManager: modelManager,
                onClose: { close(.settings) },
                onMinimize: { minimize(.settings) }
            )
        }
    }

    // MARK: - Desktop

    private var desktopIcons: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(AppWindow.allCases) { window in
                W95DesktopIcon(glyph: window.glyph, label: window.title) { open(window) }
            }
        }
        .padding(20)
    }

    // MARK: - Taskbar

    private var taskbar: some View {
        HStack(spacing: 5) {
            Menu {
                ForEach(AppWindow.allCases) { window in
                    Button(window.title) { open(window) }
                }
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
            ForEach(openWindows) { window in
                Button {
                    active == window ? minimize(window) : open(window)
                } label: {
                    Text(window.title)
                        .font(W95.ui(11, bold: active == window))
                        .foregroundStyle(W95.text)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(active == window ? W95.faceLight : W95.face)
                        .overlay(W95BevelOverlay(sunken: active == window))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(W95.ui(11))
                    .foregroundStyle(W95.text)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .overlay(W95BevelOverlay(sunken: true))
            }
        }
        .padding(4)
        .background(W95.face)
        .overlay(Rectangle().fill(W95.white).frame(height: 1), alignment: .top)
    }

    // MARK: - Menu bar (chat window)

    private var menuBar: some View {
        HStack(spacing: 0) {
            menu("File") {
                menuItem("New Chat") { conversation.clear() }
            }
            menu("Mode") {
                menuItem(appState.settings.toolsMode ? "   Chat" : "✓ Chat") {
                    appState.settings.toolsMode = false
                }
                menuItem(appState.settings.toolsMode ? "✓ Tools" : "   Tools") {
                    appState.settings.toolsMode = true
                }
            }
            menu("Models") {
                if installedModels.isEmpty {
                    menuItem("(none installed)") {}
                } else {
                    ForEach(installedModels) { model in
                        menuItem(model == modelManager.choice ? "✓ \(model.name)" : "   \(model.name)") {
                            Task { await modelManager.switchTo(model) }
                        }
                    }
                }
                menuSeparator
                menuItem("Model Library…") { open(.library) }
            }
            Spacer()
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .background(W95.face)
        .zIndex(10)
    }

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
