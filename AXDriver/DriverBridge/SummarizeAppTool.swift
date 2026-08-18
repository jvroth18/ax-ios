#if AX_DRIVER
import Foundation
import UIKit
import AXCore

/// Path 2: open an app via WebDriverAgent, capture screenshot(s), and have the on-device
/// vision model summarize what it sees. Read-only — no taps beyond launching the app.
/// This is the realistic AXDriver use case: comprehension is far more forgiving than
/// coordinate-precise tapping for a 2B vision model.
///
/// endsTurn: the summary is spoken as-is. Reloading the text model just to rephrase the
/// VLM's output would cost ~15s and add nothing.
struct SummarizeAppTool: AXTool {
    let spec: ToolSpec
    var endsTurn: Bool { true }

    @MainActor
    init() {
        let connectors = AppState.shared.settings.appSummaryConnectors
        let names = connectors.map { "\"\($0.name)\"" }.joined(separator: ", ")
        spec = ToolSpec(
            name: "summarize_app",
            description: "Open an app on this phone and summarize what its screen shows. Available: \(names)",
            parameters: JSONSchema(
                type: .object,
                properties: [
                    "connector": JSONSchema(type: .string, description: "Exact registered app-summary name"),
                ],
                required: ["connector"]
            ),
            risk: .confirm  // it visibly drives the phone; the user should expect it
        )
    }

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let name = call.string("connector") else { throw AXToolError.missingArgument("connector") }
        let connectors = await MainActor.run { AppState.shared.settings.appSummaryConnectors }
        guard let connector = connectors.first(where: { $0.name.lowercased() == name.lowercased() }) else {
            return .failure("\"\(name)\" is not a registered app summary. Available: \(connectors.map(\.name).joined(separator: ", "))")
        }

        var wda = WDAClient()
        guard await wda.isRunning() else {
            return .failure("WebDriverAgent is not running — start it first (see AXDriver/WDA-SETUP.md).")
        }
        try await wda.createSession()
        try await wda.launchApp(bundleID: connector.bundleID)
        try await Task.sleep(for: .seconds(2))  // let the app settle

        let screen = await MainActor.run { UIScreen.main.bounds.size }
        var screenshots: [UIImage] = [try await wda.screenshot()]
        for _ in 0..<max(0, min(connector.scrolls, 4)) {
            try await wda.scrollUp(screenWidth: screen.width, screenHeight: screen.height)
            try await Task.sleep(for: .milliseconds(700))
            screenshots.append(try await wda.screenshot())
        }

        let planner = try await DriverRuntime.shared.vlm()
        var parts: [String] = []
        for (index, screenshot) in screenshots.enumerated() {
            let framing = screenshots.count > 1 ? " (screen \(index + 1) of \(screenshots.count))" : ""
            let text = try await planner.describe(
                prompt: connector.prompt + framing,
                screenshot: screenshot
            )
            parts.append(text)
        }

        let summary = parts.count == 1
            ? parts[0]
            : parts.enumerated().map { "Part \($0.offset + 1): \($0.element)" }.joined(separator: " ")
        return .ok(summary.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
#endif
