import XCTest
@testable import AXCore

/// The router's failure mode is silent loss of capability, so most of these cases assert
/// that it *keeps* things — including the case where it should give up entirely.
final class ToolRouterTests: XCTestCase {

    private let tools = EvalToolCatalog.specs

    private func selection(_ request: String) -> [String] {
        ToolRouter.select(from: tools, for: request).tools.map(\.name).sorted()
    }

    func testKeepsTheObviousToolAndNarrows() {
        let result = ToolRouter.select(from: tools, for: "Turn on the flashlight")
        XCTAssertTrue(result.narrowed)
        XCTAssertTrue(result.tools.contains { $0.name == "toggle_flashlight" })
        XCTAssertLessThan(result.tools.count, tools.count)
    }

    func testKeepsTimerForADurationRequest() {
        XCTAssertTrue(selection("Set a timer for 10 minutes").contains("set_timer"))
    }

    func testKeepsMorseToolForMorseRequest() {
        let result = ToolRouter.select(from: tools, for: "Signal SOS in Morse code")
        XCTAssertTrue(result.narrowed)
        XCTAssertTrue(result.tools.contains { $0.name == "signal_morse_code" })
    }

    func testKeepsCalendarToolForACalendarRequest() {
        XCTAssertTrue(selection("Put lunch with Sarah on my calendar tomorrow").contains("create_calendar_event"))
    }

    func testKeepsContactLookupForACallRequest() {
        let selected = selection("Call Dave")
        XCTAssertTrue(selected.contains("call_number") || selected.contains("find_contact"))
    }

    func testWorkflowToolsAreAlwaysKept() {
        // "Blink the light ten times" never says "repeat_steps", but needs it.
        let selected = selection("Blink the light ten times")
        XCTAssertTrue(selected.contains("repeat_steps"))
        XCTAssertTrue(selected.contains("wait"))
    }

    func testReturnsEverythingWhenNothingMatches() {
        // A request the router has no evidence about is exactly when narrowing is most
        // dangerous, so it must decline to narrow.
        let result = ToolRouter.select(from: tools, for: "What do you think about all this?")
        XCTAssertFalse(result.narrowed)
        XCTAssertEqual(result.tools.count, tools.count)
    }

    func testReturnsEverythingForAnEmptyRequest() {
        XCTAssertFalse(ToolRouter.select(from: tools, for: "   ").narrowed)
    }

    func testSmallCatalogIsNeverNarrowed() {
        let few = Array(tools.prefix(3))
        let result = ToolRouter.select(from: few, for: "Turn on the flashlight")
        XCTAssertFalse(result.narrowed)
        XCTAssertEqual(result.tools.count, 3)
    }

    func testNameMatchesOutrankDescriptionMatches() {
        let words = ToolRouter.tokenize("flashlight")
        let flashlight = tools.first { $0.name == "toggle_flashlight" }!
        let others = tools.filter { $0.name != "toggle_flashlight" }
        for other in others {
            XCTAssertGreaterThan(
                ToolRouter.score(spec: flashlight, against: words),
                ToolRouter.score(spec: other, against: words),
                "\(other.name) should not outrank the tool the request names"
            )
        }
    }
}
