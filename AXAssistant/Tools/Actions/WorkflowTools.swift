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
    /// Primitive tools are injected so the same executor can run against recording
    /// stubs in the harness. Production passes the standard registry's primitives.
    let primitiveTools: [any AXTool]

    init(primitiveTools: [any AXTool]) {
        self.primitiveTools = primitiveTools
    }

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
                    description: "How many times to repeat the whole sequence (default 1, 1 to 50)"
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
        let times = call.int("times") ?? 1
        let plan: WorkflowPlan
        do {
            plan = try WorkflowPlan.compile(
                steps: raw, times: times, tools: primitiveTools.map(\.spec)
            )
        } catch {
            return .failure(String(describing: error))
        }

        var completed = 0
        let registry = ToolRegistry(tools: primitiveTools)
        for plannedCall in plan.calls {
            // A ten-minute blink the user cannot stop is a bug, not a feature: the
            // turn's Task is cancelled by the Stop button, and a workflow is the one
            // tool long enough for that to matter mid-run.
            if Task.isCancelled {
                return .ok("Stopped after \(completed) actions.")
            }
            guard let tool = registry.tool(named: plannedCall.name) else {
                return .failure("Stopped after \(completed) actions: tool disappeared.")
            }
            do {
                let result = try await tool.run(plannedCall)
                guard result.success else {
                    return .failure("Stopped after \(completed) actions: \(result.content)")
                }
                completed += 1
            } catch {
                return .failure("Stopped after \(completed) actions: \(error.localizedDescription)")
            }
        }

        return .ok(
            "Ran the repeated sequence successfully: "
                + "\(describe(WorkflowStep.parse(raw))) "
                + "\(times == 1 ? "once" : "\(times) times") — \(completed) actions. "
                + "Continue with every remaining action in the original request; "
                + "do not give a final answer until all requested actions have a tool result."
        )
    }

    private func describe(_ steps: [WorkflowStep]) -> String {
        let names = steps.map { step -> String in
            guard let value = step.value else { return step.tool }
            return "\(step.tool) \(value)"
        }
        return names.joined(separator: " → ")
    }

}
