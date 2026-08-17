import Foundation

public enum ChatRole: String, Codable, Sendable {
    case system, user, assistant, tool
}

public struct ChatMessage: Codable, Equatable, Sendable {
    public let role: ChatRole
    public let content: String

    public init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }
}

/// Tunables for the agent loop, shared between the app and tests.
public struct AgentConfig: Sendable {
    /// Maximum generate→execute-tool→feed-back cycles before the loop gives up and
    /// asks the model for a plain-text answer.
    public var maxToolIterations: Int
    public var maxContextTokens: Int

    public init(maxToolIterations: Int = 3, maxContextTokens: Int = 4096) {
        self.maxToolIterations = maxToolIterations
        self.maxContextTokens = maxContextTokens
    }
}
