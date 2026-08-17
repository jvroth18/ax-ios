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
}
