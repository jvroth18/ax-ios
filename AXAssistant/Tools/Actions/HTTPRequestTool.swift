import Foundation
import AXCore

/// Calls a user-registered endpoint connector. The model chooses BY NAME from the
/// allowlist configured in Settings > Connectors — it can never supply a raw URL,
/// so the only data egress possible is to endpoints the user explicitly added.
struct HTTPRequestTool: AXTool {
    let spec: ToolSpec

    @MainActor
    init() {
        let connectors = AppState.shared.settings.endpointConnectors
        let catalog = connectors.isEmpty
            ? "No connectors registered yet."
            : connectors.map { connector in
                let hint = connector.descriptionForModel.isEmpty ? "" : " — \(connector.descriptionForModel)"
                return "\"\(connector.name)\"\(hint)"
            }.joined(separator: "; ")
        spec = ToolSpec(
            name: "http_request",
            description: "Call one of the user's registered endpoint connectors and return the response. Available: \(catalog)",
            parameters: JSONSchema(
                type: .object,
                properties: [
                    "connector": JSONSchema(type: .string, description: "Exact registered connector name"),
                    "body": JSONSchema(type: .string, description: "Optional request body (POST only)"),
                ],
                required: ["connector"]
            ),
            risk: .confirm
        )
    }

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let name = call.string("connector") else { throw AXToolError.missingArgument("connector") }
        let connectors = await MainActor.run { AppState.shared.settings.endpointConnectors }
        guard let connector = connectors.first(where: { $0.name.lowercased() == name.lowercased() }) else {
            return .failure("\"\(name)\" is not a registered connector.")
        }
        guard let url = URL(string: connector.url), url.scheme == "https" else {
            return .failure("Connector \"\(connector.name)\" has an invalid URL (https required).")
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = connector.method
        if connector.method == "POST", let body = call.string("body") {
            request.httpBody = Data(body.utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? "(non-text response, \(data.count) bytes)"
        let truncated = text.count > 2000 ? String(text.prefix(2000)) + "…" : text
        guard (200..<300).contains(status) else {
            return .failure("\(connector.name) returned HTTP \(status): \(truncated)")
        }
        return .ok(truncated)
    }
}
