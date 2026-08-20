import XCTest
@testable import AXCore

final class EvalJudgeTests: XCTestCase {

    private func toolCall(_ name: String, _ arguments: [String: JSONValue] = [:]) -> ToolCall {
        ToolCall(name: name, arguments: arguments)
    }

    private func completion(_ name: String, _ argumentsJSON: String) -> String {
        "<tool_call>\n{\"name\": \"\(name)\", \"arguments\": \(argumentsJSON)}\n</tool_call>"
    }

    // MARK: - The bug the old harness scored as a pass, 43 commits running

    /// End-to-end regression guard: the completion the system prompt asks for must pass
    /// both halves — right instant, and arguments the shipping tool actually accepts.
    func testZonelessReminderDatePassesEndToEnd() throws {
        let evalCase = try XCTUnwrap(EvalSuite.all.first { $0.id == "date-reminder-5pm-today" })
        let judged = EvalJudge.judge(
            evalCase,
            completion: completion(
                "create_reminder",
                #"{"title": "Call mom", "due": "2026-08-19T17:00:00"}"#
            ),
            tools: EvalToolCatalog.specs
        )
        XCTAssertEqual(judged.outcome, .pass)
        XCTAssertTrue(judged.executionCovered)
    }

    /// The reason this harness exists, demonstrated rather than asserted: rerun the exact
    /// same completion against the pre-fix contract (RemindersTool parsing `due` with
    /// `ISO8601DateFormatter(.withInternetDateTime)`) and the case fails as
    /// `executionRejected` — while generation-only scoring, the old harness's only mode,
    /// still calls it a pass.
    func testTheHarnessWouldHaveCaughtTheReminderDateBug() throws {
        let evalCase = try XCTUnwrap(EvalSuite.all.first { $0.id == "date-reminder-5pm-today" })
        let raw = completion(
            "create_reminder",
            #"{"title": "Call mom", "due": "2026-08-19T17:00:00"}"#
        )
        let buggy = ContractValidator(contracts: [
            ToolContract(
                tool: "create_reminder",
                required: ["title"],
                arguments: ["due": .iso8601RequiringZone]
            ),
        ])

        // Arguments alone: correct. This is all the old harness ever looked at — and it
        // did not even look this hard, since `["due": nil]` asserted key existence only.
        let argumentsOnly = EvalJudge.judge(
            evalCase, completion: raw, tools: EvalToolCatalog.specs, validator: nil
        )
        XCTAssertTrue(argumentsOnly.passed)
        XCTAssertFalse(argumentsOnly.executionCovered, "no validator ⇒ execution unchecked")

        let judged = EvalJudge.judge(
            evalCase, completion: raw, tools: EvalToolCatalog.specs, validator: buggy
        )
        guard case .executionRejected(let tool, let why) = judged.outcome else {
            return XCTFail("expected executionRejected, got \(judged.outcome)")
        }
        XCTAssertEqual(tool, "create_reminder")
        XCTAssertTrue(why.contains("UTC offset"), why)
    }

    func testFullyQualifiedReminderDatePasses() throws {
        let evalCase = try XCTUnwrap(EvalSuite.all.first { $0.id == "date-reminder-5pm-today" })
        let judged = EvalJudge.judge(
            evalCase,
            completion: completion(
                "create_reminder",
                #"{"title": "Call mom", "due": "2026-08-19T17:00:00-04:00"}"#
            ),
            tools: EvalToolCatalog.specs
        )
        XCTAssertEqual(judged.outcome, .pass)
        XCTAssertTrue(judged.executionCovered)
    }

    /// The calendar side of the same spelling. Both tools now share `DateArgument`; this
    /// keeps them from diverging again.
    func testCalendarAcceptsTheSameSpelling() throws {
        let evalCase = try XCTUnwrap(
            EvalSuite.all.first { $0.id == "date-calendar-lunch-tomorrow-noon" }
        )
        let judged = EvalJudge.judge(
            evalCase,
            completion: completion(
                "create_calendar_event",
                #"{"title": "Lunch with Sarah", "start": "2026-08-20T12:00:00"}"#
            ),
            tools: EvalToolCatalog.specs
        )
        XCTAssertEqual(judged.outcome, .pass)
    }

