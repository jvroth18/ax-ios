import Foundation

/// The scored result of one case.
public struct EvalJudgment: Sendable, Equatable, Codable {
    public let outcome: EvalOutcome
    /// Every call the model emitted, rendered "tool(k=v, k=v)". Recorded even on a pass so
    /// a committed report can be re-read later without re-running the model.
    public let emittedCalls: [String]
    /// False when no validator could dry-run one of the emitted tools — i.e. the case
    /// passed but execution was never actually checked.
    public let executionCovered: Bool

    public var passed: Bool { outcome.passed }

    public init(outcome: EvalOutcome, emittedCalls: [String], executionCovered: Bool) {
        self.outcome = outcome
        self.emittedCalls = emittedCalls
        self.executionCovered = executionCovered
    }
}

/// Scores a completion (or an executed agent-loop turn) against a case.
///
/// Differences from the harness this replaces, all of them things that used to be invisible:
///   - **every** emitted call is scored, not `toolCalls.first`;
///   - extra calls are a failure with their own outcome, not silently dropped;
///   - date arguments are compared as instants against the pinned clock;
///   - "no tool call" is a first-class expected answer;
///   - arguments are run through the tool's real acceptance contract.
public enum EvalJudge {

    /// Convenience for the generation-only path: parse then judge.
    public static func judge(
        _ evalCase: EvalCase,
        completion: String,
        tools: [ToolSpec],
        clock: EvalClock = .pinned,
        validator: (any ToolExecutionValidating)? = ContractValidator.axAssistant
    ) -> EvalJudgment {
        let parsed: ParsedCompletion
        do {
            parsed = try ToolCallParser.parse(completion, tools: tools)
        } catch {
            // A completion the parser rejects is a real user-visible failure (the agent
            // loop burns a retry on it), so it is scored, not skipped.
            return EvalJudgment(
                outcome: .parseError("\(error)"), emittedCalls: [], executionCovered: false
            )
        }
        return judge(
            evalCase, calls: parsed.toolCalls, replyText: parsed.text,
            clock: clock, validator: validator
        )
    }

    public static func judge(
        _ evalCase: EvalCase,
        calls: [ToolCall],
        replyText: String,
        clock: EvalClock = .pinned,
        validator: (any ToolExecutionValidating)? = ContractValidator.axAssistant
    ) -> EvalJudgment {
        let emitted = calls.map(summary)
        var covered = true

        func finish(_ outcome: EvalOutcome) -> EvalJudgment {
            EvalJudgment(outcome: outcome, emittedCalls: emitted, executionCovered: covered)
        }

        // Negative and ambiguity cases: the correct behavior is silence-plus-words.
        guard !evalCase.expected.isEmpty else {
            if let first = calls.first { return finish(.unexpectedCall(first.name)) }
            if evalCase.requiresQuestion, !looksLikeAQuestion(replyText) {
                return finish(.notAQuestion(replyText))
            }
            return finish(.pass)
        }

        // Under-calling and over-calling are distinct diagnoses and are reported as such.
        if calls.count < evalCase.expected.count {
            let missing = evalCase.expected[calls.count].tool
            return finish(.missingCall(expected: missing, text: replyText))
        }

        let pairs: [(ExpectedCall, ToolCall)]
        let extras: [ToolCall]
        if evalCase.orderMatters {
            pairs = Array(zip(evalCase.expected, calls))
            extras = Array(calls.dropFirst(evalCase.expected.count))
        } else {
            var remaining = calls
            var matched: [(ExpectedCall, ToolCall)] = []
            for expectation in evalCase.expected {
                if let index = remaining.firstIndex(where: { $0.name == expectation.tool }) {
                    matched.append((expectation, remaining.remove(at: index)))
                } else {
                    // No call by that name at all: report it against the first spare call
                    // so the failure names both sides.
                    guard !remaining.isEmpty else {
                        return finish(.missingCall(expected: expectation.tool, text: replyText))
                    }
                    matched.append((expectation, remaining.removeFirst()))
                }
            }
            pairs = matched
            extras = remaining
        }

        for (expectation, call) in pairs {
            guard call.name == expectation.tool else {
                return finish(.wrongTool(expected: expectation.tool, got: call.name))
            }
            // Sorted so a call with two bad arguments always reports the same one — a
            // report that changes between identical runs is not an instrument.
            for key in expectation.arguments.keys.sorted() {
                guard let matcher = expectation.arguments[key] else { continue }
                if let why = matcher.mismatchReason(for: call.arguments[key], clock: clock) {
                    return finish(.badArgument(tool: call.name, argument: key, why: why))
                }
            }
        }

        // Extras are checked after argument matching so the report shows the more
        // actionable failure first when a case fails both ways.
        if let extra = extras.first { return finish(.spuriousExtraCall(extra.name)) }

        for (expectation, call) in pairs {
            switch expectation.execution {
            case .skip:
                covered = false
            case .accept:
                guard let validator, validator.covers(tool: call.name) else {
                    covered = false
                    continue
                }
                if let why = validator.rejectionReason(for: call) {
                    return finish(.executionRejected(tool: call.name, why: why))
                }
            case .reject:
                guard let validator, validator.covers(tool: call.name) else {
                    covered = false
                    continue
                }
                if validator.rejectionReason(for: call) == nil {
                    return finish(.executionAcceptedUnexpectedly(tool: call.name))
                }
            }
        }

        return finish(.pass)
    }

    /// "create_reminder(due=2026-08-19T17:00:00, title=Call mom)" — keys sorted for
    /// diffable reports.
    public static func summary(_ call: ToolCall) -> String {
        let arguments = call.arguments.keys.sorted()
            .map { "\($0)=\(ArgumentMatcher.display(call.arguments[$0]!))" }
            .joined(separator: ", ")
        return "\(call.name)(\(arguments))"
    }

    /// Deliberately loose: models phrase clarifying questions in many ways, and a case
    /// should fail for *guessing*, not for punctuation. A trailing "?" or a leading
    /// interrogative both count.
    static func looksLikeAQuestion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("?") { return true }
        let openers = ["what", "which", "who", "when", "where", "how", "could you tell", "let me know"]
        let lowered = trimmed.lowercased()
        return openers.contains { lowered.hasPrefix($0) || lowered.contains("\n\($0)") }
    }
}
