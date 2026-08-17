import SwiftUI
import AXCore

struct ChatView: View {
    @Environment(AppState.self) private var appState
    let modelManager: ModelManager
    @Binding var session: VoiceSession?
    @State private var typedInput = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let session {
                        SessionTranscriptView(session: session)
                    } else {
                        ContentUnavailableView(
                            "Press your Action Button",
                            systemImage: "waveform.circle",
                            description: Text("Or type below. Assign the Action Button in Settings > Action Button > Shortcut > Ask AX.")
                        )
                        .padding(.top, 60)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }

            if case .listening = appState.mode {
                RecordingOverlay(session: session)
            }

            HStack {
                TextField("Type a request…", text: $typedInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submitTyped)
                Button(action: startVoice) {
                    Image(systemName: "mic.circle.fill").font(.title)
                }
            }
            .padding()
        }
        .sheet(isPresented: confirmationPresented) {
            if let pending = session?.pendingConfirmation {
                ConfirmSheet(call: pending.call, spec: pending.spec, resume: pending.resume)
            }
        }
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(
            get: { session?.pendingConfirmation != nil },
            set: { presented in
                if !presented { session?.pendingConfirmation?.resume(false) }
            }
        )
    }

    private func startVoice() {
        session?.cancel()
        session = VoiceSession(modelManager: modelManager, appState: appState)
        session?.start()
    }

    private func submitTyped() {
        guard !typedInput.isEmpty else { return }
        // Reuse the voice pipeline minus recording: create a session and inject text.
        session?.cancel()
        let newSession = VoiceSession(modelManager: modelManager, appState: appState)
        newSession.transcript = typedInput
        session = newSession
        let text = typedInput
        typedInput = ""
        Task { await newSession.respondToTyped(text) }
    }
}

private struct SessionTranscriptView: View {
    let session: VoiceSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !session.transcript.isEmpty {
                Text(session.transcript)
                    .padding(10)
                    .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            }
            switch session.phase {
            case .recording:
                EmptyView()
            case .thinking(let partial):
                Text(partial.isEmpty ? "…" : partial)
                    .foregroundStyle(.secondary)
                    .padding(10)
            case .done(let reply):
                Text(reply)
                    .padding(10)
                    .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }
}

extension VoiceSession {
    /// Entry point for typed (non-voice) requests from ChatView.
    func respondToTyped(_ text: String) async {
        transcript = text
        do {
            try await respond(to: text)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