    func testWrongDateFailsEvenWhenTheKeyIsPresent() throws {
        let evalCase = try XCTUnwrap(
            EvalSuite.all.first { $0.id == "date-calendar-lunch-tomorrow-noon" }
        )
        let judged = EvalJudge.judge(
            evalCase,
            completion: completion(
                "create_calendar_event",
                #"{"title": "Lunch with Sarah", "start": "1999-01-01T12:00:00Z"}"#
            ),
            tools: EvalToolCatalog.specs
        )
        guard case .badArgument(_, let argument, _) = judged.outcome else {
            return XCTFail("expected badArgument, got \(judged.outcome)")
        }
        XCTAssertEqual(argument, "start")
    }

    func testInventedDueDateFails() throws {
        let evalCase = try XCTUnwrap(EvalSuite.all.first { $0.id == "date-reminder-no-time" })
        let judged = EvalJudge.judge(
            evalCase,
            completion: completion(
                "create_reminder",
                #"{"title": "Buy milk", "due": "2026-08-20T09:00:00-04:00"}"#
            ),
            tools: EvalToolCatalog.specs
        )
        guard case .badArgument(_, let argument, let why) = judged.outcome else {
            return XCTFail("expected badArgument, got \(judged.outcome)")
        }
        XCTAssertEqual(argument, "due")
        XCTAssertTrue(why.contains("should not be set"), why)
    }

    // MARK: - Negative and ambiguity

    func testNegativeCasePassesOnPlainText() throws {
        let evalCase = try XCTUnwrap(EvalSuite.all.first { $0.id == "negative-capital-of-france" })
        let judged = EvalJudge.judge(
            evalCase, completion: "Paris.", tools: EvalToolCatalog.specs
        )
        XCTAssertEqual(judged.outcome, .pass)
    }

    func testNegativeCaseRejectsSilence() throws {
        let evalCase = try XCTUnwrap(EvalSuite.all.first { $0.id == "negative-joke" })
        XCTAssertEqual(
            EvalJudge.judge(evalCase, completion: "   ", tools: EvalToolCatalog.specs).outcome,
            .emptyReply
        )
    }

