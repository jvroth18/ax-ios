import Foundation
import AXCore

/// The action catalog: builds the tool section of the system prompt and dispatches calls.
struct ToolRegistry: Sendable {
    let tools: [any AXTool]

    var specs: [ToolSpec] { tools.map(\.spec) }

    func tool(named name: String) -> (any AXTool)? {
        tools.first { $0.spec.name == name }
    }

    /// The default catalog, rebuilt per request: http_request's spec embeds the live
    /// connector allowlist. Every tool here works with free-account entitlements.
    @MainActor
    static var standard: ToolRegistry {
        var tools: [any AXTool] = [
            RemindersTool(),
            CalendarCreateTool(),
            CalendarReadTool(),
            ContactsTool(),
            CallTool(),
            MessageTool(),
            OpenAppTool(),
            OpenURLTool(),
            TimerTool(),
            FlashlightTool(),
            MorseFlashlightTool(),
            MusicTool(),
            ShortcutTool(),
            RememberTool(),
            WaitTool(),
        ]
        // Inject primitives into the workflow executor. This keeps the production path
        // simple while allowing evals to substitute recording tools and test expansion.
        tools.append(RepeatStepsTool(primitiveTools: tools))
        if !AppState.shared.settings.endpointConnectors.isEmpty {
            tools.append(HTTPRequestTool())
        }
        #if AX_DRIVER
        if !AppState.shared.settings.appSummaryConnectors.isEmpty {
            tools.append(SummarizeAppTool())
        }
        #endif
        return ToolRegistry(tools: tools)
    }
}
