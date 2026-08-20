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
        XCTAssertFalse(RequestPolicy.allows(tool: "compose_message", for: "Tell me a joke"))
        XCTAssertFalse(RequestPolicy.allows(tool: "compose_message", for: "Write me a poem"))
        XCTAssertFalse(RequestPolicy.allows(tool: "compose_message", for: "Explain this error message"))
        XCTAssertTrue(RequestPolicy.allows(tool: "compose_message", for: "Text Sam that I am late"))
        XCTAssertTrue(RequestPolicy.allows(tool: "compose_message", for: "Send a message to Mom"))
        XCTAssertTrue(RequestPolicy.allows(tool: "compose_message", for: "Could you message Mom?"))
    }

    func testCallToolRequiresExplicitCallIntent() {
        XCTAssertFalse(RequestPolicy.allows(tool: "call_number", for: "Hi"))
        XCTAssertFalse(RequestPolicy.allows(tool: "call_number", for: "How does a phone work?"))
        XCTAssertTrue(RequestPolicy.allows(tool: "call_number", for: "Give Mom a ring"))
    }
}
