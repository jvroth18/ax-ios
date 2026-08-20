import Foundation

/// Fixes mechanically-wrong tool arguments before a tool sees them.
///
/// A model that emits `{"minutes": "10"}` instead of `{"minutes": 10}`, or `"State": "ON"`
/// for an enum of `["on", "off"]`, has understood the request perfectly and typed it
/// slightly wrong. Failing that call costs a full generation to say "try again" and a
/// second one to retry — on a 1.7B at 45 tok/s that's the difference between a two-second
/// answer and an eight-second one, and small models often repeat the same mistake anyway.
///
/// Every repair here is **information-preserving**: a string that already reads as the
/// number, an enum value that differs only in case or padding, a quoted string the model
/// wrapped twice. Anything requiring a guess about intent — a missing argument, an
/// unparseable date, a value not in the enum — is deliberately left to fail, because
/// inventing those is how an assistant silently does the wrong thing.
public enum ToolArgumentRepair {

    public struct Repair: Sendable, Equatable {
        public let argument: String
        public let from: String
        public let to: String
    }

    public struct Outcome: Sendable, Equatable {
        public let call: ToolCall
        public let repairs: [Repair]
        public var didRepair: Bool { !repairs.isEmpty }
    }

    public static func repair(_ call: ToolCall, spec: ToolSpec) -> Outcome {
        guard let properties = spec.parameters.properties else {
            return Outcome(call: call, repairs: [])
        }
        var arguments = call.arguments
        var repairs: [Repair] = []

        // Models sometimes capitalize argument names ("State"). Match keys case-insensitively
        // against the schema before anything else, or every later repair misses.
        for (key, value) in call.arguments where properties[key] == nil {
            guard let canonical = properties.keys.first(where: { $0.lowercased() == key.lowercased() })
            else { continue }
            arguments.removeValue(forKey: key)
            arguments[canonical] = value
            repairs.append(Repair(argument: key, from: key, to: canonical))
        }

        for (key, schema) in properties {
            guard let value = arguments[key] else { continue }

            // "10" → 10 for a numeric argument. The commonest small-model slip.
            if schema.type == .number || schema.type == .integer,
               value.numberValue == nil,
               let text = value.stringValue,
               let number = Double(text.trimmingCharacters(in: .whitespaces)) {
                arguments[key] = .number(number)
                repairs.append(Repair(argument: key, from: "\"\(text)\"", to: "\(number)"))
                continue
            }

            // 10 → "10" for a string argument that a model typed as a bare number.
            if schema.type == .string, value.stringValue == nil, let number = value.numberValue {
                let text = number == number.rounded() ? String(Int(number)) : String(number)
                arguments[key] = .string(text)
                repairs.append(Repair(argument: key, from: "\(number)", to: "\"\(text)\""))
                continue
            }

            guard var text = value.stringValue else { continue }

            // Strip padding and a layer of quotes the model wrapped around its own value.
            let unwrapped = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if unwrapped != text {
                repairs.append(Repair(argument: key, from: "\"\(text)\"", to: "\"\(unwrapped)\""))
                text = unwrapped
                arguments[key] = .string(text)
            }

            // "ON" → "on" when the schema fixes the vocabulary. Only ever matches an
            // allowed value; a genuinely wrong one still fails.
            if let allowed = schema.enumValues, !allowed.contains(text),
               let match = allowed.first(where: { $0.lowercased() == text.lowercased() }) {
                arguments[key] = .string(match)
                repairs.append(Repair(argument: key, from: "\"\(text)\"", to: "\"\(match)\""))
            }
        }

        guard !repairs.isEmpty else { return Outcome(call: call, repairs: []) }
        return Outcome(call: ToolCall(name: call.name, arguments: arguments), repairs: repairs)
    }
}
