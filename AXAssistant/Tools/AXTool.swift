import Foundation
import AXCore

/// One capability the model may invoke. Implementations live in Tools/Actions/.
protocol AXTool: Sendable {
    var spec: ToolSpec { get }
    func run(_ call: ToolCall) async throws -> ToolResult
}

enum AXToolError: LocalizedError {
    case missingArgument(String)
    case badArgument(String, String)
    case permissionDenied(String)
    case notAvailable(String)

    var errorDescription: String? {
        switch self {
        case .missingArgument(let name): return "Missing argument \(name)"
        case .badArgument(let name, let why): return "Bad argument \(name): \(why)"
        case .permissionDenied(let what): return "Permission denied: \(what)"
        case .notAvailable(let why): return why
        }
    }
}
