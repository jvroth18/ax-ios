import Foundation

/// Something that can say, without side effects, whether a tool would accept a call.
///
/// The app supplies a version backed by the *real* tool symbols (see
/// `AXAssistant/LLM/EvalDryRun.swift`); `ContractValidator` below is the platform-free
/// stand-in that lets `swift test` and the CLI exercise the same scoring path on a Mac,
/// where EventKit/AlarmKit/UIKit are unavailable.
public protocol ToolExecutionValidating: Sendable {
    func covers(tool: String) -> Bool
    /// nil when the tool would run; a reason string when it would throw.
    func rejectionReason(for call: ToolCall) -> String?
}

/// One argument's runtime requirement — the thing the tool's `run` actually enforces,
/// which the JSON Schema in the prompt does *not* express. The schema says `due` is a
/// string; it cannot say "and it must carry a UTC offset or the tool throws".
public enum ArgumentContract: Sendable, Equatable, Codable {
    /// The production date parser itself — `DateArgument.parse`, the exact call
    /// `RemindersTool` and `CalendarCreateTool` make. Not a mirror: this contract runs the
    /// shipping code, minus EventKit.
    case dateArgument
    /// `ISO8601DateFormatter(.withInternetDateTime)`, which REQUIRES an explicit zone.
    ///
    /// No shipping tool uses this any more — `RemindersTool` did until the DateArgument
    /// fix, and it is why "remind me at 5pm" threw on the zone-less string the prompt
    /// itself teaches. Kept because it is the failure this harness was built to catch, it
    /// is what any future tool that reaches for a formatter directly will do again, and
    /// `EvalJudgeTests` uses it to prove the eval detects the bug rather than asserting so.
    case iso8601RequiringZone
    case positiveNumber
    case httpURL
    case dialableNumber
    case nonEmptyString
    case memberOf([String])
    /// A `repeat_steps` step list that reads as at least one "tool:value" step. Partial by
    /// construction: whether each named tool exists, is repeatable, and takes one argument
    /// is only knowable against a live registry, so that half is checked on device.
    case workflowSteps

    func rejectionReason(tool: String, argument: String, value: JSONValue) -> String? {
        switch self {
        case .dateArgument:
            let raw = ArgumentMatcher.display(value)
            return DateArgument.parse(raw) == nil
                ? "\(argument)=\"\(raw)\" is not a date-time AX can parse" : nil
        case .iso8601RequiringZone:
            let raw = ArgumentMatcher.display(value)
            if !EvalDateParser.hasExplicitZone(raw) {
                return "\(argument)=\"\(raw)\" has no UTC offset; ISO8601DateFormatter(.withInternetDateTime) returns nil → throws badArgument"
            }
            return EvalDateParser.parse(raw, timeZone: TimeZone(identifier: "America/New_York")!) == nil
                ? "\(argument)=\"\(raw)\" is not ISO 8601" : nil
        case .positiveNumber:
            guard let number = ArgumentMatcher.coerceNumber(value) else {
                return "\(argument)=\"\(ArgumentMatcher.display(value))\" is not a number"
            }
            return number > 0 ? nil : "\(argument)=\(ArgumentMatcher.trim(number)) must be positive"
        case .httpURL:
            let raw = ArgumentMatcher.display(value)
            guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return "\(argument)=\"\(raw)\" is not an http(s) URL"
            }
            return nil
        case .dialableNumber:
            let raw = ArgumentMatcher.display(value)
            let digits = raw.filter { $0.isNumber || $0 == "+" }
            guard digits.filter(\.isNumber).count >= 7, URL(string: "tel:\(digits)") != nil else {
                return "\(argument)=\"\(raw)\" is not a dialable number"
            }
            return nil
        case .nonEmptyString:
            let raw = ArgumentMatcher.display(value).trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? "\(argument) is empty" : nil
        case .workflowSteps:
            guard let text = value.stringValue, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                return "steps must be a non-empty string"
            }
            return WorkflowStep.parse(text).isEmpty
                ? "steps=\"\(text)\" has no readable \"tool:value\" step" : nil
        case .memberOf(let allowed):
            let raw = ArgumentMatcher.display(value).lowercased()
            return allowed.contains(where: { $0.lowercased() == raw })
                ? nil : "\(argument)=\"\(raw)\" is not one of [\(allowed.joined(separator: ", "))]"
        }
    }
}

public struct ToolContract: Sendable, Equatable, Codable {
    public let tool: String
    public let required: [String]
    public let arguments: [String: ArgumentContract]

