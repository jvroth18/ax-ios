import XCTest
@testable import AXCore

final class ToolCallParserTests: XCTestCase {

    let tools: [ToolSpec] = [
        ToolSpec(
            name: "create_reminder",
            description: "Create a reminder",
            parameters: JSONSchema(
                type: .object,
                properties: [
                    "title": JSONSchema(type: .string, description: "Reminder text"),
                    "due": JSONSchema(type: .string, description: "ISO 8601 due date"),
                ],
                required: ["title"]
            ),
            risk: .safe
        ),
        ToolSpec(
            name: "set_timer",
            description: "Start a timer",
            parameters: JSONSchema(
                type: .object,
                properties: ["minutes": JSONSchema(type: .integer)],
                required: ["minutes"]
            ),
            risk: .safe
        ),
        ToolSpec(
            name: "toggle_flashlight",
            description: "Turn the flashlight on or off",
            parameters: JSONSchema(
                type: .object,
                properties: ["state": JSONSchema(type: .string, enumValues: ["on", "off"])],
                required: ["state"]
            ),
            risk: .safe
        ),
    ]

    func testParsesSingleValidCall() throws {
        let output = """
        <tool_call>
        {"name": "create_reminder", "arguments": {"title": "Call mom", "due": "2026-08-17T17:00:00"}}
        </tool_call>
        """
        let parsed = try ToolCallParser.parse(output, tools: tools)
        XCTAssertEqual(parsed.toolCalls.count, 1)
        XCTAssertEqual(parsed.toolCalls[0].name, "create_reminder")
        XCTAssertEqual(parsed.toolCalls[0].string("title"), "Call mom")
        XCTAssertEqual(parsed.text, "")
    }

    func testParsesBareJSONCallWithoutTags() throws {
        let output = """
        {"name": "toggle_flashlight", "arguments": {"state": "on"}}
        """
        let parsed = try ToolCallParser.parse(output, tools: tools)
        XCTAssertEqual(parsed.toolCalls.count, 1)
        XCTAssertEqual(parsed.toolCalls[0].name, "toggle_flashlight")
        XCTAssertEqual(parsed.toolCalls[0].string("state"), "on")
        XCTAssertEqual(parsed.text, "")
    }

    func testParsesMultipleBareJSONCallLines() throws {
        let output = """
        {"name": "toggle_flashlight", "arguments": {"state": "on"}}
        {"name": "set_timer", "arguments": {"minutes": 10}}
        """
        let parsed = try ToolCallParser.parse(output, tools: tools)
        XCTAssertEqual(parsed.toolCalls.map(\.name), ["toggle_flashlight", "set_timer"])
    }

    func testBareJSONWithoutNameIsText() throws {
        let output = #"{"answer": "It is 72 degrees outside."}"#
        let parsed = try ToolCallParser.parse(output, tools: tools)
        XCTAssertTrue(parsed.toolCalls.isEmpty)
        XCTAssertEqual(parsed.text, output)
    }

    func testBareJSONUnknownToolThrows() {
        let output = #"{"name": "warp_drive", "arguments": {}}"#
        XCTAssertThrowsError(try ToolCallParser.parse(output, tools: tools)) { error in
            XCTAssertEqual(error as? ToolCallParseError, .unknownTool(name: "warp_drive"))
        }
    }

    func testBareJSONInvalidArgsThrows() {
        let output = #"{"name": "toggle_flashlight", "arguments": {"state": "sideways"}}"#
        XCTAssertThrowsError(try ToolCallParser.parse(output, tools: tools))
    }

    func testStraysThinkTagsAreStripped() throws {
        let output = """
        {"name": "toggle_flashlight", "arguments": {"state": "on"}}</think>
        """
        let parsed = try ToolCallParser.parse(output, tools: tools)
        XCTAssertEqual(parsed.toolCalls.count, 1)
        XCTAssertEqual(parsed.toolCalls[0].name, "toggle_flashlight")
    }

    func testStripsThinkBlockAndKeepsSurroundingText() throws {
        let output = """
        <think>The user wants a timer. minutes = 10.</think>
        Sure, starting a 10 minute timer.
        <tool_call>
        {"name": "set_timer", "arguments": {"minutes": 10}}
        </tool_call>
        """
        let parsed = try ToolCallParser.parse(output, tools: tools)
        XCTAssertEqual(parsed.toolCalls.count, 1)
        XCTAssertEqual(parsed.toolCalls[0].int("minutes"), 10)
        XCTAssertEqual(parsed.text, "Sure, starting a 10 minute timer.")
    }

    func testParsesMultipleCalls() throws {
        let output = """
        <tool_call>
        {"name": "set_timer", "arguments": {"minutes": 5}}
        </tool_call>
        <tool_call>
        {"name": "toggle_flashlight", "arguments": {"state": "on"}}
        </tool_call>
        """
        let parsed = try ToolCallParser.parse(output, tools: tools)
        XCTAssertEqual(parsed.toolCalls.map(\.name), ["set_timer", "toggle_flashlight"])
    }

    func testPlainTextHasNoCalls() throws {
        let parsed = try ToolCallParser.parse("It's a beautiful day.", tools: tools)
        XCTAssertTrue(parsed.toolCalls.isEmpty)
        XCTAssertEqual(parsed.text, "It's a beautiful day.")
    }

    func testMalformedJSONThrows() {
        let output = "<tool_call>{not json at all</tool_call>"
        XCTAssertThrowsError(try ToolCallParser.parse(output, tools: tools)) { error in
            guard case ToolCallParseError.malformedJSON = error else {
                return XCTFail("Expected malformedJSON, got \(error)")
            }
        }
    }

    func testUnknownToolThrows() {
        let output = #"<tool_call>{"name": "launch_missiles", "arguments": {}}</tool_call>"#
        XCTAssertThrowsError(try ToolCallParser.parse(output, tools: tools)) { error in
            XCTAssertEqual(error as? ToolCallParseError, .unknownTool(name: "launch_missiles"))
        }
    }

    func testMissingRequiredArgumentThrows() {
        let output = #"<tool_call>{"name": "create_reminder", "arguments": {"due": "2026-08-18"}}</tool_call>"#
        XCTAssertThrowsError(try ToolCallParser.parse(output, tools: tools)) { error in
            XCTAssertEqual(
                error as? ToolCallParseError,
                .missingRequiredArgument(tool: "create_reminder", argument: "title")
            )
        }
    }

    func testTypeMismatchThrows() {
        let output = #"<tool_call>{"name": "set_timer", "arguments": {"minutes": "ten"}}</tool_call>"#
        XCTAssertThrowsError(try ToolCallParser.parse(output, tools: tools)) { error in
            XCTAssertEqual(
                error as? ToolCallParseError,
                .typeMismatch(tool: "set_timer", argument: "minutes", expected: "integer")
            )
        }
    }

    func testEnumViolationThrows() {
        let output = #"<tool_call>{"name": "toggle_flashlight", "arguments": {"state": "blinking"}}</tool_call>"#
        XCTAssertThrowsError(try ToolCallParser.parse(output, tools: tools)) { error in
            guard case ToolCallParseError.typeMismatch(_, "state", _) = error else {
                return XCTFail("Expected enum typeMismatch, got \(error)")
            }
        }
    }

    func testUnclosedToolCallTagIsTreatedAsText() throws {
        let output = #"<tool_call>{"name": "set_timer""#
        let parsed = try ToolCallParser.parse(output, tools: tools)
        XCTAssertTrue(parsed.toolCalls.isEmpty)
        XCTAssertEqual(parsed.text, output)
    }
}
