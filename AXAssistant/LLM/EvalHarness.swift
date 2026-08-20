import Foundation
import AXCore
import MLXLMCommon

/// Device-side driver for the tool-calling eval.
///
/// The cases, matchers, scoring and report rendering all live in `Packages/AXCore/Eval`,
/// which is platform-free and covered by `swift test`; this file only does the parts that
/// need MLX and the real tool registry: generate, run the agent loop for chained cases, and
/// write the results artifact. `swift run ax-eval` drives the same AXCore scoring on a Mac.
///
/// What changed from the harness this replaces, and why:
///  - **Dates are checked.** `expectedArgs: ["due": nil]` used to assert key existence, so
///    every date case passed on any value at all. Cases now compare the emitted instant
///    against a fixed reference "now" (`EvalClock.pinned`), which is also what gets injected
///    into the system prompt — so "tomorrow at noon" has exactly one right answer.
///  - **Every call is scored**, not `toolCalls.first`; extra calls fail explicitly.
///  - **Negative, ambiguity and multi-step classes exist**, so spurious firing and chaining
///    are measurable at all.
///  - **Arguments are dry-run** through the tools' real acceptance rules (`AppToolValidator`),
///    which is how a tool that throws on well-formed model output gets caught instead of
///    scoring a pass for 43 commits.
enum EvalHarness {

    /// The pinned system prompt. The registered-shortcut list and the current-date line are
    /// both fixed, because both change what the model is allowed to answer.
    @MainActor
    static func systemPrompt(
        registry: ToolRegistry,
        profile: PromptProfile? = nil
    ) -> String {
        PromptBuilder.systemPrompt(
            tools: registry.specs,
            context: PromptBuilder.Context(
                currentDateTime: EvalClock.pinned.promptDateTime,
                registeredShortcuts: EvalToolCatalog.pinnedShortcuts
            ),
            profile: profile ?? currentProfile()
        )
    }

    /// The profile the loaded model would get in production, so a score measures the
    /// prompt the user actually ships with rather than a generic one.
    @MainActor
    static func currentProfile() -> PromptProfile {
        PromptProfile.forModel(ModelManager.shared.choice.id)
    }

    static let validator = AppToolValidator(registeredShortcuts: EvalToolCatalog.pinnedShortcuts)

    /// Single-turn cases: generate once, parse, score.
    static func run(
        _ evalCase: EvalCase,
        container: ModelContainer,
        system: String,
        registry: ToolRegistry
    ) async -> EvalJudgment {
        do {
            let completion = try await LLMGenerator.generate(
                container: container,
                messages: [
                    ChatMessage(role: .system, content: system),
                    ChatMessage(role: .user, content: evalCase.transcript),
                ]
            )
            return EvalJudge.judge(
                evalCase, completion: completion, tools: registry.specs, validator: validator
            )
        } catch {
            return EvalJudgment(
                outcome: .generationError(error.localizedDescription),
                emittedCalls: [], executionCovered: false
            )
        }
    }

    /// Chained cases: drive the real `AgentLoop` over a stub registry and score the whole
    /// sequence of calls it produced.
    ///
    /// Caveat worth knowing when reading a report: `AgentLoop` builds its own system prompt
    /// from `formattedNow()`, so multi-step cases run against the wall clock, not the pinned
    /// one. None of them involve dates for that reason.
    @MainActor
    static func runMultiStep(
        _ evalCase: EvalCase,
        container: ModelContainer,
        registry: ToolRegistry
    ) async -> EvalJudgment {
        let profile = currentProfile()
        let loop = AgentLoop(
            container: container,
            registry: EvalStubRegistry.make(mirroring: registry),
            confirmer: EvalAutoConfirmer(),
            config: AgentConfig(
                maxToolIterations: profile.suggestedMaxToolIterations ?? AgentConfig().maxToolIterations
            ),
            profile: profile
        )
        do {
            let turn = try await loop.run(userText: evalCase.transcript, onPartial: { _ in })
            return EvalJudge.judge(
                evalCase, calls: turn.toolCalls, replyText: turn.reply, validator: validator
            )
        } catch {
            return EvalJudgment(
                outcome: .generationError(error.localizedDescription),
                emittedCalls: [], executionCovered: false
            )
        }
    }

