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

    func testMessageToolRequiresExplicitCommunicationIntent() {
        XCTAssertFalse(RequestPolicy.allows(tool: "compose_message", for: "Hi"))
        XCTAssertFalse(RequestPolicy.allows(tool: "compose_message", for: "What is the weather?"))
        XCTAssertTrue(RequestPolicy.allows(tool: "compose_message", for: "Text Sam that I am late"))
        XCTAssertTrue(RequestPolicy.allows(tool: "compose_message", for: "Send a message to Mom"))
    }

    func testCallToolRequiresExplicitCallIntent() {
        XCTAssertFalse(RequestPolicy.allows(tool: "call_number", for: "Hi"))
        XCTAssertTrue(RequestPolicy.allows(tool: "call_number", for: "Give Mom a ring"))
    }
}
