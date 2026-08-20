import XCTest
@testable import AXCore

final class EvalDateParserTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/New_York")!

    private func iso(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = zone
        return formatter.string(from: date)
    }

    func testZonelessFormsAreReadAsLocal() {
        // The spelling docs/TOOL-CALLING.md tells the model to emit.
        XCTAssertEqual(
            iso(EvalDateParser.parse("2026-08-19T17:00:00", timeZone: zone)),
            "2026-08-19T17:00:00-04:00"
        )
        XCTAssertEqual(
            iso(EvalDateParser.parse("2026-08-19T17:00", timeZone: zone)),
            "2026-08-19T17:00:00-04:00"
        )
        XCTAssertEqual(
            iso(EvalDateParser.parse("2026-08-19 17:00", timeZone: zone)),
            "2026-08-19T17:00:00-04:00"
        )
    }

    func testZonedFormsResolveToTheSameInstant() {
        let local = EvalDateParser.parse("2026-08-19T17:00:00-04:00", timeZone: zone)
        let utc = EvalDateParser.parse("2026-08-19T21:00:00Z", timeZone: zone)
        XCTAssertEqual(local, utc)
        // Zone-carrying but second-less, which ISO8601DateFormatter alone rejects.
        XCTAssertEqual(EvalDateParser.parse("2026-08-19T17:00-04:00", timeZone: zone), local)
    }

    func testFractionalSecondsAndDateOnly() {
        XCTAssertNotNil(EvalDateParser.parse("2026-08-19T17:00:00.500Z", timeZone: zone))
        XCTAssertEqual(
            iso(EvalDateParser.parse("2026-08-19", timeZone: zone)),
            "2026-08-19T00:00:00-04:00"
        )
    }

    func testGarbageIsRejected() {
        XCTAssertNil(EvalDateParser.parse("tomorrow at noon", timeZone: zone))
        XCTAssertNil(EvalDateParser.parse("", timeZone: zone))
        XCTAssertNil(EvalDateParser.parse("5pm", timeZone: zone))
    }

    /// `hasExplicitZone` is what decides whether the shipping RemindersTool would throw,
    /// so its edge cases are load-bearing.
    func testHasExplicitZone() {
        XCTAssertFalse(EvalDateParser.hasExplicitZone("2026-08-19T17:00:00"))
        XCTAssertFalse(EvalDateParser.hasExplicitZone("2026-08-19 17:00"))
        XCTAssertFalse(EvalDateParser.hasExplicitZone("2026-08-19"))
        XCTAssertTrue(EvalDateParser.hasExplicitZone("2026-08-19T17:00:00Z"))
        XCTAssertTrue(EvalDateParser.hasExplicitZone("2026-08-19T17:00:00+05:30"))
        XCTAssertTrue(EvalDateParser.hasExplicitZone("2026-08-19T17:00:00-04:00"))
    }
}
