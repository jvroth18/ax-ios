import XCTest
@testable import AXCore

/// The clock is the foundation of every date assertion, so it gets tested first and
/// hardest: if "now" moves, no date case means anything.
final class EvalClockTests: XCTestCase {

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = EvalClock.pinned.timeZone
        return formatter.string(from: date)
    }

    func testPinnedClockIsHostTimeZoneIndependent() {
        // The whole point: this string must be identical on a machine in Tokyo.
        XCTAssertEqual(
            EvalClock.pinned.promptDateTime,
            "Wednesday 2026-08-19 14:30, America/New_York"
        )
        XCTAssertEqual(iso(EvalClock.pinned.reference), "2026-08-19T14:30:00-04:00")
    }

    func testPromptDateTimeMatchesAgentLoopFormat() {
        // AgentLoop.formattedNow() is "EEEE yyyy-MM-dd HH:mm, <zone id>". If that shape
        // ever changes, the pinned prompt stops resembling the real one.
        let parts = EvalClock.pinned.promptDateTime.split(separator: ",")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].split(separator: " ").count, 3)
        XCTAssertNotNil(TimeZone(identifier: parts[1].trimmingCharacters(in: .whitespaces)))
    }

    func testWallClockDayOffsets() {
        let clock = EvalClock.pinned
        XCTAssertEqual(
            iso(DateExpectation.wallClock(dayOffset: 0, hour: 17, minute: 0).resolve(clock: clock)),
            "2026-08-19T17:00:00-04:00"
        )
        XCTAssertEqual(
            iso(DateExpectation.wallClock(dayOffset: 1, hour: 12, minute: 0).resolve(clock: clock)),
            "2026-08-20T12:00:00-04:00"
        )
        // Friday, as the suite's "Friday at 9am" case assumes.
        XCTAssertEqual(
            iso(DateExpectation.wallClock(dayOffset: 2, hour: 9, minute: 0).resolve(clock: clock)),
            "2026-08-21T09:00:00-04:00"
        )
        // Monday, for "next Monday".
        XCTAssertEqual(
            iso(DateExpectation.wallClock(dayOffset: 5, hour: 15, minute: 0).resolve(clock: clock)),
            "2026-08-24T15:00:00-04:00"
        )
    }

    func testWallClockOffsetLandsOnTheExpectedWeekday() {
        let calendar = EvalClock.pinned.calendar
        let friday = DateExpectation.wallClock(dayOffset: 2, hour: 9, minute: 0)
            .resolve(clock: .pinned)
        XCTAssertEqual(calendar.component(.weekday, from: friday), 6)  // 1 = Sunday
    }

    func testRelativeExpectation() {
        let due = DateExpectation.relative(seconds: 20 * 60).resolve(clock: .pinned)
        XCTAssertEqual(iso(due), "2026-08-19T14:50:00-04:00")
    }
}
