import Foundation
import AXCore

/// Pause between actions. Exists so "toggle the light, wait, toggle it back" is
/// expressible at all — without it the model's only way to space actions out is to
/// stall the whole agent loop, which it cannot do.
struct WaitTool: AXTool {
    static let maxSeconds: Double = 30

    let spec = ToolSpec(
        name: "wait",
        description: "Pause for a number of seconds before the next action.",
        parameters: JSONSchema(
            type: .object,
            properties: [
                "seconds": JSONSchema(type: .number, description: "How long to pause, 0.1 to 30"),
            ],
            required: ["seconds"]
        ),
        risk: .safe
    )

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let seconds = call.number("seconds") else {
            throw AXToolError.missingArgument("seconds")
        }
        let clamped = min(max(seconds, 0), Self.maxSeconds)
        try? await Task.sleep(for: .seconds(clamped))
        return .ok("Waited \(Self.format(clamped)) seconds.")
    }

    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// Runs a short sequence of one-argument steps, optionally repeated.
///
/// WHY this exists: the agent loop hands control back to the model between every tool
/// call, so "blink the light ten times" would be 30+ generate→execute cycles — minutes
/// of latency, a prompt that grows every cycle, and a count that a 1.7B loses track of
/// by step four. One `repeat_steps` call collapses the whole repetitive part into a
/// single deterministic execution, leaving the model to do only what models are good at:
/// deciding *what* the loop is.
///
/// The step list is a flat string (`"toggle_flashlight:on, wait:0.5"`) rather than
/// nested JSON for two reasons: `JSONSchema` deliberately cannot express arrays of
/// objects, and small models emit flat strings far more reliably than nested structures.
struct RepeatStepsTool: AXTool {
    static let maxTimes = 50
    static let maxTotalSteps = 200
    /// Total sleeping time allowed in one call, so a workflow can't wedge the app.
    static let maxTotalWaitSeconds: Double = 120

    let spec = ToolSpec(
        name: "repeat_steps",
        description: """
        Run a sequence of simple actions, optionally repeating it. Use this for anything \
        repetitive ("blink the light 10 times", "toggle it on and off with a pause"). \
        Steps are written as "tool:value" separated by commas, using each tool's single \
        main argument, e.g. "toggle_flashlight:on, wait:0.5, toggle_flashlight:off, wait:0.5". \
        Only tools with one required argument can be used as steps, and actions that need \
        confirmation (calls, messages, shortcuts, calendar events) cannot be repeated — \
        call those directly instead.
        """,
        parameters: JSONSchema(
            type: .object,
            properties: [
                "steps": JSONSchema(
                    type: .string,
                    description: "Comma-separated \"tool:value\" steps, in order"
                ),
                "times": JSONSchema(
                    type: .integer,
                    description: "How many times to repeat the whole sequence (default 1, max 50)"
                ),
            ],
            required: ["steps"]
        ),
        risk: .safe
    )

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let raw = call.string("steps"), !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AXToolError.missingArgument("steps")
        }
        let steps = WorkflowStep.parse(raw)
        guard !steps.isEmpty else {
            throw AXToolError.badArgument("steps", "could not read any \"tool:value\" steps")
        }
        let times = min(max(call.int("times") ?? 1, 1), Self.maxTimes)
        guard steps.count * times <= Self.maxTotalSteps else {
            return .failure("That's \(steps.count * times) actions — too many for one go (limit \(Self.maxTotalSteps)).")
        }

        // Resolve against the live registry, minus this tool (no recursion).
        let registry = await MainActor.run { ToolRegistry.standard }
        var plan: [(tool: any AXTool, call: ToolCall)] = []
        var totalWait: Double = 0
        for step in steps {
            guard step.tool != spec.name else {
                return .failure("A workflow can't contain another workflow — put the steps in this one.")
            }
            guard let tool = registry.tool(named: step.tool) else {
                return .failure("I don't have a tool called \"\(step.tool)\".")
            }
            guard tool.spec.risk != .confirm else {
                return .failure("\"\(step.tool)\" needs confirmation each time, so it can't run inside a repeat. Ask for it directly.")
            }
            let arguments = try step.arguments(for: tool.spec)
            if tool.spec.name == "wait", let seconds = arguments["seconds"]?.numberValue {
                totalWait += seconds * Double(times)
            }
            plan.append((tool, ToolCall(name: tool.spec.name, arguments: arguments)))
        }
        guard totalWait <= Self.maxTotalWaitSeconds else {
            return .failure("That would spend \(Int(totalWait))s waiting — keep a workflow under \(Int(Self.maxTotalWaitSeconds))s.")
        }

        var completed = 0
        for _ in 0..<times {
            for entry in plan {
                do {
                    let result = try await entry.tool.run(entry.call)
                    guard result.success else {
                        return .failure("Stopped after \(completed) actions: \(result.content)")
                    }
                    completed += 1
                } catch {
                    return .failure("Stopped after \(completed) actions: \(error.localizedDescription)")
                }
            }
        }

        return .ok("Ran \(describe(steps)) \(times == 1 ? "once" : "\(times) times") — \(completed) actions.")
    }

    private func describe(_ steps: [WorkflowStep]) -> String {
        let names = steps.map { step -> String in
            guard let value = step.value else { return step.tool }
            return "\(step.tool) \(value)"
        }
        return names.joined(separator: " → ")
    }

}
