import Foundation
import AXCore

/// Memoizes read-only tool results for the length of one turn.
///
/// Scoped to a turn on purpose: contacts and calendars change, and a cache that outlives
/// the request would eventually answer a fresh question with a stale fact. Within a single
/// chain — where a model re-asks `find_contact` for the same name it already looked up —
/// the answer cannot have changed.
actor ToolResultCache {
    private var entries: [String: ToolResult] = [:]

    func value(for call: ToolCall) -> ToolResult? { entries[Self.key(call)] }

    func store(_ result: ToolResult, for call: ToolCall) {
        entries[Self.key(call)] = result
    }

    /// Name plus arguments in a stable order, so `{a:1,b:2}` and `{b:2,a:1}` are one entry.
    private static func key(_ call: ToolCall) -> String {
        let arguments = call.arguments
            .map { "\($0.key)=\(String(describing: $0.value))" }
            .sorted()
            .joined(separator: "&")
        return "\(call.name)?\(arguments)"
    }
}
