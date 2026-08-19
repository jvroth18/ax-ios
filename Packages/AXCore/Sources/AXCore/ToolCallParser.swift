import Foundation

public enum ToolCallParseError: Error, Equatable, CustomStringConvertible {
    case malformedJSON(block: String)
    case missingName(block: String)
    case unknownTool(name: String)
    case missingRequiredArgument(tool: String, argument: String)
    case typeMismatch(tool: String, argument: String, expected: String)

    public var description: String {
        switch self {
        case .malformedJSON(let block):
            return "Tool call block is not valid JSON: \(block.prefix(120))"
        case .missingName(let block):
            return "Tool call is missing a \"name\" field: \(block.prefix(120))"
        case .unknownTool(let name):
            return "Model called unknown tool \"\(name)\""
        case .missingRequiredArgument(let tool, let argument):
            return "Tool \"\(tool)\" call is missing required argument \"\(argument)\""
        case .typeMismatch(let tool, let argument, let expected):
            return "Tool \"\(tool)\" argument \"\(argument)\" should be \(expected)"
        }
    }
}

/// The parsed form of one model completion: any validated tool calls plus the
/// user-facing text with `<tool_call>` and `<think>` blocks stripped out.
public struct ParsedCompletion: Equatable, Sendable {
    public let toolCalls: [ToolCall]
    public let text: String
}

/// Extracts and validates Hermes-style `<tool_call>{"name":…,"arguments":…}</tool_call>`
/// blocks from Qwen output.
public enum ToolCallParser {

    public static func parse(_ completion: String, tools: [ToolSpec]) throws -> ParsedCompletion {
        var withoutThinking = strip(tag: "think", from: completion)
        // Some finetunes emit dangling think tags (a bare "</think>" after real
        // content, or an unpaired "<think>") that survive matched-pair stripping
        // and would corrupt an otherwise-valid completion.
        withoutThinking = withoutThinking
            .replacingOccurrences(of: "</think>", with: "")
            .replacingOccurrences(of: "<think>", with: "")
        var text = withoutThinking
        var calls: [ToolCall] = []

        for block in blocks(tag: "tool_call", in: withoutThinking) {
            text = text.replacingOccurrences(of: block.raw, with: "")
            let call = try parseBlock(block.inner, tools: tools)
            calls.append(call)
        }

        // Fallback: small models often emit the call JSON bare, without the
        // <tool_call> tags. If the whole completion is {"name":…,"arguments":…}
        // shaped (or several such objects on separate lines), honor it.
        if calls.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") {
                let candidates = bareCandidates(in: trimmed)
                if !candidates.isEmpty {
                    for candidate in candidates {
                        calls.append(try parseBlock(candidate, tools: tools))
                    }
                    text = ""
                }
            }
        }

        return ParsedCompletion(
            toolCalls: calls,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Bare-JSON candidates: the whole string if it decodes as a call-shaped object
    /// ("name" string present), else each line that does. Non-call JSON (no "name")
    /// is left alone so JSON-shaped prose answers still read as text.
    private static func bareCandidates(in trimmed: String) -> [String] {
        func isCallShaped(_ string: String) -> Bool {
            guard let data = string.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data)
            else { return false }
            return decoded["name"]?.stringValue != nil
        }
        if isCallShaped(trimmed) { return [trimmed] }
        let lines = trimmed
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count > 1, lines.allSatisfy({ $0.hasPrefix("{") && isCallShaped($0) }) {
            return lines
        }
        return []
    }

    // MARK: - Block extraction

    private struct TagBlock {
        let raw: String    // including the tags
        let inner: String  // content between the tags
    }

    private static func blocks(tag: String, in text: String) -> [TagBlock] {
        var result: [TagBlock] = []
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        var searchRange = text.startIndex..<text.endIndex

        while let openRange = text.range(of: open, range: searchRange),
              let closeRange = text.range(of: close, range: openRange.upperBound..<text.endIndex) {
            let raw = String(text[openRange.lowerBound..<closeRange.upperBound])
            let inner = String(text[openRange.upperBound..<closeRange.lowerBound])
            result.append(TagBlock(raw: raw, inner: inner))
            searchRange = closeRange.upperBound..<text.endIndex
        }
        return result
    }

    private static func strip(tag: String, from text: String) -> String {
        var result = text
        for block in blocks(tag: tag, in: text) {
            result = result.replacingOccurrences(of: block.raw, with: "")
        }
        return result
    }

    // MARK: - Parsing + validation

    private static func parseBlock(_ inner: String, tools: [ToolSpec]) throws -> ToolCall {
        let json = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
            throw ToolCallParseError.malformedJSON(block: json)
        }
        guard let name = decoded["name"]?.stringValue else {
            throw ToolCallParseError.missingName(block: json)
        }
        guard let spec = tools.first(where: { $0.name == name }) else {
            throw ToolCallParseError.unknownTool(name: name)
        }

        let arguments = decoded["arguments"]?.objectValue ?? [:]
        try validate(arguments: arguments, against: spec)
        return ToolCall(name: name, arguments: arguments)
    }

    private static func validate(arguments: [String: JSONValue], against spec: ToolSpec) throws {
        for requiredKey in spec.parameters.required ?? [] {
            guard let value = arguments[requiredKey], value != .null else {
                throw ToolCallParseError.missingRequiredArgument(tool: spec.name, argument: requiredKey)
            }
        }
        for (key, value) in arguments {
            guard let schema = spec.parameters.properties?[key] else { continue }
            try check(value: value, matches: schema.type, tool: spec.name, argument: key)
            if let allowed = schema.enumValues, let string = value.stringValue, !allowed.contains(string) {
                throw ToolCallParseError.typeMismatch(
                    tool: spec.name, argument: key, expected: "one of \(allowed.joined(separator: ", "))"
                )
            }
        }
    }

    private static func check(
        value: JSONValue, matches type: JSONSchema.SchemaType, tool: String, argument: String
    ) throws {
        let matches: Bool
        switch type {
        case .string: matches = value.stringValue != nil
        case .number: matches = value.numberValue != nil
        case .integer: matches = value.intValue != nil
        case .boolean: matches = value.boolValue != nil
        case .array: matches = value.arrayValue != nil
        case .object: matches = value.objectValue != nil
        }
        guard matches else {
            throw ToolCallParseError.typeMismatch(tool: tool, argument: argument, expected: type.rawValue)
        }
    }
}
