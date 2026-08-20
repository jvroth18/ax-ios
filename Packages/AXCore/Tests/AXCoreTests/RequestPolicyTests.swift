import XCTest
@testable import AXCore

final class RequestPolicyTests: XCTestCase {
    func testStandaloneGreetingsGetAConversationReply() {
        for greeting in ["Hi", "hello!", " Hey there ", "Good morning."] {
            XCTAssertEqual(RequestPolicy.directReply(for: greeting), "Hi! What can I help you with?")
        }
    }

    func testGreetingWithAnActionStillReachesTheAgent() {
        XCTAssertNil(RequestPolicy.directReply(for: "Hi, text Sam that I am late"))
        XCTAssertNil(RequestPolicy.directReply(for: "Hey, blink the flashlight five times"))
    }
}
