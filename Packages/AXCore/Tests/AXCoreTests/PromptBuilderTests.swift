import XCTest
@testable import AXCore

final class PromptBuilderTests: XCTestCase {

    let tool = ToolSpec(
        name: "create_reminder",
        description: "Create a reminder in the Reminders app",
        parameters: JSONSchema(
            type: .object,
            properties: ["title": JSONSchema(type: .string)],
            required: ["title"]
        ),
        risk: .safe
    )

    func testSystemPromptContainsToolSchemaAndContext() {
        let prompt = PromptBuilder.systemPrompt(
            tools: [tool],
            context: .init(
                currentDateTime: "Monday 2026-08-17 14:00, America/New_York",
                registeredShortcuts: ["Goodnight"]
            )
        )
        XCTAssertTrue(prompt.contains("<tools>"))
        XCTAssertTrue(prompt.contains(#""name":"create_reminder""#))
        XCTAssertTrue(prompt.contains("Create a reminder in the Reminders app"))
        XCTAssertTrue(prompt.contains("Monday 2026-08-17 14:00"))
        XCTAssertTrue(prompt.contains("\"Goodnight\""))
        XCTAssertTrue(prompt.contains("<tool_call>"))
    }

    func testToolJSONIsValidHermesEntry() throws {
        let prompt = PromptBuilder.systemPrompt(
            tools: [tool],
            context: .init(currentDateTime: "2026-08-17")
        )
        // Extract the single line between <tools> and </tools> and confirm it decodes.
        guard let open = prompt.range(of: "<tools>\n"),
              let close = prompt.range(of: "\n</tools>") else {
            return XCTFail("Missing <tools> block")
        }
        let line = String(prompt[open.upperBound..<close.lowerBound])
        let decoded = try JSONDecoder().decode([String: JSONValue].self, from: Data(line.utf8))
        XCTAssertEqual(decoded["type"]?.stringValue, "function")
        XCTAssertEqual(decoded["function"]?.objectValue?["name"]?.stringValue, "create_reminder")
    }

    func testToolResponseRoundTrips() throws {
        let turn = PromptBuilder.toolResponse(.ok("Reminder created"))
        XCTAssertTrue(turn.hasPrefix("<tool_response>"))
        XCTAssertTrue(turn.hasSuffix("</tool_response>"))
        let inner = turn
            .replacingOccurrences(of: "<tool_response>\n", with: "")
            .replacingOccurrences(of: "\n</tool_response>", with: "")
        let decoded = try JSONDecoder().decode([String: JSONValue].self, from: Data(inner.utf8))
        XCTAssertEqual(decoded["success"]?.boolValue, true)
        XCTAssertEqual(decoded["content"]?.stringValue, "Reminder created")
    }

    func testSmallProfileContinuesCompoundRequestsWithoutRepeatingWork() {
        let prompt = PromptBuilder.systemPrompt(
            tools: [tool],
            context: .init(currentDateTime: "2026-08-17"),
            profile: .small
        )
        XCTAssertFalse(prompt.contains("Do exactly one thing per reply"))
        XCTAssertFalse(prompt.contains("Emit at most one tool call per reply"))
        XCTAssertTrue(prompt.contains("call the next unfinished action"))
        XCTAssertTrue(prompt.contains("Never repeat an action whose tool result says it succeeded"))
        XCTAssertTrue(prompt.contains("Never call those inner tools again"))
        XCTAssertTrue(prompt.contains("toggle_flashlight:on, play_music:pause, set_timer:2"))
        XCTAssertTrue(prompt.contains("call_number"))
    }

    /// The prompt and the parser must agree on one format. They drifted apart once —
    /// the prompt taught a zone-less date-time and create_reminder rejected it.
    func testDateRuleTeachesAFormatTheParserAccepts() {
        let prompt = PromptBuilder.systemPrompt(
            tools: [tool],
            context: .init(currentDateTime: "Monday 2026-08-17 14:00, America/New_York")
        )
        XCTAssertTrue(prompt.contains("YYYY-MM-DDTHH:MM:SS"))
        XCTAssertTrue(prompt.contains("2026-08-17T17:00:00"))
        XCTAssertNotNil(DateArgument.parse("2026-08-17T17:00:00"))
        XCTAssertNotNil(DateArgument.parse("2026-08-17"))
    }

    func testPromptSeparatesGreetingsFromExplicitRepeatedActions() {
        let prompt = PromptBuilder.systemPrompt(
            tools: [tool],
            context: .init(currentDateTime: "Monday 2026-08-17 14:00, America/New_York")
        )
        XCTAssertTrue(prompt.contains("Greetings and small talk never use a tool"))
        XCTAssertTrue(prompt.contains("Turn the flashlight on and off 5 times"))
        XCTAssertTrue(prompt.contains(#""times": 5"#))
    }
}