    func testNegativeCaseFailsOnAnyToolCall() throws {
        let evalCase = try XCTUnwrap(EvalSuite.all.first { $0.id == "negative-minutes-in-a-day" })
        let judged = EvalJudge.judge(
            evalCase,
            completion: completion("set_timer", #"{"minutes": 1440}"#),
            tools: EvalToolCatalog.specs
        )
        XCTAssertEqual(judged.outcome, .unexpectedCall("set_timer"))
    }

    func testAmbiguityRequiresAQuestion() throws {
        let evalCase = try XCTUnwrap(EvalSuite.all.first { $0.id == "ambiguous-set-a-timer" })
        XCTAssertEqual(
            EvalJudge.judge(
                evalCase, completion: "How long should I set it for?", tools: EvalToolCatalog.specs
            ).outcome,
            .pass
        )
        guard case .notAQuestion = EvalJudge.judge(
            evalCase, completion: "Sure thing.", tools: EvalToolCatalog.specs
        ).outcome else {
            return XCTFail("a bare acknowledgement is not a clarifying question")
        }
        // Guessing a duration is the failure this class exists to catch.
        XCTAssertEqual(
            EvalJudge.judge(
                evalCase,
                completion: completion("set_timer", #"{"minutes": 5}"#),
                tools: EvalToolCatalog.specs
            ).outcome,
            .unexpectedCall("set_timer")
        )
    }

    // MARK: - Every call is scored, not just the first

    func testExtraCallFailsInsteadOfBeingIgnored() throws {
        let evalCase = try XCTUnwrap(EvalSuite.all.first { $0.id == "extra-flashlight-and-joke" })
        let raw = completion("toggle_flashlight", #"{"state": "on"}"#)
            + "\n" + completion("create_reminder", #"{"title": "Tell a joke"}"#)
        let judged = EvalJudge.judge(evalCase, completion: raw, tools: EvalToolCatalog.specs)
        XCTAssertEqual(judged.outcome, .spuriousExtraCall("create_reminder"))
        XCTAssertEqual(judged.emittedCalls.count, 2, "both calls are recorded in the report")
    }

    func testTwoLegitimateCallsStillPass() throws {
        let evalCase = try XCTUnwrap(EvalSuite.all.first { $0.id == "extra-two-legitimate-calls" })
        let raw = completion("read_next_events", "{}")
            + "\n" + completion("create_reminder", #"{"title": "Water the plants"}"#)
        XCTAssertEqual(
            EvalJudge.judge(evalCase, completion: raw, tools: EvalToolCatalog.specs).outcome,
            .pass
        )
    }

    func testUnorderedCasesToleratePermutedCalls() throws {
        let evalCase = try XCTUnwrap(EvalSuite.all.first { $0.id == "extra-two-legitimate-calls" })
        let raw = completion("create_reminder", #"{"title": "Water the plants"}"#)
            + "\n" + completion("read_next_events", "{}")
        XCTAssertEqual(
            EvalJudge.judge(evalCase, completion: raw, tools: EvalToolCatalog.specs).outcome,
            .pass
        )
    }

    // MARK: - Multi-step

    func testMultiStepChecksOrderAndArgumentThreading() throws {
        let evalCase = try XCTUnwrap(EvalSuite.all.first { $0.id == "multi-call-dave" })
        let good = [
            toolCall("find_contact", ["name": .string("Dave")]),
            toolCall("call_number", ["number": .string("+14155550147")]),
        ]
        XCTAssertEqual(
            EvalJudge.judge(evalCase, calls: good, replyText: "Calling Dave.").outcome, .pass
        )

        // Right tools, wrong order: call_number cannot have known the number yet.
        let reversed = Array(good.reversed())
        guard case .wrongTool = EvalJudge.judge(
            evalCase, calls: reversed, replyText: ""
        ).outcome else {
            return XCTFail("ordered case should reject a reversed chain")
        }

        // A hallucinated number instead of the one step one returned.
        let hallucinated = [
            good[0], toolCall("call_number", ["number": .string("+15551234567")]),
        ]
        guard case .badArgument(_, let argument, _) = EvalJudge.judge(
            evalCase, calls: hallucinated, replyText: ""
        ).outcome else {
            return XCTFail("expected the threaded number to be checked")
        }
        XCTAssertEqual(argument, "number")
    }

    func testMissingSecondStepIsReportedAsMissingNotWrongTool() throws {
        let evalCase = try XCTUnwrap(EvalSuite.all.first { $0.id == "multi-call-dave" })
        let judged = EvalJudge.judge(
            evalCase,
            calls: [toolCall("find_contact", ["name": .string("Dave")])],
            replyText: "Dave's number is +1 415 555 0147."
        )
        XCTAssertEqual(judged.outcome, .missingCall(
            expected: "call_number", text: "Dave's number is +1 415 555 0147."
        ))
    }

    // MARK: - Failure shapes

    func testWrongToolIsNamedOnBothSides() throws {
        let evalCase = try XCTUnwrap(EvalSuite.all.first { $0.id == "date-reminder-in-20-minutes" })
        let judged = EvalJudge.judge(
            evalCase,
            completion: completion("set_timer", #"{"minutes": 20}"#),
            tools: EvalToolCatalog.specs
        )
        XCTAssertEqual(judged.outcome, .wrongTool(expected: "create_reminder", got: "set_timer"))
    }

    func testNoCallOnAToolCaseIsAMissingCall() throws {
        let evalCase = try XCTUnwrap(EvalSuite.all.first { $0.id == "single-flashlight-on" })
        let judged = EvalJudge.judge(
            evalCase, completion: "I'll turn on the flashlight.", tools: EvalToolCatalog.specs
        )
        XCTAssertEqual(judged.outcome, .missingCall(
            expected: "toggle_flashlight", text: "I'll turn on the flashlight."
        ))
    }

    func testMalformedCompletionIsScoredNotSkipped() throws {
        let evalCase = try XCTUnwrap(EvalSuite.all.first { $0.id == "single-flashlight-on" })
        let judged = EvalJudge.judge(
            evalCase,
            completion: "<tool_call>\n{\"name\": \"make_toast\", \"arguments\": {}}\n</tool_call>",
            tools: EvalToolCatalog.specs
        )
        guard case .parseError = judged.outcome else {
            return XCTFail("an unknown tool must be a scored failure, got \(judged.outcome)")
        }
    }

    /// Argument failures are reported deterministically — a report that changes between
    /// identical runs cannot be diffed.
    func testArgumentFailureReportingIsStable() throws {
        let evalCase = try XCTUnwrap(
            EvalSuite.all.first { $0.id == "date-calendar-30-minute-call" }
        )
        let raw = completion(
            "create_calendar_event",
            #"{"title": "Zzz", "start": "1999-01-01T00:00:00Z", "duration_minutes": 90}"#
        )
        let outcomes = (0..<10).map {
            _ in EvalJudge.judge(evalCase, completion: raw, tools: EvalToolCatalog.specs).outcome
        }
        XCTAssertEqual(Set(outcomes.map(\.label)).count, 1)
    }
}