    public init(tool: String, required: [String] = [], arguments: [String: ArgumentContract] = [:]) {
        self.tool = tool
        self.required = required
        self.arguments = arguments
    }
}

/// Platform-free execution validator.
///
/// HONEST LIMITATION, stated up front: this table is a *declaration* of what the shipping
/// tools accept, not the tools themselves — AXCore cannot import EventKit/AlarmKit/UIKit,
/// and running the real `run(_:)` would place calls and write to the user's Reminders.
/// Two things keep the declaration honest:
///   1. The app-side validator (`AppToolValidator`) calls the genuine app symbols, and the
///      harness cross-checks it against this table, reporting `contractDrift` when the two
///      disagree — so fixing a tool without updating this table is loud, not silent.
///   2. `reject` probe cases assert the validator refuses what it claims to refuse.
public struct ContractValidator: ToolExecutionValidating {
    public let contracts: [String: ToolContract]

    public init(contracts: [ToolContract]) {
        self.contracts = Dictionary(uniqueKeysWithValues: contracts.map { ($0.tool, $0) })
    }

    public func covers(tool: String) -> Bool { contracts[tool] != nil }

    public func rejectionReason(for call: ToolCall) -> String? {
        guard let contract = contracts[call.name] else { return nil }
        for key in contract.required where call.arguments[key] == nil || call.arguments[key] == .null {
            return "missing required argument \(key)"
        }
        // Sorted so a call violating two contracts always reports the same one.
        for key in contract.arguments.keys.sorted() {
            guard let value = call.arguments[key], value != .null else { continue }
            if let reason = contract.arguments[key]?.rejectionReason(
                tool: call.name, argument: key, value: value
            ) {
                return reason
            }
        }
        return nil
    }

    /// The shipped tools, as of the AXAssistant tool catalog.
    ///
    /// Both date arguments run the real `DateArgument.parse`. They did not always agree:
    /// `RemindersTool` used to parse with `ISO8601DateFormatter(.withInternetDateTime)` and
    /// threw on the zone-less string the prompt teaches, while `CalendarCreateTool` took a
    /// forgiving path and accepted it. Generation-only scoring could not see the
    /// difference, so the reminder bug survived 43 commits with the eval reporting 9/9.
    /// These contracts are the regression guard for that.
    public static let axAssistant = ContractValidator(contracts: [
        ToolContract(
            tool: "create_reminder",
            required: ["title"],
            arguments: ["title": .nonEmptyString, "due": .dateArgument]
        ),
        ToolContract(
            tool: "create_calendar_event",
            required: ["title", "start"],
            arguments: ["title": .nonEmptyString, "start": .dateArgument]
        ),
        ToolContract(tool: "read_next_events"),
        ToolContract(tool: "find_contact", required: ["name"], arguments: ["name": .nonEmptyString]),
        ToolContract(tool: "call_number", required: ["number"], arguments: ["number": .dialableNumber]),
        ToolContract(
            tool: "compose_message",
            required: ["number", "body"],
            arguments: ["number": .dialableNumber, "body": .nonEmptyString]
        ),
        ToolContract(
            tool: "open_app",
            required: ["app"],
            arguments: ["app": .memberOf(EvalToolCatalog.knownApps)]
        ),
        ToolContract(tool: "open_url", required: ["url"], arguments: ["url": .httpURL]),
        ToolContract(tool: "set_timer", required: ["minutes"], arguments: ["minutes": .positiveNumber]),
        ToolContract(
            tool: "toggle_flashlight",
            required: ["state"],
            arguments: ["state": .memberOf(["on", "off"])]
        ),
        ToolContract(
            tool: "play_music",
            required: ["action"],
            arguments: ["action": .memberOf(["play", "pause", "next", "previous"])]
        ),
        // Partial: run_shortcut's real gate is the user's registered-shortcut list in
        // SettingsStore, which AXCore cannot see. Only the argument shape is checked here.
        ToolContract(tool: "run_shortcut", required: ["name"], arguments: ["name": .nonEmptyString]),
        ToolContract(tool: "wait", required: ["seconds"], arguments: ["seconds": .positiveNumber]),
        // Partial: only the step *syntax* is checked here. Whether each step names a real,
        // repeatable, single-argument tool needs the live registry, so `AppToolValidator`
        // carries that half on device.
        ToolContract(tool: "repeat_steps", required: ["steps"], arguments: ["steps": .workflowSteps]),
    ])
}
