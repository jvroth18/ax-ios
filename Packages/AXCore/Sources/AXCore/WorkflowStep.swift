import Foundation

/// One step of a `repeat_steps` workflow: a tool name and its single value.
///
/// Lives in AXCore rather than beside the tool because it's pure parsing — the part most
/// likely to meet input a model invented — and everything pure in this package is covered
/// by `swift test` rather than discovered on a phone.
public struct WorkflowStep: Sendable, Equatable {
    public let tool: String
    public let value: String?

    public init(tool: String, value: String?) {
        self.tool = tool
        self.value = value
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case tooManyArguments(tool: String, count: Int)
        case missingValue(tool: String, argument: String)
        case notANumber(argument: String, value: String)

        public var description: String {
            switch self {
            case .tooManyArguments(let tool, let count):
                return "\(tool) needs \(count) arguments, so it can't be a workflow step"
            case .missingValue(let tool, let argument):
                return "\(tool) needs a value for \(argument)"
            case .notANumber(let argument, let value):
                return "\"\(value)\" is not a number for \(argument)"
            }
        }
    }

    /// Liberal reader for the flat step syntax. Accepts commas, semicolons or newlines
    /// between steps and `tool:value`, `tool=value` or `tool(value)` within one, and
    /// tolerates the model wrapping the list in brackets or quotes — all shapes observed
    /// from small models asked for the same thing.
    public static func parse(_ raw: String) -> [WorkflowStep] {
        let cleaned = raw
            .trimmingCharacters(in: CharacterSet(charactersIn: " []\"'"))
            .replacingOccurrences(of: "\n", with: ",")
        return cleaned
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .compactMap { piece -> WorkflowStep? in
                var text = piece.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                guard !text.isEmpty else { return nil }
                if let open = text.firstIndex(of: "("), text.hasSuffix(")") {
                    let name = String(text[text.startIndex..<open])
                    let inner = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
                    text = "\(name):\(inner)"
                }
                guard let range = text.rangeOfCharacter(from: CharacterSet(charactersIn: ":=")) else {
                    let tool = text.trimmingCharacters(in: CharacterSet(charactersIn: " ()\"'"))
                    return tool.isEmpty ? nil : WorkflowStep(tool: tool, value: nil)
                }
                let tool = String(text[text.startIndex..<range.lowerBound])
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"'()"))
                let value = String(text[range.upperBound...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"'()"))
                guard !tool.isEmpty else { return nil }
                return WorkflowStep(tool: tool, value: value.isEmpty ? nil : value)
            }
    }

    /// Maps this step's single value onto the tool's one required argument, typed by its
    /// schema. Derived from the spec rather than a hardcoded table, so a new tool with one
    /// required argument becomes usable in workflows for free — and one with two is
    /// rejected with a reason the model can act on.
    public func arguments(for spec: ToolSpec) throws -> [String: JSONValue] {
        let required = spec.parameters.required ?? []
        guard required.count <= 1 else {
            throw ParseError.tooManyArguments(tool: spec.name, count: required.count)
        }
        guard let key = required.first else { return [:] }
        guard let value else {
            throw ParseError.missingValue(tool: spec.name, argument: key)
        }
        switch spec.parameters.properties?[key]?.type ?? .string {
        case .number, .integer:
            guard let number = Double(value) else {
                throw ParseError.notANumber(argument: key, value: value)
            }
            return [key: .number(number)]
        case .boolean:
            return [key: .bool(["true", "yes", "on", "1"].contains(value.lowercased()))]
        default:
            return [key: .string(value)]
        }
    }
}
