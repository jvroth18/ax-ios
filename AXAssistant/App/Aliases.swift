import AXCore

// MLXLMCommon also exports types named ToolCall and ToolSpec. Everywhere in this app,
// the unqualified names mean AXCore's — these module-level aliases shadow the imports.
typealias ToolCall = AXCore.ToolCall
typealias ToolSpec = AXCore.ToolSpec
