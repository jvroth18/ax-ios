import Foundation
import AXCore

/// Execution-level validation for the eval: "would this tool accept these arguments?",
/// answered without performing the action.
///
/// ## Why not just call `tool.run(_:)`?
/// Because `run` *is* the side effect. Running `create_reminder` writes to the user's
/// Reminders database, `call_number` dials, `run_shortcut` foregrounds another app. An
/// eval that executed tools would be unrunnable more than once.
///
/// ## Why not add a `validate` method to `AXTool`?
/// That is the cleaner long-term shape and worth doing, but it means editing all twelve
/// tools. This validator instead calls the **same symbols the tools call** —
/// `DateArgument.parse`, `String.iso8601Date`, `OpenAppTool.knownApps` — so the
/// parts that matter most (date parsing, the app table) are not copies at all: they are
/// the production code paths, invoked without the EventKit/UIKit half.
///
/// Where logic genuinely had to be restated (a `> 0` check, a scheme test) it is one line
/// and marked. `AppToolValidator.drift(against:)` then cross-checks this validator against
/// the platform-free `ContractValidator` the Mac-side tests use, so the two descriptions of
/// "what the tools accept" cannot silently diverge — a mismatch is reported in every run.
struct AppToolValidator: ToolExecutionValidating {

    /// `run_shortcut`'s real gate is a registered-name list. The harness passes
    /// `EvalToolCatalog.pinnedShortcuts` rather than `AppState.shared.settings`, so a score
    /// does not depend on what the person running the eval happens to have registered.
    let registeredShortcuts: [String]

    private static let covered: Set<String> = [
        "create_reminder", "create_calendar_event", "read_next_events", "find_contact",
        "call_number", "compose_message", "open_app", "open_url", "set_timer",
        "toggle_flashlight", "play_music", "run_shortcut", "wait", "repeat_steps", "remember",
    ]

    func covers(tool: String) -> Bool { Self.covered.contains(tool) }

    /// Applies the same repair production does, using the live spec when there is one.
    private static func repaired(_ call: ToolCall) -> ToolCall {
        let registry = MainActor.assumeIsolated { ToolRegistry.standard }
        guard let spec = registry.tool(named: call.name)?.spec else { return call }
        return ToolArgumentRepair.repair(call, spec: spec).call
    }

