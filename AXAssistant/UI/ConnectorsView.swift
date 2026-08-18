import SwiftUI

/// Configure the connectors the model may use: HTTP endpoints (http_request tool) and
/// app-summary tasks (summarize_app tool, AXDriver builds). The lists here ARE the
/// allowlists — the model can only reference entries by name.
struct ConnectorsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingEndpointForm = false
    @State private var showingAppSummaryForm = false

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Section {
                ForEach(settings.endpointConnectors) { connector in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connector.name).font(.headline)
                        Text("\(connector.method) \(connector.url)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if !connector.descriptionForModel.isEmpty {
                            Text(connector.descriptionForModel)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .onDelete { settings.endpointConnectors.remove(atOffsets: $0) }
                Button("Add endpoint") { showingEndpointForm = true }
            } header: {
                Text("Endpoints")
            } footer: {
                Text("HTTPS endpoints AX may call by voice (\"check my talky stats\"). AX always asks before calling one. The model can only use endpoints listed here.")
            }

            Section {
                ForEach(settings.appSummaryConnectors) { connector in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connector.name).font(.headline)
                        Text("\(connector.bundleID) · \(connector.scrolls + 1) screen\(connector.scrolls == 0 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { settings.appSummaryConnectors.remove(atOffsets: $0) }
                Button("Add app summary") { showingAppSummaryForm = true }
            } header: {
                Text("App summaries")
            } footer: {
                Text("\"Open this app and read the screen to me\" tasks. Requires the experimental AXDriver build with WebDriverAgent running — configuration is saved either way.")
            }
        }
        .navigationTitle("Connectors")
        .sheet(isPresented: $showingEndpointForm) {
            EndpointForm { settings.endpointConnectors.append($0) }
        }
        .sheet(isPresented: $showingAppSummaryForm) {
            AppSummaryForm { settings.appSummaryConnectors.append($0) }
        }
    }
}

private struct EndpointForm: View {
    let onSave: (EndpointConnector) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = "https://"
    @State private var method = "GET"
    @State private var hint = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (how you'll say it)", text: $name)
                TextField("URL (https)", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Method", selection: $method) {
                    Text("GET").tag("GET")
                    Text("POST").tag("POST")
                }
                TextField("What it returns (helps the model)", text: $hint)
            }
            .navigationTitle("New endpoint")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(EndpointConnector(
                            name: name.trimmingCharacters(in: .whitespaces),
                            url: url, method: method, descriptionForModel: hint
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !url.hasPrefix("https://"))
                }
            }
        }
    }
}

private struct AppSummaryForm: View {
    let onSave: (AppSummaryConnector) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var bundleID = ""
    @State private var scrolls = 1
    @State private var prompt = "Summarize what is shown on this screen in 2-3 spoken sentences."

    /// Common apps so users don't have to hunt for bundle identifiers.
    private static let known: [(String, String)] = [
        ("X", "com.atebits.Tweetie2"),
        ("LinkedIn", "com.linkedin.LinkedIn"),
        ("Mail", "com.apple.mobilemail"),
        ("Messages", "com.apple.MobileSMS"),
        ("Slack", "com.tinyspeck.chatlyio"),
        ("Reddit", "com.reddit.Reddit"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (how you'll say it)", text: $name)
                Picker("App", selection: $bundleID) {
                    Text("Custom…").tag("")
                    ForEach(Self.known, id: \.1) { app in
                        Text(app.0).tag(app.1)
                    }
                }
                TextField("Bundle ID", text: $bundleID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Stepper("Screens to read: \(scrolls + 1)", value: $scrolls, in: 0...4)
                TextField("Prompt for the vision model", text: $prompt, axis: .vertical)
            }
            .navigationTitle("New app summary")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(AppSummaryConnector(
                            name: name.trimmingCharacters(in: .whitespaces),
                            bundleID: bundleID, scrolls: scrolls, prompt: prompt
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || bundleID.isEmpty)
                }
            }
        }
    }
}
