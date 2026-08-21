import Foundation
import UIKit
import AXCore

/// Runs a user Shortcut via the Shortcuts x-callback-url scheme. This is the escape hatch
/// for everything App Intents can't reach: the user builds a Shortcut ("Goodnight",
/// "Log water", …), registers its name in Morse Settings, and the model may then call it.
///
/// Mechanics: opening the URL foregrounds the Shortcuts app; on completion, Shortcuts
/// calls back into axassistant://shortcut-result?result=… which AXAssistantApp routes to
/// `handleCallback`. If the user set no output, the callback still fires with no result.
struct ShortcutTool: AXTool {
    let spec = ToolSpec(
        name: "run_shortcut",
        description: """
        Run one of the user's registered Shortcuts by exact name, optionally passing text input. \
        Only names the user registered are allowed.
        """,
        parameters: JSONSchema(
            type: .object,
            properties: [
                "name": JSONSchema(type: .string, description: "Exact registered shortcut name"),
                "input": JSONSchema(type: .string, description: "Optional text input"),
            ],
            required: ["name"]
        ),
        risk: .confirm
    )

    private static let pending = PendingCallback()

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let name = call.string("name") else { throw AXToolError.missingArgument("name") }
        let registered = await MainActor.run { AppState.shared.settings.registeredShortcuts }
        guard registered.contains(name) else {
            return .failure("\"\(name)\" is not a registered shortcut. Registered: \(registered.joined(separator: ", "))")
        }

        var components = URLComponents(string: "shortcuts://x-callback-url/run-shortcut")!
        var query = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "x-success", value: "axassistant://shortcut-result"),
            URLQueryItem(name: "x-error", value: "axassistant://shortcut-error"),
        ]
        if let input = call.string("input") {
            query.append(URLQueryItem(name: "input", value: "text"))
            query.append(URLQueryItem(name: "text", value: input))
        }
        components.queryItems = query

        let url = components.url!
        await MainActor.run { UIApplication.shared.open(url) }

        // Wait for the x-callback round trip (user may take a while if the shortcut asks questions)
        let outcome = await Self.pending.wait(timeout: 60)
        switch outcome {
        case .success(let result):
            return .ok(result.map { "Shortcut \"\(name)\" finished. Output: \($0)" }
                       ?? "Shortcut \"\(name)\" finished.")
        case .error(let message):
            return .failure("Shortcut \"\(name)\" failed: \(message)")
        case .timeout:
            return .ok("Shortcut \"\(name)\" was started, but didn't report back within 60s.")
        }
    }

    /// Called from AXAssistantApp.onOpenURL.
    static func handleCallback(url: URL) {
        guard url.scheme == "axassistant" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let value = { (name: String) in components?.queryItems?.first { $0.name == name }?.value }
        switch url.host {
        case "shortcut-result":
            Task { await pending.resolve(.success(result: value("result"))) }
        case "shortcut-error":
            Task { await pending.resolve(.error(message: value("errorMessage") ?? "unknown error")) }
        default:
            break
        }
    }

    enum Outcome: Sendable {
        case success(result: String?)
        case error(message: String)
        case timeout
    }

    /// Serializes one in-flight shortcut round trip.
    actor PendingCallback {
        private var continuation: CheckedContinuation<Outcome, Never>?

        func wait(timeout: TimeInterval) async -> Outcome {
            let watchdog = Task {
                try? await Task.sleep(for: .seconds(timeout))
                self.resolve(.timeout)
            }
            defer { watchdog.cancel() }
            return await withCheckedContinuation { self.continuation = $0 }
        }

        func resolve(_ outcome: Outcome) {
            continuation?.resume(returning: outcome)
            continuation = nil
        }
    }
}
