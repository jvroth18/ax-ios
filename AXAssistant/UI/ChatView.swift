import SwiftUI
import AXCore

/// The conversation, as a 90s chat log: "You:" / "AX:" lines in a sunken white well,
/// a Send button that's always visible, and a status bar reporting what the app is doing.
struct ChatView: View {
    @Environment(AppState.self) private var appState
    let modelManager: ModelManager
    let conversation: Conversation
    @Binding var session: VoiceSession?
    @State private var typedInput = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if conversation.messages.isEmpty && conversation.thinkingPartial == nil {
                            emptyState
                        }
                        ForEach(conversation.messages) { message in
                            ChatLine(message: message)
                        }
                        if let partial = conversation.thinkingPartial {
                            HStack(alignment: .top, spacing: 6) {
                                W95Hourglass()
                                Text(partial.isEmpty ? "AX is thinking…" : partial)
                                    .font(W95.ui(13))
                                    .foregroundStyle(W95.shadow)
                            }
                            .id("thinking")
                        }
                        if case .failed(let why) = session?.phase {
                            Text("! \(why)")
                                .font(W95.ui(12, bold: true))
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .w95Well(background: .white)
                // Drag down over the log peels the keyboard away; a tap outside
                // the field dismisses it outright.
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { inputFocused = false })
                .onChange(of: conversation.messages) { _, messages in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if case .listening = appState.mode {
                RecordingOverlay(session: session)
            }

            // Mode switch: the active mode reads as the pressed-in key.
            HStack(spacing: 6) {
                Text("Mode:")
                    .font(W95.ui(11))
                    .foregroundStyle(W95.shadow)
                modeKey("Chat", active: !appState.settings.toolsMode) {
                    appState.settings.toolsMode = false
                }
                modeKey("Tools", active: appState.settings.toolsMode) {
                    appState.settings.toolsMode = true
                }
                Spacer()
                Text(appState.settings.toolsMode
                     ? "AX can act: reminders, timers, apps…"
                     : "Conversation only — no actions")
                    .font(W95.ui(10))
                    .foregroundStyle(W95.shadow)
            }
            .padding(.horizontal, 2)

            HStack(spacing: 4) {
                Button("New") { conversation.clear() }
                    .buttonStyle(W95ButtonStyle())
                    .disabled(conversation.messages.isEmpty || appState.mode != .idle)
                TextField("Type a message…", text: $typedInput, axis: .vertical)
                    .font(W95.ui(13))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .w95Well(background: .white)
                    .focused($inputFocused)
                    .onSubmit(submitTyped)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { inputFocused = false }
                                .font(W95.ui(13, bold: true))
                        }
                    }
                Button("Send") { submitTyped() }
                    .buttonStyle(W95ButtonStyle(bold: true))
                    .disabled(appState.mode != .idle
                        || typedInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("🎙") { startVoice() }
                    .buttonStyle(W95ButtonStyle())
                    .disabled(appState.mode != .idle)
            }

            W95StatusBar(fields: [statusText, modelManager.choice.params])
        }
        .padding(4)
        .background(W95.face)
        .sheet(isPresented: confirmationPresented) {
            if let pending = conversation.pendingConfirmation {
                ConfirmSheet(call: pending.call, spec: pending.spec, resume: pending.resume)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to AX!")
                .font(W95.ui(15, bold: true))
                .foregroundStyle(W95.navy)
            Text("Press your Action Button to talk, or type below.")
                .font(W95.ui(13))
            Text("Tip: assign the Action Button under Settings → Action Button → Shortcut → Ask AX.")
                .font(W95.ui(12))
                .foregroundStyle(W95.shadow)
        }
        .padding(.top, 8)
    }

    private var statusText: String {
        switch appState.mode {
        case .idle: return conversation.messages.isEmpty ? "Ready" : "Done"
        case .listening: return "Listening…"
        case .thinking: return "Working…"
        case .awaitingConfirmation: return "Waiting for you…"
        }
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(
            get: { conversation.pendingConfirmation != nil },
            set: { presented in
                if !presented { conversation.pendingConfirmation?.resume(false) }
            }
        )
    }

    private func modeKey(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(W95.ui(12, bold: active))
                .foregroundStyle(W95.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(active ? W95.faceLight : W95.face)
                .overlay(W95BevelOverlay(sunken: active))
        }
        .buttonStyle(.plain)
        .disabled(appState.mode != .idle)
    }

    private func startVoice() {
        session?.cancel()
        session = VoiceSession(conversation: conversation, modelManager: modelManager, appState: appState)
        session?.start()
    }

    private func submitTyped() {
        let text = typedInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, appState.mode == .idle else { return }
        typedInput = ""
        Task { await conversation.send(text, modelManager: modelManager, appState: appState) }
    }
}

private struct ChatLine: View {
    let message: Conversation.DisplayMessage

    var body: some View {
        switch message.role {
        case .user:
            (Text("You: ").font(W95.ui(13, bold: true)).foregroundStyle(W95.navy)
             + Text(message.text).font(W95.ui(13)).foregroundStyle(W95.text))
        case .assistant:
            (Text("AX: ").font(W95.ui(13, bold: true)).foregroundStyle(W95.maroon)
             + Text(message.text).font(W95.ui(13)).foregroundStyle(W95.text))
        case .tool:
            Text("* \(message.text)")
                .font(W95.ui(12).italic())
                .foregroundStyle(W95.shadow)
        }
    }
}
