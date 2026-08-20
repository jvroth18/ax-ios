import XCTest
@testable import AXCore

final class DateArgumentTests: XCTestCase {

    /// Fixed zone for the "no designator means local" cases, so the expectations don't
    /// depend on where the test machine is.
    private let newYork = TimeZone(identifier: "America/New_York")!

    private func components(_ date: Date, in zone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }

    private func assertLocalWallClock(
        _ raw: String,
        _ expected: DateComponents,
        hasTime: Bool = true,
        line: UInt = #line
    ) {
        guard let parsed = DateArgument.parse(raw) else {
            return XCTFail("\(raw) did not parse", line: line)
        }
        XCTAssertEqual(components(parsed.date, in: .current), expected, "\(raw)", line: line)
        XCTAssertEqual(parsed.hasTime, hasTime, "\(raw)", line: line)
    }

    // MARK: - The shapes models actually emit

    /// The canonical example in docs/TOOL-CALLING.md. This is the one that used to throw
    /// badArgument("due", "not ISO 8601") in create_reminder.
    func testZonelessDateTimeIsLocalWallClock() {
        assertLocalWallClock(
            "2026-08-17T17:00:00",
            DateComponents(year: 2026, month: 8, day: 17, hour: 17, minute: 0, second: 0)
        )
    }

    func testZonelessWithoutSeconds() {
        assertLocalWallClock(
            "2026-08-17T17:00",
            DateComponents(year: 2026, month: 8, day: 17, hour: 17, minute: 0, second: 0)
        )
    }

    func testSpaceSeparatorAndLowercaseT() {
        let expected = DateComponents(year: 2026, month: 8, day: 17, hour: 17, minute: 30, second: 0)
        assertLocalWallClock("2026-08-17 17:30", expected)
        assertLocalWallClock("2026-08-17t17:30:00", expected)
    }

    func testUnpaddedMonthDayAndHour() {
        assertLocalWallClock(
            "2026-8-7T9:05",
            DateComponents(year: 2026, month: 8, day: 7, hour: 9, minute: 5, second: 0)
        )
    }

    func testDateOnlyIsMidnightAndFlaggedUntimed() {
        assertLocalWallClock(
            "2026-08-17",
            DateComponents(year: 2026, month: 8, day: 17, hour: 0, minute: 0, second: 0),
            hasTime: false
        )
    }

    func testSurroundingWhitespaceIsTolerated() {
        assertLocalWallClock(
            "  2026-08-17T17:00:00\n",
            DateComponents(year: 2026, month: 8, day: 17, hour: 17, minute: 0, second: 0)
        )
    }

    // MARK: - Explicit zones win over local

    func testTrailingZIsUTC() throws {
        let parsed = try XCTUnwrap(DateArgument.parse("2026-08-17T17:00:00Z"))
        XCTAssertEqual(
            components(parsed.date, in: TimeZone(secondsFromGMT: 0)!),
            DateComponents(year: 2026, month: 8, day: 17, hour: 17, minute: 0, second: 0)
        )
    }

    func testNumericOffsetsInBothPunctuations() throws {
        let colon = try XCTUnwrap(DateArgument.parse("2026-08-17T17:00:00-04:00"))
        let bare = try XCTUnwrap(DateArgument.parse("2026-08-17T17:00:00-0400"))
        XCTAssertEqual(colon.date, bare.date)
        XCTAssertEqual(
            components(colon.date, in: TimeZone(secondsFromGMT: -4 * 3600)!),
            DateComponents(year: 2026, month: 8, day: 17, hour: 17, minute: 0, second: 0)
        )
    }

    func testHalfHourOffset() throws {
        let parsed = try XCTUnwrap(DateArgument.parse("2026-08-17T17:00:00+05:30"))
        XCTAssertEqual(
            parsed.date,
            try XCTUnwrap(DateArgument.parse("2026-08-17T11:30:00Z")).date
        )
    }

    func testFractionalSecondsAreAccepted() throws {
        let parsed = try XCTUnwrap(DateArgument.parse("2026-08-17T17:00:00.500Z"))
        XCTAssertEqual(
            parsed.date.timeIntervalSince1970,
            try XCTUnwrap(DateArgument.parse("2026-08-17T17:00:00Z")).date.timeIntervalSince1970,
            accuracy: 1
        )
    }

    // MARK: - Local time is resolved by the calendar, not by an offset

    /// The old helper appended "Z" and subtracted the offset *of the UTC instant*, which
    /// reads the wrong side of a DST boundary. 17:00 must be 17:00 in both seasons, and
    /// the two must be a different number of hours from their UTC namesakes.
    func testWallClockSurvivesDaylightSavingOnBothSides() throws {
        for raw in ["2026-07-01T17:00:00", "2026-12-01T17:00:00"] {
            let parsed = try XCTUnwrap(DateArgument.parse(raw))
            XCTAssertEqual(components(parsed.date, in: .current).hour, 17, raw)
        }
        guard TimeZone.current == newYork else {
            // The offsets below are New York's; the wall-clock assertions above are the
            // portable half of this test.
            return
        }
        let summer = try XCTUnwrap(DateArgument.parse("2026-07-01T17:00:00")).date
        let winter = try XCTUnwrap(DateArgument.parse("2026-12-01T17:00:00")).date
        let summerUTC = try XCTUnwrap(DateArgument.parse("2026-07-01T17:00:00Z")).date
        let winterUTC = try XCTUnwrap(DateArgument.parse("2026-12-01T17:00:00Z")).date
        XCTAssertEqual(summer.timeIntervalSince(summerUTC), 4 * 3600, accuracy: 0.5)  // EDT
        XCTAssertEqual(winter.timeIntervalSince(winterUTC), 5 * 3600, accuracy: 0.5)  // EST
    }

    // MARK: - Rejections

    func testGarbageIsRejected() {
        for raw in [
            "",
            "tomorrow at 5",
            "5pm",
            "08/17/2026",
            "2026-08-17T17:00:00 and also call mom",
            "2026-13-01T09:00:00",   // month 13
            "2026-02-31T09:00:00",   // no such day
            "2026-08-17T25:00:00",   // hour 25 must not roll into the 18th
            "2026-08-17T17:60:00",
        ] {
            XCTAssertNil(DateArgument.parse(raw), "\(raw) should not parse")
        }
    }

    // MARK: - String convenience

    func testStringAccessorMatchesParse() {
        XCTAssertEqual("2026-08-17T17:00:00".iso8601Date, DateArgument.parse("2026-08-17T17:00:00")?.date)
        XCTAssertNil("not a date".iso8601Date)
    }
}
