import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    let modelManager: ModelManager
    @State private var newShortcutName = ""

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Section("Model") {
                Picker("Model", selection: Binding(
                    get: { modelManager.choice },
                    set: { modelManager.choice = $0 }
                )) {
                    ForEach(ModelManager.ModelChoice.allCases) { choice in
                        Text("\(choice.displayName) · \(choice.approximateSize)").tag(choice)
                    }
                }
                Button("Delete downloaded model", role: .destructive) {
                    modelManager.deleteDownloadedModel()
                }
            }

            Section("Voice") {
                Toggle("Speak replies aloud", isOn: $settings.speakReplies)
                VStack(alignment: .leading) {
                    Text("End recording after \(settings.silenceTimeout, specifier: "%.1f")s of silence")
                    Slider(value: $settings.silenceTimeout, in: 0.8...3.0, step: 0.1)
                }
            }

            Section {
                ForEach(settings.registeredShortcuts, id: \.self) { name in
                    Text(name)
                }
                .onDelete { settings.registeredShortcuts.remove(atOffsets: $0) }
                HStack {
                    TextField("Exact shortcut name", text: $newShortcutName)
                    Button("Add") {
                        let trimmed = newShortcutName.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !settings.registeredShortcuts.contains(trimmed) else { return }
                        settings.registeredShortcuts.append(trimmed)
                        newShortcutName = ""
                    }
                }
            } header: {
                Text("Shortcuts AX may run")
            } footer: {
                Text("AX can only run Shortcuts you list here, and always asks before running one. Names must match the Shortcuts app exactly.")
            }

            Section {
                NavigationLink("Connectors") { ConnectorsView() }
            } footer: {
                Text("Endpoints and app-summary tasks AX can use by voice.")
            }

            Section("History") {
                NavigationLink("Interaction history") { HistoryView() }
            }

            #if DEBUG
            Section("Developer") {
                NavigationLink("Tool-call eval") { EvalView(modelManager: modelManager) }
                #if AX_DRIVER
                NavigationLink("Driver (experimental)") { DriverView(modelManager: modelManager) }
                #endif
            }
            #endif
        }
        .navigationTitle("Settings")
    }
}
