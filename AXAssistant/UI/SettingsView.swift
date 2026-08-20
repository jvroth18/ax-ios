import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    let modelManager: ModelManager
    let onClose: () -> Void
    let onMinimize: () -> Void
    @State private var newShortcutName = ""

    var body: some View {
        @Bindable var settings = appState.settings

        W95Window(title: "Settings", onClose: onClose, onMinimize: onMinimize) {
            NavigationStack {
                VStack(spacing: 4) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            W95GroupBox(label: "Agent") {
                HStack(spacing: 10) {
                    Text("Tool chain limit: \(settings.maxToolIterations)")
                        .font(W95.ui(12))
                    Stepper("", value: $settings.maxToolIterations, in: 1...8)
                        .labelsHidden()
                }
                Text("How many tools AX may chain in one request. Higher = more capable multi-step actions, slower worst case.")
                    .font(W95.ui(11))
                    .foregroundStyle(W95.shadow)
                Toggle("Send only relevant tools (faster, experimental)", isOn: $settings.pruneToolsInPrompt)
                    .toggleStyle(W95CheckboxStyle())
                Text("The full tool list costs ~1,700 tokens of prompt on every step. Narrowing it is faster but can hide a tool from the model.")
                    .font(W95.ui(11))
                    .foregroundStyle(W95.shadow)
            }

            W95GroupBox(label: "Voice") {
                                Toggle("Speak replies aloud", isOn: $settings.speakReplies)
                                    .toggleStyle(W95CheckboxStyle())
                                Toggle("Kokoro voice (natural, on-device)", isOn: $settings.useKokoroVoice)
                                    .toggleStyle(W95CheckboxStyle())
                                if settings.useKokoroVoice {
                                    Picker("Voice", selection: $settings.kokoroVoice) {
                                        ForEach(KokoroSpeaker.voices, id: \.id) { voice in
                                            Text(voice.label).tag(voice.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(W95.navy)
                                    Text("Kokoro-82M, a small open TTS model. First use downloads ~330 MB; runs fully on-device beside the language model.")
                                        .font(W95.ui(11))
                                        .foregroundStyle(W95.shadow)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("End recording after \(settings.silenceTimeout, specifier: "%.1f")s of silence")
                                        .font(W95.ui(12))
                                    Slider(value: $settings.silenceTimeout, in: 0.8...3.0, step: 0.1)
                                        .tint(W95.navy)
                                }
                            }

                            W95GroupBox(label: "Shortcuts AX may run") {
                                if settings.registeredShortcuts.isEmpty {
                                    Text("(none registered)")
                                        .font(W95.ui(12))
                                        .foregroundStyle(W95.shadow)
                                } else {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(settings.registeredShortcuts, id: \.self) { name in
                                            HStack {
                                                Text(name).font(W95.ui(12))
                                                Spacer()
                                                Button("✕") {
                                                    settings.registeredShortcuts.removeAll { $0 == name }
                                                }
                                                .buttonStyle(W95ButtonStyle())
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                        }
                                    }
                                    .w95Well(background: .white)
                                }
                                HStack(spacing: 4) {
                                    TextField("Exact shortcut name", text: $newShortcutName)
                                        .font(W95.ui(12))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .w95Well(background: .white)
                                    Button("Add") {
                                        let trimmed = newShortcutName.trimmingCharacters(in: .whitespaces)
                                        guard !trimmed.isEmpty, !settings.registeredShortcuts.contains(trimmed) else { return }
                                        settings.registeredShortcuts.append(trimmed)
                                        newShortcutName = ""
                                    }
                                    .buttonStyle(W95ButtonStyle())
                                }
                                Text("AX can only run Shortcuts listed here, and always asks first. Names must match the Shortcuts app exactly.")
                                    .font(W95.ui(11))
                                    .foregroundStyle(W95.shadow)
                            }

                            W95GroupBox(label: "What AX remembers about you") {
                                if UserMemoryStore.shared.facts.isEmpty {
                                    Text("(nothing yet — AX saves facts you tell it about yourself)")
                                        .font(W95.ui(11))
                                        .foregroundStyle(W95.shadow)
                                } else {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(UserMemoryStore.shared.facts, id: \.self) { fact in
                                            HStack(alignment: .top) {
                                                Text(fact).font(W95.ui(12))
                                                Spacer()
                                                Button("✕") { UserMemoryStore.shared.forget(fact) }
                                                    .buttonStyle(W95ButtonStyle())
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                        }
                                    }
                                    .w95Well(background: .white)
                                    Button("Forget everything") { UserMemoryStore.shared.forgetAll() }
                                        .buttonStyle(W95ButtonStyle())
                                }
                            }

                            W95GroupBox(label: "More") {
                                link("Connectors") { ConnectorsView() }
                                // SwiftData store creation can take seconds on a cold
                                // launch. History is secondary, so open its container only
                                // when the user actually enters this screen.
                                link("Interaction history") {
                                    HistoryView().modelContainer(for: Interaction.self)
                                }
                                #if DEBUG
                                link("Tool-call eval") { EvalView(modelManager: modelManager) }
                                #if AX_DRIVER
                                link("Driver (experimental)") { DriverView(modelManager: modelManager) }
                                #endif
                                #endif
                            }
                        }
                        .padding(8)
                    }
                    .w95Well(background: W95.face)
                    W95StatusBar(fields: ["AX — on-device model runner"])
                }
                .padding(4)
                .background(W95.face)
                .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    /// Blue underlined hyperlink — the 90s-web way to go somewhere.
    private func link(_ title: String, destination: @escaping () -> some View) -> some View {
        NavigationLink { destination() } label: {
            Text(title)
                .font(W95.ui(13))
                .foregroundStyle(W95.link)
                .underline()
        }
        .buttonStyle(.plain)
    }
}