    /// Runs the whole suite and assembles a committable report.
    ///
    /// `onCase` fires as each case finishes so the debug screen can fill in live; the
    /// returned report is the artifact.
    @MainActor
    static func runAll(
        container: ModelContainer,
        cases: [EvalCase] = EvalSuite.all,
        onCase: @MainActor (EvalCase, EvalJudgment) -> Void = { _, _ in }
    ) async -> EvalReport {
        let registry = ToolRegistry.standard
        let system = systemPrompt(registry: registry)
        let metricsBaseline = MetricsStore.shared.generations.count

        var results: [EvalCaseResult] = []
        for evalCase in cases {
            let started = Date()
            let judgment: EvalJudgment
            // Workflow cases run the real loop too: the behaviour under test is whether the
            // model collapses repetition into one call *and then keeps going*, which only
            // exists inside AgentLoop.
            if evalCase.caseClass == .multiStep || evalCase.caseClass == .workflow {
                judgment = await runMultiStep(evalCase, container: container, registry: registry)
            } else {
                judgment = await run(
                    evalCase, container: container, system: system, registry: registry
                )
            }
            onCase(evalCase, judgment)
            results.append(EvalCaseResult(
                evalCase: evalCase,
                judgment: judgment,
                durationSeconds: Date().timeIntervalSince(started)
            ))
        }

        return EvalReport(
            modelID: MetricsStore.shared.loadedModelID ?? "unknown",
            promptProfile: currentProfile().name,
            catalogDrift: drift(registry: registry),
            results: results,
            metrics: metrics(since: metricsBaseline)
        )
    }

    /// Everything that would make a score untrustworthy: an eval tool catalog that no longer
    /// matches the live registry, or a dry-run validator that disagrees with the contract
    /// table the Mac-side tests score against.
    @MainActor
    static func drift(registry: ToolRegistry) -> [String] {
        EvalToolCatalog.drift(from: registry.specs)
            + validator.drift().map { "contract: \($0)" }
    }

    /// Pulls the throughput and memory numbers `MetricsStore` recorded *during this run*,
    /// so the report says how fast and how heavy the scores were, in the same file.
    @MainActor
    static func metrics(since baseline: Int) -> EvalRunMetrics {
        let store = MetricsStore.shared
        let fresh = Array(store.generations.dropFirst(baseline))
        guard !fresh.isEmpty else { return EvalRunMetrics() }
        func mean(_ values: [Double]) -> Double {
            values.reduce(0, +) / Double(values.count)
        }
        return EvalRunMetrics(
            tokensPerSecond: mean(fresh.map(\.tokensPerSecond)),
            promptTokensPerSecond: mean(fresh.map(\.promptTokensPerSecond)),
            timeToFirstTokenSeconds: mean(fresh.map(\.timeToFirstToken)),
            peakFootprintMB: Double(fresh.map(\.footprintBytes).max() ?? 0) / 1_048_576,
            gpuPeakMB: Double(fresh.map(\.gpuPeakBytes).max() ?? 0) / 1_048_576,
            modelLoadSeconds: store.modelLoadDuration
        )
    }

    // MARK: - Artifact

    /// Writes `results-<model>-<timestamp>.json` and `.md` into Documents/evals and returns
    /// the JSON URL.
    ///
    /// WHY files: until now every published eval number ("9/9 on the tool-calling eval", in
    /// two `ModelCatalog` blurbs) existed only as prose. A run should leave behind something
    /// a person can open, diff, and commit next to the claim.
    static func writeReport(_ report: EvalReport) throws -> URL {
        let directory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("evals", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let slug = report.modelID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "-")
        let base = "results-\(slug)-\(formatter.string(from: report.generatedAt))"

        let jsonURL = directory.appendingPathComponent("\(base).json")
        try report.jsonData().write(to: jsonURL, options: .atomic)
        try Data(report.markdown().utf8)
            .write(to: directory.appendingPathComponent("\(base).md"), options: .atomic)
        return jsonURL
    }
}