    func rejectionReason(for rawCall: ToolCall) -> String? {
        // Production repairs arguments before executing, so scoring the unrepaired call
        // would fail cases that work on device — the eval would be measuring a code path
        // that no longer exists.
        let call = Self.repaired(rawCall)
        switch call.name {
        case "create_reminder":
            guard let title = call.string("title"), !title.isEmpty else {
                return "missing required argument title"
            }
            guard let due = call.string("due") else { return nil }
            // THE production line, verbatim: RemindersTool.run calls DateArgument.parse and
            // throws AXToolError.badArgument when it returns nil.
            return DateArgument.parse(due) == nil ? "due=\"\(due)\" is not ISO 8601" : nil

        case "create_calendar_event":
            guard let title = call.string("title"), !title.isEmpty else {
                return "missing required argument title"
            }
            guard let start = call.string("start") else { return "missing required argument start" }
            // CalendarCreateTool's line, unchanged.
            return start.iso8601Date == nil ? "start=\"\(start)\" is not ISO 8601" : nil

        case "find_contact":
            let name = call.string("name") ?? ""
            return name.isEmpty ? "missing required argument name" : nil

        case "call_number", "compose_message":
            guard let raw = call.string("number") else { return "missing required argument number" }
            // Restated from CallTool.run (one line). `canOpenURL` is deliberately not
            // called: it answers differently on a simulator than on a phone, and an eval
            // result must not depend on which one you ran it from.
            let digits = raw.filter { $0.isNumber || $0 == "+" }
            guard digits.filter(\.isNumber).count >= 7, URL(string: "tel:\(digits)") != nil else {
                return "number=\"\(raw)\" is not a dialable number"
            }
            if call.name == "compose_message", (call.string("body") ?? "").isEmpty {
                return "missing required argument body"
            }
            return nil

        case "open_app":
            guard let app = call.string("app")?.lowercased() else {
                return "missing required argument app"
            }
            // The production table itself.
            return OpenAppTool.knownApps[app] == nil ? "app=\"\(app)\" is not a known app" : nil

        case "open_url":
            guard let raw = call.string("url"), let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                return "url=\"\(call.string("url") ?? "")\" is not an http(s) URL"
            }
            return nil

        case "set_timer":
            guard let minutes = call.number("minutes"), minutes > 0 else {
                return "minutes must be a positive number"
            }
            return nil

        case "toggle_flashlight":
            let state = call.string("state") ?? ""
            return ["on", "off"].contains(state) ? nil : "state=\"\(state)\" is not on/off"

        case "play_music":
            let action = call.string("action") ?? ""
            return ["play", "pause", "next", "previous"].contains(action)
                ? nil : "action=\"\(action)\" is not a known transport action"

        case "run_shortcut":
            guard let name = call.string("name") else { return "missing required argument name" }
            // ShortcutTool returns a failure (not a throw) for unregistered names; either
            // way the user's request did not happen, which is what the eval cares about.
            return registeredShortcuts.contains(name)
                ? nil : "\"\(name)\" is not a registered shortcut"

        case "remember":
            guard let fact = call.string("fact"),
                  !fact.trimmingCharacters(in: .whitespaces).isEmpty else {
                return "missing required argument fact"
            }
            return nil

        case "wait":
            // WaitTool clamps the value, so any positive number is accepted; only a
            // missing or non-numeric seconds is a rejection.
            guard let seconds = call.number("seconds"), seconds > 0 else {
                return "seconds must be a positive number"
            }
            return nil

        case "repeat_steps":
            guard let steps = call.string("steps"), !steps.trimmingCharacters(in: .whitespaces).isEmpty else {
                return "missing required argument steps"
            }
            let registry = MainActor.assumeIsolated { ToolRegistry.standard }
            do {
                _ = try WorkflowPlan.compile(
                    steps: steps,
                    times: call.int("times") ?? 1,
                    tools: registry.specs.filter { $0.name != "repeat_steps" }
                )
            } catch {
                return String(describing: error)
            }
            return nil

        default:
            return nil
        }
    }

    /// Cross-check against the platform-free contract table used by `swift test` and
    /// `ax-eval`. Any disagreement means one of the two is stale — most likely because a
    /// tool was fixed on device without updating `ContractValidator.axAssistant`.
    ///
    /// Deliberately small and hand-picked: these probes are the arguments whose acceptance
    /// actually decides case outcomes in the suite.
    func drift(against contracts: ContractValidator = .axAssistant) -> [String] {
        let probes: [ToolCall] = [
            ToolCall(name: "create_reminder", arguments: [
                "title": .string("Call mom"), "due": .string("2026-08-19T17:00:00"),
            ]),
            ToolCall(name: "create_reminder", arguments: [
                "title": .string("Call mom"), "due": .string("2026-08-19T17:00:00-04:00"),
            ]),
            ToolCall(name: "create_reminder", arguments: [
                "title": .string("Call mom"), "due": .string("tomorrow at five"),
            ]),
            ToolCall(name: "create_calendar_event", arguments: [
                "title": .string("Lunch"), "start": .string("2026-08-20T12:00:00"),
            ]),
            ToolCall(name: "set_timer", arguments: ["minutes": .number(0)]),
            ToolCall(name: "open_app", arguments: ["app": .string("uber")]),
            ToolCall(name: "open_url", arguments: ["url": .string("example.com")]),
            ToolCall(name: "call_number", arguments: ["number": .string("Dave")]),
            ToolCall(name: "wait", arguments: ["seconds": .number(0.5)]),
            ToolCall(name: "repeat_steps", arguments: [
                "steps": .string("toggle_flashlight:on, wait:0.5"), "times": .number(3),
            ]),
            ToolCall(name: "repeat_steps", arguments: ["steps": .string("")]),
        ]
        return probes.compactMap { probe in
            let mine = rejectionReason(for: probe) != nil
            let theirs = contracts.rejectionReason(for: probe) != nil
            guard mine != theirs else { return nil }
            return "\(EvalJudge.summary(probe)): device says "
                + "\(mine ? "reject" : "accept"), contract table says \(theirs ? "reject" : "accept")"
        }
    }
}
