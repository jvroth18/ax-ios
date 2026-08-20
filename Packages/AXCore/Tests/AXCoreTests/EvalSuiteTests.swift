import XCTest
@testable import AXCore

/// Invariants on the suite itself. A case that references a tool that doesn't exist, or a
/// duplicated id, silently corrupts every report built from it.
final class EvalSuiteTests: XCTestCase {

    func testCaseIDsAreUniqueAndStable() {
        let ids = EvalSuite.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate case id")
        XCTAssertFalse(ids.contains(where: \.isEmpty))
    }

    func testEveryClassIsPopulated() {
        for caseClass in EvalCaseClass.allCases {
            XCTAssertFalse(
                EvalSuite.cases(in: caseClass).isEmpty,
                "\(caseClass.rawValue) has no cases — a class with none reports 0/0, which reads as fine"
            )
        }
    }

    func testEveryExpectedToolAndArgumentExists() {
        let specs = Dictionary(uniqueKeysWithValues: EvalToolCatalog.specs.map { ($0.name, $0) })
        for evalCase in EvalSuite.all {
            for call in evalCase.expected {
                guard let spec = specs[call.tool] else {
                    return XCTFail("\(evalCase.id) expects unknown tool \(call.tool)")
                }
                for argument in call.arguments.keys {
                    XCTAssertNotNil(
                        spec.parameters.properties?[argument],
                        "\(evalCase.id) matches \(call.tool).\(argument), which is not in the schema"
                    )
                }
            }
        }
    }

    func testNegativeAndAmbiguityCasesExpectNoCalls() {
        for evalCase in EvalSuite.all where [.negative, .ambiguity].contains(evalCase.caseClass) {
            XCTAssertTrue(evalCase.expected.isEmpty, "\(evalCase.id) should expect no tool call")
        }
        for evalCase in EvalSuite.cases(in: .ambiguity) {
            XCTAssertTrue(evalCase.requiresQuestion, "\(evalCase.id) should demand a question")
        }
    }

    func testDateCasesActuallyAssertADate() {
        for evalCase in EvalSuite.cases(in: .dateExtraction) {
            let matchers = evalCase.expected.flatMap { $0.arguments.values }
            let assertsTime = matchers.contains { matcher in
                if case .resolvedDateAnyOf = matcher { return true }
                if case .absent = matcher { return true }
                return false
            }
            XCTAssertTrue(
                assertsTime,
                "\(evalCase.id) is a dateExtraction case that never checks a date — "
                    + "exactly the hole this suite replaced"
            )
        }
    }

    func testMultiStepCasesAreOrderedAndChained() {
        for evalCase in EvalSuite.cases(in: .multiStep) {
            XCTAssertTrue(evalCase.orderMatters, "\(evalCase.id)")
            XCTAssertGreaterThan(evalCase.expected.count, 1, "\(evalCase.id) isn't multi-step")
        }
    }

    /// Every case must be scorable end to end. The switch below is exhaustive on purpose:
    /// adding a matcher without teaching this test to synthesize it is a build error, not
    /// a silently unexercised branch.
    ///
    /// Every case must be scorable end to end: build the call the case describes, and
    /// confirm the suite considers it a pass. Catches matchers that can never be satisfied
    /// (a `contains` on a value the tool can't produce, a date outside its own tolerance).
    func testSuiteIsSelfConsistentForDateAndEnumMatchers() {
        for evalCase in EvalSuite.all where !evalCase.expected.isEmpty {
            var calls: [ToolCall] = []
            for expectation in evalCase.expected {
                var arguments: [String: JSONValue] = [:]
                for (key, matcher) in expectation.arguments {
                    switch matcher {
                    case .absent:
                        continue
                    case .present:
                        arguments[key] = .string("x")
                    case .exact(let value), .caseInsensitive(let value), .contains(let value):
                        arguments[key] = .string(value)
                    case .oneOf(let values):
                        arguments[key] = .string(values[0])
                    case .number(let value, _):
                        arguments[key] = .number(value)
                    case .digits(let value):
                        arguments[key] = .string(value)
                    case .resolvedDateAnyOf(let expectations, _):
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime]
                        formatter.timeZone = EvalClock.pinned.timeZone
                        arguments[key] = .string(
                            formatter.string(from: expectations[0].resolve(clock: .pinned))
                        )
                    }
                }
                calls.append(ToolCall(name: expectation.tool, arguments: arguments))
            }
            let judged = EvalJudge.judge(evalCase, calls: calls, replyText: "")
            XCTAssertEqual(judged.outcome, .pass, "\(evalCase.id) cannot be satisfied")
        }
    }
}
