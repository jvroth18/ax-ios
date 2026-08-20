import XCTest
@testable import AXCore

/// The repairs are only safe if they never change meaning. Half of these cases exist to
/// prove the repairer *declines* to fix things — an argument it guesses at is worse than
/// one that fails loudly.
final class ToolArgumentRepairTests: XCTestCase {

    private let timer = ToolSpec(
        name: "set_timer",
        description: "Start a countdown timer",
        parameters: JSONSchema(
            type: .object,
            properties: [
                "minutes": JSONSchema(type: .number, description: "Duration"),
                "label": JSONSchema(type: .string, description: "Optional label"),
            ],
            required: ["minutes"]
        ),
        risk: .safe
    )
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

    func testCoercesNumericStringToNumber() {
        let outcome = ToolArgumentRepair.repair(
            ToolCall(name: "set_timer", arguments: ["minutes": .string("10")]), spec: timer
        )
        XCTAssertEqual(outcome.call.arguments["minutes"]?.numberValue, 10)
        XCTAssertTrue(outcome.didRepair)
    }

    func testCoercesBareNumberToStringArgument() {
        let outcome = ToolArgumentRepair.repair(
            ToolCall(name: "set_timer", arguments: [
                "minutes": .number(5), "label": .number(3),
            ]), spec: timer
        )
        XCTAssertEqual(outcome.call.arguments["label"]?.stringValue, "3")
    }

    func testNormalizesEnumCaseOnly() {
        let outcome = ToolArgumentRepair.repair(
            ToolCall(name: "toggle_flashlight", arguments: ["state": .string("ON")]), spec: flashlight
        )
        XCTAssertEqual(outcome.call.arguments["state"]?.stringValue, "on")
    }

    func testCanonicalizesArgumentNameCase() {
        let outcome = ToolArgumentRepair.repair(
            ToolCall(name: "toggle_flashlight", arguments: ["State": .string("off")]), spec: flashlight
        )
        XCTAssertEqual(outcome.call.arguments["state"]?.stringValue, "off")
        XCTAssertNil(outcome.call.arguments["State"])
    }

    func testStripsWrappingQuotesAndPadding() {
        let outcome = ToolArgumentRepair.repair(
            ToolCall(name: "set_timer", arguments: [
                "minutes": .number(1), "label": .string("  \"Tea\"  "),
            ]), spec: timer
        )
        XCTAssertEqual(outcome.call.arguments["label"]?.stringValue, "Tea")
    }

    // MARK: - Things it must NOT do

    func testLeavesValueOutsideEnumAlone() {
        let outcome = ToolArgumentRepair.repair(
            ToolCall(name: "toggle_flashlight", arguments: ["state": .string("bright")]), spec: flashlight
        )
        XCTAssertEqual(outcome.call.arguments["state"]?.stringValue, "bright")
        XCTAssertFalse(outcome.didRepair, "guessing an enum value would silently do the wrong thing")
    }

    func testLeavesUnparseableNumberAlone() {
        let outcome = ToolArgumentRepair.repair(
            ToolCall(name: "set_timer", arguments: ["minutes": .string("a while")]), spec: timer
        )
        XCTAssertEqual(outcome.call.arguments["minutes"]?.stringValue, "a while")
        XCTAssertFalse(outcome.didRepair)
    }

    func testDoesNotInventMissingArguments() {
        let outcome = ToolArgumentRepair.repair(
            ToolCall(name: "set_timer", arguments: [:]), spec: timer
        )
        XCTAssertTrue(outcome.call.arguments.isEmpty)
        XCTAssertFalse(outcome.didRepair)
    }

    func testCorrectCallIsUntouched() {
        let call = ToolCall(name: "set_timer", arguments: [
            "minutes": .number(10), "label": .string("Pasta"),
        ])
        let outcome = ToolArgumentRepair.repair(call, spec: timer)
        XCTAssertFalse(outcome.didRepair)
        XCTAssertEqual(outcome.call.arguments, call.arguments)
    }
}
