import SwiftUI
import AXCore

struct ChatView: View {
    @Environment(AppState.self) private var appState
    let modelManager: ModelManager
    let conversation: Conversation
    @Binding var session: VoiceSession?
    @State private var typedInput = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if conversation.messages.isEmpty && conversation.thinkingPartial == nil {
                            ContentUnavailableView(
                                "Press your Action Button",
                                systemImage: "waveform.circle",
                                description: Text("Or type below. Assign the Action Button in Settings > Action Button > Shortcut > Ask AX.")
                            )
                            .padding(.top, 60)
                        }
                        ForEach(conversation.messages) { message in
                            MessageBubble(message: message)
                        }
                        if let partial = conversation.thinkingPartial {
                            Text(partial.isEmpty ? "…" : partial)
                                .foregroundStyle(.secondary)
                                .padding(10)
                                .id("thinking")
                        }
                        if case .failed(let why) = session?.phase {
                            Label(why, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.callout)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .onChange(of: conversation.messages) { _, messages in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if case .listening = appState.mode {
                RecordingOverlay(session: session)
            }

            HStack {
                TextField("Type a request…", text: $typedInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submitTyped)
                Button(action: startVoice) {
                    Image(systemName: "mic.circle.fill").font(.title)
                }
                .disabled(appState.mode != .idle)
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Clear", systemImage: "square.and.pencil") { conversation.clear() }
                    .disabled(conversation.messages.isEmpty)
            }
        }
        .sheet(isPresented: confirmationPresented) {
            if let pending = conversation.pendingConfirmation {
                ConfirmSheet(call: pending.call, spec: pending.spec, resume: pending.resume)
            }
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

private struct MessageBubble: View {
    let message: Conversation.DisplayMessage

    var body: some View {
        switch message.role {
        case .user:
            Text(message.text)
                .padding(10)
                .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant:
            Text(message.text)
                .padding(10)
                .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .tool:
            Label(message.text, systemImage: "wrench.and.screwdriver")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}
