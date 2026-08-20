import XCTest
@testable import AXCore

final class WorkflowPlanTests: XCTestCase {
    private let flashlight = ToolSpec(
        name: "toggle_flashlight",
        description: "Turn the flashlight on or off",
        parameters: JSONSchema(
            type: .object,
            properties: ["state": JSONSchema(type: .string, enumValues: ["on", "off"])],
            required: ["state"]
        ),
        risk: .safe
    )
    private let wait = ToolSpec(
        name: "wait",
        description: "Pause",
        parameters: JSONSchema(
            type: .object,
            properties: ["seconds": JSONSchema(type: .number)],
            required: ["seconds"]
        ),
        risk: .safe
    )
    private let message = ToolSpec(
        name: "compose_message",
        description: "Draft a message",
        parameters: JSONSchema(
            type: .object,
            properties: ["body": JSONSchema(type: .string)],
            required: ["body"]
        ),
        risk: .confirm
    )

    func testCompilesTenFlashlightCyclesToExactlyTwentyOrderedCalls() throws {
        let plan = try WorkflowPlan.compile(
            steps: "toggle_flashlight:on, toggle_flashlight:off",
            times: 10,
            tools: [flashlight, wait]
        )

        XCTAssertEqual(
            plan.cycle.filter { $0.name == "toggle_flashlight" }.map { $0.string("state") },
            ["on", "off"]
        )
        XCTAssertEqual(plan.calls.count, 40)
        XCTAssertEqual(
            plan.calls.filter { $0.name == "toggle_flashlight" }.map { $0.string("state") ?? "" },
            Array(repeating: ["on", "off"], count: 10).flatMap { $0 }
        )
        XCTAssertEqual(plan.totalWaitSeconds, 5)
    }

    func testCompilesArbitraryThenSequenceOnce() throws {
        let plan = try WorkflowPlan.compile(
            steps: "toggle_flashlight:on, wait:0.25, toggle_flashlight:off",
            tools: [flashlight, wait]
        )

        XCTAssertEqual(plan.calls.map(\.name), ["toggle_flashlight", "wait", "toggle_flashlight"])
        XCTAssertEqual(plan.totalWaitSeconds, 0.25)
    }

    func testRejectsUnknownInvalidConfirmedAndRecursiveSteps() {
        XCTAssertThrowsError(try WorkflowPlan.compile(steps: "missing:on", tools: [flashlight]))
        XCTAssertThrowsError(try WorkflowPlan.compile(steps: "toggle_flashlight:blink", tools: [flashlight]))
        XCTAssertThrowsError(try WorkflowPlan.compile(steps: "compose_message:hello", tools: [message]))

        let repeatSpec = ToolSpec(
            name: "repeat_steps", description: "Repeat", parameters: JSONSchema(type: .object), risk: .safe
        )
        XCTAssertThrowsError(try WorkflowPlan.compile(steps: "repeat_steps:anything", tools: [repeatSpec]))
    }

    func testRejectsRatherThanSilentlyClampingLimits() {
        XCTAssertThrowsError(
            try WorkflowPlan.compile(steps: "toggle_flashlight:on", times: 51, tools: [flashlight])
        )
        XCTAssertThrowsError(
            try WorkflowPlan.compile(steps: "wait:30", times: 5, tools: [wait])
        )
        XCTAssertThrowsError(
            try WorkflowPlan.compile(steps: "wait:31", tools: [wait])
        )
    }
}
