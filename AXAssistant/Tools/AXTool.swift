import Foundation
import AXCore

/// One capability the model may invoke. Implementations live in Tools/Actions/.
protocol AXTool: Sendable {
    var spec: ToolSpec { get }
    /// When true, the tool's result text becomes the final reply verbatim — the loop does
    /// NOT feed it back through the text model. Used by tools that must swap models in
    /// memory (single-resident rule) or already produce spoken-ready text.
    var endsTurn: Bool { get }
    /// True for tools that only read state. Read-only calls in the same turn may run
    /// concurrently and their results may be reused within a turn; everything else runs
    /// in the order the model asked for, because "flashlight on" and "flashlight off"
    /// executing simultaneously is not a speedup, it's a coin flip.
    var isReadOnly: Bool { get }
    func run(_ call: ToolCall) async throws -> ToolResult
}

extension AXTool {
    var endsTurn: Bool { false }
    var isReadOnly: Bool { false }
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
