import XCTest
@testable import AXCore

final class ArgumentMatcherTests: XCTestCase {
    private let clock = EvalClock.pinned

    private func reason(_ matcher: ArgumentMatcher, _ value: JSONValue?) -> String? {
        matcher.mismatchReason(for: value, clock: clock)
    }

    // MARK: - The date matcher (the reason this file exists)

    func testResolvedDateAcceptsEveryCorrectSpelling() {
        let matcher = ArgumentMatcher.resolvedDate(.wallClock(dayOffset: 0, hour: 17, minute: 0))
        for spelling in [
            "2026-08-19T17:00:00",        // zone-less, as the docs instruct
            "2026-08-19T17:00:00-04:00",  // fully qualified
            "2026-08-19T21:00:00Z",       // same instant in UTC
            "2026-08-19 17:00",           // space separator, no seconds
        ] {
            XCTAssertNil(reason(matcher, .string(spelling)), "should accept \(spelling)")
        }
    }

    /// The regression the old harness could not see. `expectedArgs: ["due": nil]` asserted
    /// key existence only, so this value scored a pass.
    func testResolvedDateRejectsTheValueTheOldHarnessPassed() {
        let matcher = ArgumentMatcher.resolvedDate(.wallClock(dayOffset: 0, hour: 17, minute: 0))
        let bogus = JSONValue.string("1999-01-01T00:00:00")
        XCTAssertNil(reason(.present, bogus), "old semantics: key exists, therefore pass")
        let why = reason(matcher, bogus)
        XCTAssertNotNil(why)
        XCTAssertTrue(why!.contains("days early"), why ?? "")
    }

    func testResolvedDateRejectsWrongTimeOnTheRightDay() {
        let matcher = ArgumentMatcher.resolvedDate(.wallClock(dayOffset: 1, hour: 12, minute: 0))
        // Midnight instead of noon — the classic "tomorrow at noon" failure.
        XCTAssertNotNil(reason(matcher, .string("2026-08-20T00:00:00")))
        // 12-hour confusion.
        XCTAssertNotNil(reason(matcher, .string("2026-08-20T00:00:00-04:00")))
        XCTAssertNil(reason(matcher, .string("2026-08-20T12:00:00")))
    }

    func testResolvedDateRejectsRightTimeOnWrongDay() {
        let matcher = ArgumentMatcher.resolvedDate(.wallClock(dayOffset: 1, hour: 12, minute: 0))
        let why = reason(matcher, .string("2026-08-19T12:00:00"))
        XCTAssertNotNil(why)
        XCTAssertTrue(why!.contains("early"), why ?? "")
    }

    func testResolvedDateRespectsTolerance() {
        let matcher = ArgumentMatcher.resolvedDate(
            .relative(seconds: 20 * 60), toleranceSeconds: 120
        )
        XCTAssertNil(reason(matcher, .string("2026-08-19T14:50:00")))
        XCTAssertNil(reason(matcher, .string("2026-08-19T14:51:30")))  // 90s late, inside
        XCTAssertNotNil(reason(matcher, .string("2026-08-19T14:55:00")))  // 5min late, outside
    }

    func testResolvedDateAnyOfAcceptsEitherReading() {
        let matcher = ArgumentMatcher.resolvedDateAnyOf(
            [
                .wallClock(dayOffset: 5, hour: 15, minute: 0),
                .wallClock(dayOffset: 12, hour: 15, minute: 0),
            ],
            toleranceSeconds: 60
        )
        XCTAssertNil(reason(matcher, .string("2026-08-24T15:00:00")))
        XCTAssertNil(reason(matcher, .string("2026-08-31T15:00:00")))
        // 3am on a valid day is still wrong.
        XCTAssertNotNil(reason(matcher, .string("2026-08-24T03:00:00")))
    }

    func testUnparseableDateIsReportedAsSuch() {
        let matcher = ArgumentMatcher.resolvedDate(.wallClock(dayOffset: 0, hour: 17, minute: 0))
        let why = reason(matcher, .string("today at 5pm"))
        XCTAssertEqual(why, "\"today at 5pm\" is not a readable date-time")
    }

    // MARK: - Presence

    func testPresentAndAbsent() {
        XCTAssertNil(reason(.present, .string("anything")))
        XCTAssertEqual(reason(.present, nil), "missing")
        XCTAssertEqual(reason(.present, .null), "missing")
        XCTAssertNil(reason(.absent, nil))
        XCTAssertNil(reason(.absent, .null))
        XCTAssertNotNil(reason(.absent, .string("2026-08-19T17:00:00")))
    }

    // MARK: - Strings, enums, numbers, phone numbers

    func testStringMatchers() {
        XCTAssertNil(reason(.exact("Goodnight"), .string("Goodnight")))
        XCTAssertNotNil(reason(.exact("Goodnight"), .string("goodnight")))
        XCTAssertNil(reason(.caseInsensitive("maps"), .string("Maps")))
        XCTAssertNil(reason(.contains("mom"), .string("Call Mom back")))
        XCTAssertNotNil(reason(.contains("mom"), .string("Call Dad")))
    }

    func testOneOf() {
        XCTAssertNil(reason(.oneOf(["play", "pause"]), .string("Pause")))
        XCTAssertNotNil(reason(.oneOf(["play", "pause"]), .string("stop")))
    }

    func testNumberCoercion() {
        XCTAssertNil(reason(.number(10), .number(10)))
        XCTAssertNil(reason(.number(10), .number(10.0)))
        XCTAssertNil(reason(.number(10), .string("10")), "models emit numbers as strings")
        XCTAssertNotNil(reason(.number(10), .number(600)), "seconds instead of minutes")
        XCTAssertNil(reason(.number(1.5, tolerance: 0.01), .number(1.5)))
        XCTAssertNotNil(reason(.number(1.5, tolerance: 0.01), .number(2)))
    }

    func testDigitsMatcherNormalizesPhoneNumbers() {
        let matcher = ArgumentMatcher.digits("+1 (415) 555-0147")
        XCTAssertNil(reason(matcher, .string("+14155550147")))
        XCTAssertNil(reason(matcher, .string("415-555-0147")))
        XCTAssertNil(reason(matcher, .string("(415) 555 0147")))
        XCTAssertNotNil(reason(matcher, .string("+14155550148")))
        XCTAssertNotNil(reason(matcher, .string("Dave's number")))
    }

    func testDisplayTrimsWholeNumbers() {
        XCTAssertEqual(ArgumentMatcher.display(.number(10.0)), "10")
        XCTAssertEqual(ArgumentMatcher.display(.number(1.5)), "1.5")
        XCTAssertEqual(ArgumentMatcher.display(.bool(true)), "true")
    }
}
