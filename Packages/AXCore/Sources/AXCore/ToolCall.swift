import Foundation

/// One tool invocation emitted by the model.
public struct ToolCall: Codable, Equatable, Sendable {
    public let name: String
    public let arguments: [String: JSONValue]

    public init(name: String, arguments: [String: JSONValue]) {
        self.name = name
        self.arguments = arguments
    }

    public func string(_ key: String) -> String? { arguments[key]?.stringValue }
    public func number(_ key: String) -> Double? { arguments[key]?.numberValue }
    public func int(_ key: String) -> Int? { arguments[key]?.intValue }
    public func bool(_ key: String) -> Bool? { arguments[key]?.boolValue }
}

/// The result a tool hands back to the agent loop, serialized into a `<tool_response>` turn.
public struct ToolResult: Codable, Equatable, Sendable {
    public let success: Bool
    public let content: String

    public init(success: Bool, content: String) {
        self.success = success
        self.content = content
    }

    public static func ok(_ content: String) -> ToolResult { ToolResult(success: true, content: content) }
    public static func failure(_ content: String) -> ToolResult { ToolResult(success: false, content: content) }
}
