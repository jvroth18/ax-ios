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
    @State private var keyboardPresented = ProcessInfo.processInfo.environment["UITEST_SHOW_CHAT_KEYBOARD"] == "1"

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
                                Button("Stop") { conversation.cancelTurn() }
                                    .buttonStyle(W95ButtonStyle())
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
                .simultaneousGesture(TapGesture().onEnded { keyboardPresented = false })
                .onChange(of: conversation.messages) { _, messages in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            // One-tap tools toggle: a real W95 checkbox, always visible above input.
            if appState.mode == .idle {
                Button {
                    appState.settings.toolsMode.toggle()
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Rectangle().fill(.white).frame(width: 15, height: 15)
                                .overlay(W95BevelOverlay(sunken: true))
                            if appState.settings.toolsMode {
                                Text("✓").font(.system(size: 11, weight: .bold)).foregroundStyle(W95.text)
                            }
                        }
                        Text(appState.settings.toolsMode
                             ? "Tools mode — AX can set reminders, timers, open apps"
                             : "Tools mode off — conversation only")
                            .font(W95.ui(11))
                            .foregroundStyle(W95.shadow)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 2)
            }

            // Recording replaces the input row (stable height, one Stop control)
            // rather than stacking above and shoving it under the user's thumb.
            if case .listening = appState.mode {
                RecordingOverlay(session: session)
            } else {
                HStack(spacing: 6) {
                    Button { keyboardPresented = true } label: {
                        HStack(spacing: 2) {
                            Text(typedInput.isEmpty ? "Type a message…" : typedInput)
                                .foregroundStyle(typedInput.isEmpty ? W95.shadow : W95.text)
                                .lineLimit(2)
                                .truncationMode(.head)
                            if keyboardPresented {
                                Rectangle()
                                    .fill(W95.text)
                                    .frame(width: 1, height: 16)
                                    .w95Blink()
                            }
                            Spacer(minLength: 0)
                        }
                        .font(W95.ui(13))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .w95Well(background: .white)
                    .accessibilityLabel("Message")
                    .accessibilityValue(typedInput)
                    .accessibilityHint("Opens the AX keyboard. Use the separate Send button to submit.")
                    // One context-sensitive key: Send when there's text, mic when empty.
                    if hasDraft {
                        Button("Send") { submitTyped() }
                            .buttonStyle(W95ButtonStyle(bold: true))
                            .disabled(appState.mode != .idle)
                    } else {
                        Button("🎙 Talk") { startVoice() }
                            .buttonStyle(W95ButtonStyle())
                            .disabled(appState.mode != .idle)
                    }
                }
            }

            // Mode lives in the status bar, INS/CAPS-style — not a whole toolbar row.
            W95StatusBar(fields: [statusText, appState.settings.toolsMode ? "Tools: On" : "Tools: Off"])

            if keyboardPresented, case .idle = appState.mode {
                W95Keyboard(
                    text: $typedInput,
                    onDismiss: { keyboardPresented = false }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
        case .preparing: return "Waking up…"
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

    private var hasDraft: Bool {
        !typedInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        keyboardPresented = false
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
