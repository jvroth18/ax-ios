import Foundation
import AXCore

/// The action catalog: builds the tool section of the system prompt and dispatches calls.
struct ToolRegistry: Sendable {
    let tools: [any AXTool]

    var specs: [ToolSpec] { tools.map(\.spec) }

    func tool(named name: String) -> (any AXTool)? {
        tools.first { $0.spec.name == name }
    }

    /// The default catalog. Every tool here works with free-account entitlements.
    static let standard = ToolRegistry(tools: [
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
        MusicTool(),
        ShortcutTool(),
    ])
}
