import Foundation

/// One case's result, as written to the results file.
public struct EvalCaseResult: Sendable, Codable, Identifiable {
    public let id: String
    public let transcript: String
    public let caseClass: EvalCaseClass
    public let expectation: String
    public let passed: Bool
    public let outcomeKind: String
    public let detail: String
    public let emittedCalls: [String]
    public let executionCovered: Bool
    public let durationSeconds: Double?

    public init(evalCase: EvalCase, judgment: EvalJudgment, durationSeconds: Double? = nil) {
        self.id = evalCase.id
        self.transcript = evalCase.transcript
        self.caseClass = evalCase.caseClass
        self.expectation = evalCase.expectationSummary
        self.passed = judgment.passed
        self.outcomeKind = judgment.outcome.kind
        self.detail = judgment.outcome.label
        self.emittedCalls = judgment.emittedCalls
        self.executionCovered = judgment.executionCovered
        self.durationSeconds = durationSeconds
    }
}

/// The performance numbers `MetricsStore` already collects, carried into the same artifact
/// as the scores. WHY together: "9/9" is meaningless without "…at 4 tok/s and 3.2 GB",
/// and until now the two lived in different places (a commit message and a debug screen).
public struct EvalRunMetrics: Sendable, Codable {
    public var tokensPerSecond: Double?
    public var promptTokensPerSecond: Double?
    public var timeToFirstTokenSeconds: Double?
    public var peakFootprintMB: Double?
    public var gpuPeakMB: Double?
    public var modelLoadSeconds: Double?

    public init(
        tokensPerSecond: Double? = nil,
        promptTokensPerSecond: Double? = nil,
        timeToFirstTokenSeconds: Double? = nil,
        peakFootprintMB: Double? = nil,
        gpuPeakMB: Double? = nil,
        modelLoadSeconds: Double? = nil
    ) {
        self.tokensPerSecond = tokensPerSecond
        self.promptTokensPerSecond = promptTokensPerSecond
        self.timeToFirstTokenSeconds = timeToFirstTokenSeconds
        self.peakFootprintMB = peakFootprintMB
        self.gpuPeakMB = gpuPeakMB
        self.modelLoadSeconds = modelLoadSeconds
    }
}

