import Foundation

/// A validated, deterministic sequence compiled from a model-authored workflow string.
/// The model chooses the cycle once; execution and counting are ordinary code after that.
public struct WorkflowPlan: Sendable, Equatable {
    public static let maxTimes = 50
    public static let maxActions = 200
    public static let maxWaitSeconds: Double = 120
    public static let minimumFlashlightDwellSeconds: Double = 0.25
    /// Repeating side-effectful tools is intentionally narrow. A one-pass sequence may
    /// use any safe one-argument tool, but a loop may only contain these reversible,
    /// naturally repeatable actions.
    public static let repeatedActionAllowlist: Set<String> = [
        "toggle_flashlight", "play_music", "wait",
    ]

    public let cycle: [ToolCall]
    public let calls: [ToolCall]
    public let times: Int
    public let totalWaitSeconds: Double

    public enum CompilationError: Error, Equatable, CustomStringConvertible {
        case empty
        case timesOutOfRange(Int)
        case tooManyActions(Int)
        case unknownTool(String)
        case recursive
        case confirmationRequired(String)
        case notRepeatable(String)
        case invalidStep(String)
        case waitOutOfRange(Double)
        case tooMuchWaiting(Double)

        public var description: String {
            switch self {
            case .empty: return "I couldn't read any tool:value steps."
            case .timesOutOfRange(let times):
                return "Repeat count \(times) is outside 1...\(WorkflowPlan.maxTimes)."
            case .tooManyActions(let count):
                return "That's \(count) actions — the limit is \(WorkflowPlan.maxActions)."
            case .unknownTool(let name): return "I don't have a tool called \"\(name)\"."
            case .recursive: return "A workflow can't contain another workflow."
            case .confirmationRequired(let name):
                return "\"\(name)\" needs confirmation, so it must be called directly."
            case .notRepeatable(let name):
                return "\"\(name)\" can run in a sequence once, but it can't be repeated."
            case .invalidStep(let reason): return reason
            case .waitOutOfRange(let seconds):
                return "A wait must be greater than 0 and at most 30 seconds, got \(seconds)."
            case .tooMuchWaiting(let seconds):
                return "That would spend \(Int(seconds))s waiting — the limit is \(Int(WorkflowPlan.maxWaitSeconds))s."
            }
        }
    }

    public static func compile(
        steps raw: String,
        times: Int = 1,
        tools: [ToolSpec]
    ) throws -> WorkflowPlan {
        guard (1...maxTimes).contains(times) else {
            throw CompilationError.timesOutOfRange(times)
        }
        let parsed = WorkflowStep.parse(raw)
        guard !parsed.isEmpty else { throw CompilationError.empty }
        let catalog = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
        var cycle: [ToolCall] = []
        var waitPerCycle: Double = 0
        for step in parsed {
            guard step.tool != "repeat_steps" else { throw CompilationError.recursive }
            guard let spec = catalog[step.tool] else {
                throw CompilationError.unknownTool(step.tool)
            }
            guard spec.risk != .confirm else {
                throw CompilationError.confirmationRequired(step.tool)
            }
            if times > 1, !repeatedActionAllowlist.contains(spec.name) {
                throw CompilationError.notRepeatable(spec.name)
            }
            let arguments: [String: JSONValue]
            do {
                arguments = try step.arguments(for: spec)
            } catch {
                throw CompilationError.invalidStep(String(describing: error))
            }
            if spec.name == "wait", let seconds = arguments["seconds"]?.numberValue {
                guard seconds > 0, seconds <= 30 else {
                    throw CompilationError.waitOutOfRange(seconds)
                }
                waitPerCycle += seconds
            }
            cycle.append(ToolCall(name: spec.name, arguments: arguments))
        }

        // Small models sometimes omit pauses from "flash on and off". Without a dwell,
        // the hardware changes state too quickly to see and the user reasonably reports
        // that nothing happened. Make repeated flashlight cycles perceptible even when
        // the generated plan only contains on/off.
        if times > 1, catalog["wait"] != nil, cycle.contains(where: { $0.name == "toggle_flashlight" }) {
            var perceptible: [ToolCall] = []
            for (index, call) in cycle.enumerated() {
                perceptible.append(call)
                let nextIsWait = cycle.indices.contains(index + 1) && cycle[index + 1].name == "wait"
                if call.name == "toggle_flashlight", !nextIsWait {
                    perceptible.append(ToolCall(
                        name: "wait",
                        arguments: ["seconds": .number(minimumFlashlightDwellSeconds)]
                    ))
                    waitPerCycle += minimumFlashlightDwellSeconds
                }
            }
            cycle = perceptible
        }

        let actionCount = cycle.count * times
        guard actionCount <= maxActions else { throw CompilationError.tooManyActions(actionCount) }

        let totalWait = waitPerCycle * Double(times)
        guard totalWait <= maxWaitSeconds else {
            throw CompilationError.tooMuchWaiting(totalWait)
        }
        return WorkflowPlan(
            cycle: cycle,
            calls: (0..<times).flatMap { _ in cycle },
            times: times,
            totalWaitSeconds: totalWait
        )
    }
}
