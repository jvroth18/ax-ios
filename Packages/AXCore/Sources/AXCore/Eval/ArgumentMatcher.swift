import Foundation

/// How one tool argument is checked.
///
/// WHY this replaces `[String: String?]`: in the old harness a `nil` expected value meant
/// "assert the key exists", so every date-bearing case — the hardest thing a 1.7B is asked
/// to do — was scored purely on whether *some* `due` key was present. A model emitting
/// `1999-01-01` passed. Matchers make the assertion explicit and force each case to say
/// what "correct" means, including for dates.
public enum ArgumentMatcher: Sendable, Equatable, Codable {
    /// Key exists and is non-null. The old default — now something a case has to *choose*.
    case present
    /// Key must NOT appear. Catches invented arguments (a `due` on "remind me to buy milk").
    case absent
    case exact(String)
    case caseInsensitive(String)
    /// Case-insensitive substring. For free text the model legitimately rephrases
    /// ("Call mom" vs "call mom back").
    case contains(String)
    case oneOf([String])
    /// Numeric, coerced across JSON number/string ("10" and 10 both pass).
    case number(Double, tolerance: Double)
    /// Phone numbers compared on digits only, last 10 digits when both are long enough,
    /// so "+1 (415) 555-0147" and "4155550147" agree.
    case digits(String)
    /// The resolved-instant matcher. Any of the listed expectations within `tolerance`
    /// passes — a list because some phrasings ("next Monday") are genuinely bi-modal for
    /// humans too, and the eval should not punish the reading a person would also accept.
    case resolvedDateAnyOf([DateExpectation], toleranceSeconds: TimeInterval)

    public static func resolvedDate(
        _ expectation: DateExpectation, toleranceSeconds: TimeInterval = 60
    ) -> ArgumentMatcher {
        .resolvedDateAnyOf([expectation], toleranceSeconds: toleranceSeconds)
    }

    public static func number(_ value: Double) -> ArgumentMatcher { .number(value, tolerance: 0) }

    /// Returns nil when the argument satisfies the matcher, else a human-readable reason.
    public func mismatchReason(for value: JSONValue?, clock: EvalClock) -> String? {
        if case .absent = self {
            guard let value, value != .null else { return nil }
            return "should not be set, got \(Self.display(value))"
        }
        guard let value, value != .null else { return "missing" }

        switch self {
        case .absent:
            return nil  // handled above
        case .present:
            return nil
        case .exact(let expected):
            let actual = Self.display(value)
            return actual == expected ? nil : "expected \"\(expected)\", got \"\(actual)\""
        case .caseInsensitive(let expected):
            let actual = Self.display(value)
            return actual.lowercased() == expected.lowercased()
                ? nil : "expected \"\(expected)\" (any case), got \"\(actual)\""
        case .contains(let needle):
            let actual = Self.display(value)
            return actual.lowercased().contains(needle.lowercased())
                ? nil : "expected to contain \"\(needle)\", got \"\(actual)\""
        case .oneOf(let allowed):
            let actual = Self.display(value).lowercased()
            return allowed.contains(where: { $0.lowercased() == actual })
                ? nil : "expected one of [\(allowed.joined(separator: ", "))], got \"\(actual)\""
        case .number(let expected, let tolerance):
            guard let actual = Self.coerceNumber(value) else {
                return "expected number \(Self.trim(expected)), got \"\(Self.display(value))\""
            }
            return abs(actual - expected) <= tolerance
                ? nil : "expected \(Self.trim(expected)), got \(Self.trim(actual))"
        case .digits(let expected):
            let actual = Self.digitsOnly(Self.display(value))
            let wanted = Self.digitsOnly(expected)
            guard !actual.isEmpty else { return "expected digits \(expected), got \"\(Self.display(value))\"" }
            let matches = actual == wanted
                || (actual.count >= 10 && wanted.count >= 10 && actual.suffix(10) == wanted.suffix(10))
            return matches ? nil : "expected number \(expected), got \(Self.display(value))"
        case .resolvedDateAnyOf(let expectations, let tolerance):
            let raw = Self.display(value)
            guard let emitted = EvalDateParser.parse(raw, timeZone: clock.timeZone) else {
                return "\"\(raw)\" is not a readable date-time"
            }
            let deltas = expectations.map { emitted.timeIntervalSince($0.resolve(clock: clock)) }
            if deltas.contains(where: { abs($0) <= tolerance }) { return nil }
            let best = deltas.min(by: { abs($0) < abs($1) }) ?? 0
            let wanted = expectations.map { $0.describe(clock: clock) }.joined(separator: " or ")
            return "resolved to \(raw) — off by \(Self.humanDelta(best)) from \(wanted)"
        }
    }

    // MARK: - Coercion helpers

    /// Renders a JSON value the way a human reading a failure wants to see it. Numbers lose
    /// a trailing ".0" because models emit `10` and `10.0` interchangeably for `minutes`.
    public static func display(_ value: JSONValue) -> String {
        switch value {
        case .string(let string): return string
        case .number(let number): return trim(number)
        case .bool(let flag): return flag ? "true" : "false"
        case .null: return "null"
        case .array(let items): return "[" + items.map(display).joined(separator: ", ") + "]"
        case .object(let object):
            return "{" + object.keys.sorted().map { "\($0)=\(display(object[$0]!))" }.joined(separator: ", ") + "}"
        }
    }

    static func coerceNumber(_ value: JSONValue) -> Double? {
        if let number = value.numberValue { return number }
        if let string = value.stringValue { return Double(string.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func digitsOnly(_ string: String) -> String { string.filter(\.isNumber) }

    static func trim(_ number: Double) -> String {
        number == number.rounded() && abs(number) < 1e15
            ? String(Int(number)) : String(number)
    }

    static func humanDelta(_ seconds: TimeInterval) -> String {
        let magnitude = abs(seconds)
        let direction = seconds < 0 ? "early" : "late"
        if magnitude < 90 { return "\(Int(magnitude.rounded()))s \(direction)" }
        if magnitude < 5400 { return "\(Int((magnitude / 60).rounded()))min \(direction)" }
        if magnitude < 172_800 { return String(format: "%.1fh %@", magnitude / 3600, direction) }
        return String(format: "%.1f days %@", magnitude / 86_400, direction)
    }
}
