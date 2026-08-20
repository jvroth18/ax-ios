import XCTest
@testable import AXCore

/// The step string is model-authored, so these cases are the shapes small models actually
/// produce when asked for the same workflow — not just the one the prompt shows them.
final class WorkflowStepTests: XCTestCase {

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
    private let calendar = ToolSpec(
        name: "create_calendar_event",
        description: "Create an event",
        parameters: JSONSchema(
            type: .object,
            properties: ["title": JSONSchema(type: .string), "start": JSONSchema(type: .string)],
            required: ["title", "start"]
        ),
        risk: .confirm
    )

    func testParsesCanonicalForm() {
        let steps = WorkflowStep.parse("toggle_flashlight:on, wait:0.5, toggle_flashlight:off, wait:0.5")
        XCTAssertEqual(steps, [
            .init(tool: "toggle_flashlight", value: "on"),
            .init(tool: "wait", value: "0.5"),
            .init(tool: "toggle_flashlight", value: "off"),
            .init(tool: "wait", value: "0.5"),
        ])
    }

    func testParsesAlternateSeparatorsAndWrappers() {
        // Semicolons, equals, parens, brackets, stray quotes and newlines all observed.
        let steps = WorkflowStep.parse("""
        ["toggle_flashlight=on"; wait(1)
        toggle_flashlight = off]
        """)
        XCTAssertEqual(steps, [
            .init(tool: "toggle_flashlight", value: "on"),
            .init(tool: "wait", value: "1"),
            .init(tool: "toggle_flashlight", value: "off"),
        ])
    }

    func testIgnoresEmptyPiecesAndValuelessSteps() {
        let steps = WorkflowStep.parse("wait:1, , toggle_flashlight")
        XCTAssertEqual(steps, [
            .init(tool: "wait", value: "1"),
            .init(tool: "toggle_flashlight", value: nil),
        ])
    }

    func testMapsValueOntoTheSingleRequiredArgumentWithSchemaType() throws {
        let flash = try WorkflowStep(tool: "toggle_flashlight", value: "on").arguments(for: flashlight)
        XCTAssertEqual(flash["state"]?.stringValue, "on")

        let pause = try WorkflowStep(tool: "wait", value: "0.5").arguments(for: wait)
        XCTAssertEqual(pause["seconds"]?.numberValue, 0.5)
    }

    func testRejectsMultiArgumentToolsAsSteps() {
        XCTAssertThrowsError(
            try WorkflowStep(tool: "create_calendar_event", value: "Lunch").arguments(for: calendar)
        ) { error in
            XCTAssertEqual(
                error as? WorkflowStep.ParseError,
                .tooManyArguments(tool: "create_calendar_event", count: 2)
            )
        }
    }

    func testRejectsNonNumericValueForNumericArgument() {
        XCTAssertThrowsError(
            try WorkflowStep(tool: "wait", value: "a moment").arguments(for: wait)
        ) { error in
            XCTAssertEqual(
                error as? WorkflowStep.ParseError,
                .notANumber(argument: "seconds", value: "a moment")
            )
        }
    }

    func testRejectsStepMissingItsValue() {
        XCTAssertThrowsError(
            try WorkflowStep(tool: "wait", value: nil).arguments(for: wait)
        ) { error in
            XCTAssertEqual(
                error as? WorkflowStep.ParseError,
                .missingValue(tool: "wait", argument: "seconds")
            )
        }
    }
}
