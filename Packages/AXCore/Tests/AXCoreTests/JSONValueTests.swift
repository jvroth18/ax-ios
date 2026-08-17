import XCTest
@testable import AXCore

final class JSONValueTests: XCTestCase {

    func testRoundTrip() throws {
        let value: JSONValue = .object([
            "title": .string("Call mom"),
            "minutes": .number(10),
            "urgent": .bool(true),
            "tags": .array([.string("family")]),
            "note": .null,
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testAccessors() {
        XCTAssertEqual(JSONValue.number(10).intValue, 10)
        XCTAssertNil(JSONValue.number(10.5).intValue)
        XCTAssertEqual(JSONValue.number(10.5).numberValue, 10.5)
        XCTAssertEqual(JSONValue.string("hi").stringValue, "hi")
        XCTAssertNil(JSONValue.string("hi").numberValue)
        XCTAssertEqual(JSONValue.bool(false).boolValue, false)
    }

    func testSchemaRoundTrip() throws {
        let schema = JSONSchema(
            type: .object,
            properties: [
                "names": JSONSchema(type: .array, itemType: .string),
                "mode": JSONSchema(type: .string, enumValues: ["a", "b"]),
            ],
            required: ["names"]
        )
        let data = try JSONEncoder().encode(schema)
        let decoded = try JSONDecoder().decode(JSONSchema.self, from: data)
        XCTAssertEqual(decoded, schema)
        // "enum" and "items" must use JSON Schema key names on the wire
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"enum\""))
        XCTAssertTrue(json.contains("\"items\""))
    }
}
