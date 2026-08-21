import XCTest
@testable import AXCore

/// The execution-validation layer, tested directly. These assertions encode what the
/// shipping tools accept; if a tool is fixed, a test here should fail and be updated,
/// which is the point — the contract table is not allowed to rot quietly.
final class ToolContractTests: XCTestCase {
    private let validator = ContractValidator.axAssistant

    private func call(_ name: String, _ arguments: [String: JSONValue]) -> ToolCall {
        ToolCall(name: name, arguments: arguments)
    }

    /// Regression guard for the create_reminder date bug: the zone-less spelling the
    /// system prompt teaches must survive the tool's own parser.
    func testCreateReminderAcceptsTheSpellingThePromptTeaches() {
        XCTAssertNil(validator.rejectionReason(for: call("create_reminder", [
            "title": .string("Call mom"), "due": .string("2026-08-19T17:00:00"),
        ])))
        XCTAssertNil(validator.rejectionReason(for: call("create_reminder", [
            "title": .string("Call mom"), "due": .string("2026-08-19T17:00:00-04:00"),
        ])))
        XCTAssertNil(validator.rejectionReason(for: call("create_reminder", [
            "title": .string("Buy milk"),
        ])))
    }

    /// The bug, reconstructed. A tool that reaches for `ISO8601DateFormatter` instead of
    /// `DateArgument` rejects its own prompt's example — and this validator says so, which
    /// is the capability the whole execution layer exists to provide.
    func testStrictISOContractStillCatchesTheHistoricalBug() {
        let strict = ContractValidator(contracts: [
            ToolContract(
                tool: "create_reminder",
                required: ["title"],
                arguments: ["due": .iso8601RequiringZone]
            ),
        ])
        let why = strict.rejectionReason(for: call("create_reminder", [
            "title": .string("Call mom"), "due": .string("2026-08-19T17:00:00"),
        ]))
        XCTAssertNotNil(why)
        XCTAssertTrue(why!.contains("UTC offset"), why!)
        XCTAssertNil(strict.rejectionReason(for: call("create_reminder", [
            "title": .string("Call mom"), "due": .string("2026-08-19T17:00:00-04:00"),
        ])))
    }

    func testBothDateToolsNowShareOneParser() {
        // Same string, same verdict — the asymmetry that made the bug survivable is gone.
        for tool in ["create_reminder", "create_calendar_event"] {
            let key = tool == "create_reminder" ? "due" : "start"
            XCTAssertNil(validator.rejectionReason(for: call(tool, [
                "title": .string("Lunch"), key: .string("2026-08-20T12:00:00"),
            ])), tool)
            XCTAssertNotNil(validator.rejectionReason(for: call(tool, [
                "title": .string("Lunch"), key: .string("tomorrow at noon"),
            ])), tool)
        }
    }

    func testMissingRequiredArgument() {
        XCTAssertEqual(
            validator.rejectionReason(for: call("create_reminder", [:])),
            "missing required argument title"
        )
    }

    func testTimerRejectsNonPositiveDurations() {
        XCTAssertNil(validator.rejectionReason(for: call("set_timer", ["minutes": .number(1.5)])))
        XCTAssertNotNil(validator.rejectionReason(for: call("set_timer", ["minutes": .number(0)])))
        XCTAssertNotNil(
            validator.rejectionReason(for: call("set_timer", ["minutes": .string("ten")]))
        )
    }

    func testOpenURLRequiresAScheme() {
        XCTAssertNil(validator.rejectionReason(for: call("open_url", [
            "url": .string("https://example.com"),
        ])))
        // A bare hostname is what a model usually emits, and OpenURLTool throws on it.
        XCTAssertNotNil(validator.rejectionReason(for: call("open_url", [
            "url": .string("example.com"),
        ])))
    }

    func testEnumeratedArgumentsAreCheckedAgainstTheRealTables() {
        XCTAssertNil(validator.rejectionReason(for: call("open_app", ["app": .string("Maps")])))
        XCTAssertNotNil(validator.rejectionReason(for: call("open_app", ["app": .string("uber")])))
        XCTAssertNotNil(
            validator.rejectionReason(for: call("play_music", ["action": .string("stop")]))
        )
    }

    func testDialableNumbers() {
        XCTAssertNil(validator.rejectionReason(for: call("call_number", [
            "number": .string("+1 (415) 555-0147"),
        ])))
        XCTAssertNotNil(validator.rejectionReason(for: call("call_number", [
            "number": .string("Dave"),
        ])))
    }

    func testMorseTextRunsTheShippingEncoderContract() {
        XCTAssertTrue(validator.covers(tool: "signal_morse_code"))
        XCTAssertNil(validator.rejectionReason(for: call("signal_morse_code", [
            "text": .string("SOS"),
        ])))
        XCTAssertNotNil(validator.rejectionReason(for: call("signal_morse_code", [:])))
        XCTAssertNotNil(validator.rejectionReason(for: call("signal_morse_code", [
            "text": .string("SOS 🚀"),
        ])))
        XCTAssertNotNil(validator.rejectionReason(for: call("signal_morse_code", [
            "text": .string(String(repeating: "0", count: 64)),
        ])))
    }

    func testUnknownToolsAreNotClaimedAsCovered() {
        XCTAssertFalse(validator.covers(tool: "http_request"))
        XCTAssertNil(validator.rejectionReason(for: call("http_request", [:])))
    }
}
