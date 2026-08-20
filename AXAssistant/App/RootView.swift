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
    @State private var iconPositions: [String: CGPoint] = RootView.loadIconPositions()
    /// The in-flight wait for a model to become ready before an Action Button request
    /// can be honored. Cancelled when the app backgrounds; the request itself survives.
    @State private var pendingListenTask: Task<Void, Never>?
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                W95Desktop()
                W95AsciiLogo()
                desktopSurface
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
            switch phase {
            case .active:
                guard appState.pendingListen else { return }
                open(.chat)
                servicePendingListen()
            case .background:
                // Stop waiting, but keep the request: recording into a pocket is worse
                // than picking it up again the next time the app comes forward.
                pendingListenTask?.cancel()
                pendingListenTask = nil
                if appState.mode == .preparing { appState.mode = .idle }
            default:
                break
            }
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
                    if let status = actionButtonStatus {
                        actionButtonBanner(status)
                    }
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

    /// Draggable icons over the bouncing-logo background. Each icon remembers where
    /// you drop it (persisted); tap opens, drag repositions — like a real desktop.
    private var desktopSurface: some View {
        GeometryReader { geo in
            ForEach(Array(AppWindow.allCases.enumerated()), id: \.element) { index, window in
                W95DesktopIcon(glyph: window.glyph, label: window.title) { open(window) }
                    .position(iconPositions[window.rawValue] ?? Self.defaultIconPosition(index))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                iconPositions[window.rawValue] = clamp(value.location, in: geo.size)
                            }
                            .onEnded { _ in saveIconPositions() }
                    )
            }
        }
    }

    private static func defaultIconPosition(_ index: Int) -> CGPoint {
        CGPoint(x: 52, y: 60 + Double(index) * 92)
    }

    private func clamp(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 40), size.width - 40),
            y: min(max(point.y, 44), size.height - 44)
        )
    }

    private func saveIconPositions() {
        let encodable = iconPositions.mapValues { [$0.x, $0.y] }
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: "desktopIconPositions")
        }
    }

    private static func loadIconPositions() -> [String: CGPoint] {
        guard let data = UserDefaults.standard.data(forKey: "desktopIconPositions"),
              let raw = try? JSONDecoder().decode([String: [Double]].self, from: data)
        else { return [:] }
        return raw.compactMapValues { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
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

    // MARK: - Action Button

    /// Honors a held Action Button request as soon as the model can service it.
    ///
    /// The intent foregrounds the app, so the scene turns active while the launch load is
    /// still running (~1.3 s for the 1.7B, longer for a 4B). Consuming `pendingListen`
    /// there and then testing readiness — which is what this used to do — threw the
    /// user's press away in silence on every cold start, the app's headline interaction.
    /// So: show that we heard them, wait for the model, and only then consume the request.
    /// If readiness is never coming, say why rather than leaving them staring at nothing.
    private func servicePendingListen() {
        pendingListenTask?.cancel()
        pendingListenTask = Task { @MainActor in
            appState.actionButtonNotice = nil
            appState.mode = .preparing
            let ready = await modelManager.waitUntilReady()
            // Cancelled means the app backgrounded: leave `pendingListen` set so the next
            // foreground picks the request up again.
            guard !Task.isCancelled else { return }
            pendingListenTask = nil
            appState.pendingListen = false
            guard ready else {
                appState.mode = .idle
                appState.actionButtonNotice = unavailableNotice()
                return
            }
            startListening()
        }
    }

    /// Why the held request couldn't be serviced, in the user's terms and with the next
    /// step. ModelDownloadView is on screen underneath in every one of these cases.
    private func unavailableNotice() -> String {
        let name = modelManager.choice.name
        switch modelManager.state {
        case .failed(let message):
            return "Couldn't load \(name) — \(message). Tap Retry below, then press the Action Button again."
        case .ready:
            return "Couldn't start listening. Press the Action Button again."
        default:
            return modelManager.isDownloaded(modelManager.choice)
                ? "Stopped loading \(name) before it was ready. Start it below, then press the Action Button again."
                : "AX needs to download \(name) (\(modelManager.choice.sizeLabel)) before it can listen."
        }
    }

    /// One line telling the user what their Action Button press is doing. Only ever nil
    /// when there is genuinely nothing to report.
    private var actionButtonStatus: (text: String, isError: Bool)? {
        if let notice = appState.actionButtonNotice { return (notice, true) }
        if appState.mode == .preparing {
            return ("Heard you — waking \(modelManager.choice.name) up, then I'll listen…", false)
        }
        return nil
    }

    private func actionButtonBanner(_ status: (text: String, isError: Bool)) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if status.isError {
                Text("✗").font(W95.ui(13, bold: true)).foregroundStyle(.red)
            } else {
                W95Hourglass()
            }
            Text(status.text)
                .font(W95.ui(12))
                .foregroundStyle(W95.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if status.isError {
                Button("OK") { appState.actionButtonNotice = nil }
                    .buttonStyle(W95ButtonStyle())
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(W95.face)
        .overlay(W95BevelOverlay())
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    /// Only called once `waitUntilReady()` has confirmed a resident model. The guard is a
    /// backstop now, not the readiness test that used to swallow Action Button presses.
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
