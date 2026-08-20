import Foundation
import AXCore

/// Fake tool implementations used by multi-step eval cases.
///
/// Multi-step cases have to run the *real* `AgentLoop` — that is the whole point, since the
/// chaining behaviour under test (feed the tool response back, let the model use it) lives
/// in the loop, not in the model. But the loop executes what the model calls, so the eval
/// substitutes the registry: real `ToolSpec`s (so the system prompt is byte-for-byte what
/// production sends) wrapped around canned results (so nothing dials, writes, or opens).
struct EvalStubTool: AXTool {
    let spec: ToolSpec
    let respond: @Sendable (ToolCall) -> ToolResult

    func run(_ call: ToolCall) async throws -> ToolResult { respond(call) }
}

enum EvalStubRegistry {

    /// A stub registry mirroring `live`, so a chained case can be scored on the sequence of
    /// calls and the arguments threaded between them.
    ///
    /// `find_contact` returns `EvalStubs.findContactResult`, whose number is the value the
    /// suite asserts on step two. The model can only produce that number by reading step
    /// one's `<tool_response>` — which is exactly the capability being measured.
    static func make(mirroring live: ToolRegistry) -> ToolRegistry {
        ToolRegistry(tools: live.specs.map { spec in
            EvalStubTool(spec: spec) { call in
                switch spec.name {
                case "find_contact":
                    return .ok(EvalStubs.findContactResult(name: call.string("name") ?? ""))
                case "read_next_events":
                    return .ok("9:00 AM: Standup\n1:00 PM: 1:1 with Priya")
                case "call_number":
                    return .ok("Calling \(call.string("number") ?? "").")
                case "compose_message":
                    return .ok("Opened Messages with the draft. The user must tap Send.")
                default:
                    // Generic success: enough for the loop to continue, deliberately
                    // uninformative so a model can't pass a chain by parroting it.
                    return .ok("\(spec.name) completed.")
                }
            }
        })
    }
}

/// Auto-approves `.confirm`-risk tools. The eval measures what the model decides to call;
/// the ConfirmSheet is a separate, human-in-the-loop guarantee and blocking on it would
/// make the suite unrunnable.
struct EvalAutoConfirmer: AgentLoop.Confirmer {
    @MainActor func confirm(call: ToolCall, spec: ToolSpec) async -> Bool { true }
}
