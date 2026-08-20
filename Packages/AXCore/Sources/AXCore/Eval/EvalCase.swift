import Foundation

/// What a case is trying to falsify. Reported separately because the classes fail
/// independently: a model can be perfect at "turn on the flashlight" and still be
/// unusable because it fires `create_calendar_event` at small talk.
public enum EvalCaseClass: String, Sendable, Codable, CaseIterable {
    /// One obvious tool, no date reasoning. The old suite was entirely this.
    case singleTool
    /// A relative date/time the model must resolve against the injected "now".
    case dateExtraction
    /// The correct answer is *no tool call*. Measures spurious firing — the failure
    /// mode that corrupts a calendar rather than merely disappointing the user.
    case negative
    /// Chained calls through the real agent loop, with argument threading between steps.
    case multiStep
    /// Under-specified requests where the prompt tells the model to ask, not guess.
    case ambiguity
    /// The right call plus bait for a second one. Pass requires the *exact* call count.
    case spuriousExtra
    /// Repetition and pacing: the model must collapse a repeated action into one
    /// `repeat_steps` call rather than counting through 30 hand-backs — and must NOT
    /// reach for the workflow tool when a single action was asked for.
    case workflow

    public var title: String {
        switch self {
        case .singleTool: return "Single tool"
        case .dateExtraction: return "Date extraction"
        case .negative: return "Negative (no tool)"
        case .multiStep: return "Multi-step"
        case .ambiguity: return "Ambiguity"
        case .spuriousExtra: return "Spurious extra"
        case .workflow: return "Workflow (repetition)"
        }
    }
}

/// Whether the emitted arguments must survive the shipping tool's own parsing.
public enum ExecutionExpectation: String, Sendable, Codable {
    /// The real tool must accept these arguments. A tool that throws on well-formed model
    /// output fails the case even though the model did nothing wrong — which is exactly
    /// the `create_reminder` date bug.
    case accept
    /// The real tool is expected to reject (probe cases for validator self-tests).
    case reject
    /// No dry-run for this tool; the case is scored on arguments only and the result is
    /// flagged `executionCovered: false` so the blind spot stays visible.
    case skip
}

public struct ExpectedCall: Sendable, Equatable, Codable {
    public let tool: String
    public let arguments: [String: ArgumentMatcher]
    public let execution: ExecutionExpectation

    public init(
        _ tool: String,
        _ arguments: [String: ArgumentMatcher] = [:],
        execution: ExecutionExpectation = .accept
    ) {
        self.tool = tool
        self.arguments = arguments
        self.execution = execution
    }
}

public struct EvalCase: Identifiable, Sendable, Equatable, Codable {
    /// Stable slug, not a UUID: report files are meant to be committed and diffed across
    /// models and months, which a per-launch identifier makes impossible.
    public let id: String
    public let transcript: String
    public let caseClass: EvalCaseClass
    /// The complete expected call sequence. Empty means "no tool should fire".
    public let expected: [ExpectedCall]
    /// Multi-step chains care about order; parallel calls in one turn do not.
    public let orderMatters: Bool
    /// Ambiguity cases: the reply must actually ask something.
    public let requiresQuestion: Bool
    public let note: String?

    public init(
        id: String,
        transcript: String,
        caseClass: EvalCaseClass,
        expected: [ExpectedCall] = [],
        orderMatters: Bool = false,
        requiresQuestion: Bool = false,
        note: String? = nil
    ) {
        self.id = id
        self.transcript = transcript
        self.caseClass = caseClass
        self.expected = expected
        self.orderMatters = orderMatters
        self.requiresQuestion = requiresQuestion
        self.note = note
    }

    /// One-line summary of what the case demands, for the debug UI and the manifest.
    public var expectationSummary: String {
        guard !expected.isEmpty else {
            return requiresQuestion ? "no tool call — a clarifying question" : "no tool call"
        }
        return expected.map(\.tool).joined(separator: " → ")
    }
}

public enum EvalOutcome: Sendable, Equatable, Codable {
    case pass
    case wrongTool(expected: String, got: String)
    case missingCall(expected: String, text: String)
    /// A negative/ambiguity case fired a tool.
    case unexpectedCall(String)
    /// More calls than the case expects.
    case spuriousExtraCall(String)
    case badArgument(tool: String, argument: String, why: String)
    /// The model's arguments were right, but the real tool would throw on them.
    case executionRejected(tool: String, why: String)
    /// The tool accepted arguments a `reject` probe said it should refuse — the validator
    /// itself is wrong, which matters because the validator is what scores everyone else.
    case executionAcceptedUnexpectedly(tool: String)
    /// Ambiguity case answered with a statement instead of a question.
    case notAQuestion(String)
    case parseError(String)
    case generationError(String)

    public var passed: Bool { self == .pass }

    public var label: String {
        switch self {
        case .pass: return "pass"
        case .wrongTool(let expected, let got): return "wrong tool: expected \(expected), got \(got)"
        case .missingCall(let expected, let text):
            return "no \(expected) call — said: \(text.prefix(100))"
        case .unexpectedCall(let name): return "fired \(name) when no tool was warranted"
        case .spuriousExtraCall(let name): return "spurious extra call: \(name)"
        case .badArgument(let tool, let argument, let why): return "\(tool).\(argument): \(why)"
        case .executionRejected(let tool, let why): return "\(tool) would throw: \(why)"
        case .executionAcceptedUnexpectedly(let tool): return "\(tool) accepted args it should reject"
        case .notAQuestion(let text): return "didn't ask, asserted: \(text.prefix(100))"
        case .parseError(let why): return "parse: \(why)"
        case .generationError(let why): return "error: \(why)"
        }
    }

    /// Coarse bucket for the report's failure summary.
    public var kind: String {
        switch self {
        case .pass: return "pass"
        case .wrongTool: return "wrongTool"
        case .missingCall: return "missingCall"
        case .unexpectedCall: return "unexpectedCall"
        case .spuriousExtraCall: return "spuriousExtraCall"
        case .badArgument: return "badArgument"
        case .executionRejected: return "executionRejected"
        case .executionAcceptedUnexpectedly: return "executionAcceptedUnexpectedly"
        case .notAQuestion: return "notAQuestion"
        case .parseError: return "parseError"
        case .generationError: return "generationError"
        }
    }
}