/// A complete, committable eval run.
///
/// This type exists because the repo had no recorded eval results anywhere: the "9/9"
/// figures shipped in `ModelCatalog` blurbs were traceable only to commit messages. A run
/// now produces a file with the suite version, the pinned clock, the model, every case's
/// outcome and the throughput/memory numbers — enough to re-derive the claim or refute it.
public struct EvalReport: Sendable, Codable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let generatedAt: Date
    public let modelID: String
    public let suiteVersion: String
    public let referenceNow: String
    /// Which prompt variant produced this score. Without it, two runs of the same model
    /// are indistinguishable after the prompt changes underneath them — which is the
    /// whole failure mode per-model prompt tuning introduces.
    public let promptProfile: String
    /// Non-empty when the eval's tool catalog no longer matches the live registry — the
    /// results are then scored against stale specs and should not be trusted.
    public let catalogDrift: [String]
    public let results: [EvalCaseResult]
    public let metrics: EvalRunMetrics?

    public init(
        modelID: String,
        suiteVersion: String = EvalSuite.version,
        clock: EvalClock = .pinned,
        promptProfile: String = PromptProfile.standard.name,
        catalogDrift: [String] = [],
        results: [EvalCaseResult],
        metrics: EvalRunMetrics? = nil,
        generatedAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt
        self.modelID = modelID
        self.suiteVersion = suiteVersion
        self.referenceNow = clock.promptDateTime
        self.promptProfile = promptProfile
        self.catalogDrift = catalogDrift
        self.results = results
        self.metrics = metrics
    }

    public var passed: Int { results.filter(\.passed).count }
    public var total: Int { results.count }

    public func score(for caseClass: EvalCaseClass) -> (passed: Int, total: Int) {
        let subset = results.filter { $0.caseClass == caseClass }
        return (subset.filter(\.passed).count, subset.count)
    }

    /// Wall-clock spread across cases. Correctness alone hides the regression that
    /// matters most for a voice assistant: 9/9 taking forty seconds is worse than 8/9
    /// taking four, and nothing in a pass/fail count says so.
    public struct Latency: Sendable, Equatable {
        public let median: Double
        public let p95: Double
        public let slowest: [(id: String, seconds: Double)]

        public static func == (a: Latency, b: Latency) -> Bool {
            a.median == b.median && a.p95 == b.p95
                && a.slowest.map(\.id) == b.slowest.map(\.id)
        }
    }

    public var latency: Latency? {
        let timed = results.compactMap { result -> (String, Double)? in
            guard let seconds = result.durationSeconds else { return nil }
            return (result.id, seconds)
        }
        guard !timed.isEmpty else { return nil }
        let sorted = timed.map(\.1).sorted()
        func quantile(_ q: Double) -> Double {
            let index = Int((Double(sorted.count - 1) * q).rounded())
            return sorted[min(max(index, 0), sorted.count - 1)]
        }
        return Latency(
            median: quantile(0.5),
            p95: quantile(0.95),
            slowest: timed.sorted { $0.1 > $1.1 }.prefix(3).map { (id: $0.0, seconds: $0.1) }
        )
    }

    /// How many passing cases were never dry-run against a tool's real acceptance rules.
    public var uncoveredPasses: Int {
        results.filter { $0.passed && !$0.executionCovered }.count
    }

    // MARK: - Rendering

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> EvalReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EvalReport.self, from: data)
    }

    /// A Markdown report: headline score, per-class table, failure list, metrics.
    /// Meant to be pasted into a PR or committed next to the JSON.
    public func markdown() -> String {
        var lines: [String] = []
        lines.append("# Tool-calling eval — \(modelID)")
        lines.append("")
        lines.append("- Suite `\(suiteVersion)` · schema v\(schemaVersion)")
        lines.append("- Run \(Self.timestamp(generatedAt))")
        lines.append("- Reference \"now\" pinned to **\(referenceNow)**")
        lines.append("- Prompt profile: **\(promptProfile)**")
        lines.append("- **Overall: \(passed)/\(total)** (\(Self.percent(passed, total)))")
        if let latency {
            lines.append(String(
                format: "- Latency: median %.1fs · p95 %.1fs · slowest %@",
                latency.median, latency.p95,
                latency.slowest.map { String(format: "%@ (%.1fs)", $0.id, $0.seconds) }
                    .joined(separator: ", ")
            ))
        }
        if uncoveredPasses > 0 {
            lines.append("- \(uncoveredPasses) passing case(s) had **no execution coverage** — "
                         + "arguments were scored, but no tool validated them.")
        }
        if !catalogDrift.isEmpty {
            lines.append("")
            lines.append("> **Catalog drift — results are suspect.** The eval's tool mirror no longer "
                         + "matches the live registry:")
            for problem in catalogDrift { lines.append("> - \(problem)") }
        }
        lines.append("")
        lines.append("## By case class")
        lines.append("")
        lines.append("| Class | Pass | Total | Rate |")
        lines.append("| --- | ---: | ---: | ---: |")
        for caseClass in EvalCaseClass.allCases {
            let score = self.score(for: caseClass)
            guard score.total > 0 else { continue }
            lines.append("| \(caseClass.title) | \(score.passed) | \(score.total) "
                         + "| \(Self.percent(score.passed, score.total)) |")
        }

        let failures = results.filter { !$0.passed }
        lines.append("")
        lines.append("## Failures (\(failures.count))")
        lines.append("")
        if failures.isEmpty {
            lines.append("None.")
        } else {
            lines.append("| Case | Class | Expected | What happened |")
            lines.append("| --- | --- | --- | --- |")
            for failure in failures {
                lines.append("| `\(failure.id)` | \(failure.caseClass.rawValue) "
                             + "| \(Self.escape(failure.expectation)) | \(Self.escape(failure.detail)) |")
            }
        }

        if let metrics {
            lines.append("")
            lines.append("## Performance")
            lines.append("")
            lines.append("| Metric | Value |")
            lines.append("| --- | ---: |")
            func row(_ name: String, _ value: Double?, _ format: String) {
                guard let value else { return }
                lines.append("| \(name) | \(String(format: format, value)) |")
            }
            row("Generation", metrics.tokensPerSecond, "%.1f tok/s")
            row("Prompt prefill", metrics.promptTokensPerSecond, "%.1f tok/s")
            row("Time to first token", metrics.timeToFirstTokenSeconds, "%.2f s")
            row("Peak process footprint", metrics.peakFootprintMB, "%.0f MB")
            row("Peak MLX GPU memory", metrics.gpuPeakMB, "%.0f MB")
            row("Model load", metrics.modelLoadSeconds, "%.1f s")
        }

        lines.append("")
        lines.append("## All cases")
        lines.append("")
        lines.append("| Case | Class | Result | Emitted |")
        lines.append("| --- | --- | --- | --- |")
        for result in results {
            let mark = result.passed ? (result.executionCovered ? "pass" : "pass (unvalidated)") : "FAIL"
            let emitted = result.emittedCalls.isEmpty
                ? "_(no call)_" : result.emittedCalls.map { "`\(Self.escape($0))`" }.joined(separator: "<br>")
            lines.append("| `\(result.id)` | \(result.caseClass.rawValue) | \(mark) | \(emitted) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The suite itself, rendered without running anything — a committable description of
    /// what the eval actually asserts, so a reader can audit the cases without Swift.
    public static func suiteManifestMarkdown(clock: EvalClock = .pinned) -> String {
        var lines: [String] = []
        lines.append("# Tool-calling eval suite `\(EvalSuite.version)`")
        lines.append("")
        lines.append("Reference \"now\" for every case: **\(clock.promptDateTime)**.")
        lines.append("")
        lines.append("\(EvalSuite.all.count) cases across \(EvalCaseClass.allCases.count) classes.")
        for caseClass in EvalCaseClass.allCases {
            let cases = EvalSuite.cases(in: caseClass)
            guard !cases.isEmpty else { continue }
            lines.append("")
            lines.append("## \(caseClass.title) (\(cases.count))")
            lines.append("")
            lines.append("| Case | Transcript | Expects |")
            lines.append("| --- | --- | --- |")
            for item in cases {
                var expects = escape(item.expectationSummary)
                let arguments = item.expected.flatMap { call in
                    call.arguments.keys.sorted().map { "\(call.tool).\($0)" }
                }
                if !arguments.isEmpty { expects += " · " + arguments.joined(separator: ", ") }
                lines.append("| `\(item.id)` | \"\(escape(item.transcript))\" | \(expects) |")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func suiteManifestJSON() throws -> Data {
        struct Manifest: Encodable {
            let suiteVersion: String
            let referenceNow: String
            let cases: [EvalCase]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Manifest(
            suiteVersion: EvalSuite.version,
            referenceNow: EvalClock.pinned.promptDateTime,
            cases: EvalSuite.all
        ))
    }

    // MARK: - Formatting helpers

    static func percent(_ passed: Int, _ total: Int) -> String {
        guard total > 0 else { return "n/a" }
        return String(format: "%.0f%%", Double(passed) / Double(total) * 100)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
