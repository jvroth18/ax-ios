import Foundation
import AXCore

/// `ax-eval` — the Mac-side eval harness.
///
/// WHY it exists: `EvalView`'s doc comment has always told readers to "use the CLI eval
/// harness on the Mac" for cross-model comparison, and there was no such thing. Every
/// published score therefore came from someone tapping a button on a phone and typing the
/// number into a commit message. This tool makes the two halves that don't need MLX —
/// building the pinned prompt, and scoring completions — runnable and diffable anywhere.
///
///   swift run ax-eval prompt [model-id] [outFile]  # exact pinned shipping prompt/profile
///   swift run ax-eval manifest [outDir]            # committable description of the suite
///   swift run ax-eval score completions.json [out] # score recorded completions
///
/// The completions file is `{"model": "...", "completions": {"case-id": "raw completion"}}`.
/// A value may also be an array of strings — the successive completions of one agent-loop
/// turn — which is how multi-step cases are replayed.

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case io(String)
    var description: String {
        switch self {
        case .usage(let message): return "usage: \(message)"
        case .io(let message): return message
        }
    }
}

/// One recorded case: either a single completion or a loop's worth of them.
struct RecordedCompletions: Decodable {
    let model: String
    let completions: [String: [String]]

    private enum CodingKeys: String, CodingKey { case model, completions }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? "unknown"
        let raw = try container.decode([String: JSONValue].self, forKey: .completions)
        completions = raw.compactMapValues { value in
            if let single = value.stringValue { return [single] }
            return value.arrayValue?.compactMap(\.stringValue)
        }
    }
}

func write(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
    FileHandle.standardError.write(Data("wrote \(url.path)\n".utf8))
}

func outputDirectory(_ arguments: [String], index: Int) -> URL {
    let path = arguments.count > index ? arguments[index] : "evals"
    return URL(fileURLWithPath: path, isDirectory: true)
}

func runManifest(_ arguments: [String]) throws {
    let directory = outputDirectory(arguments, index: 2)
    try write(
        Data(EvalReport.suiteManifestMarkdown().utf8),
        to: directory.appendingPathComponent("suite-\(EvalSuite.version).md")
    )
    try write(
        try EvalReport.suiteManifestJSON(),
        to: directory.appendingPathComponent("suite-\(EvalSuite.version).json")
    )
}

func runScore(_ arguments: [String]) throws {
    guard arguments.count > 2 else {
        throw CLIError.usage("ax-eval score <completions.json> [outDir]")
    }
    let inputURL = URL(fileURLWithPath: arguments[2])
    guard let data = FileManager.default.contents(atPath: inputURL.path) else {
        throw CLIError.io("cannot read \(inputURL.path)")
    }
    let recorded = try JSONDecoder().decode(RecordedCompletions.self, from: data)

    var results: [EvalCaseResult] = []
    for evalCase in EvalSuite.all {
        guard let completions = recorded.completions[evalCase.id] else {
            // A missing recording is reported, not skipped: a suite scored on 12 of 43
            // cases must never be presentable as a score out of 12.
            results.append(EvalCaseResult(
                evalCase: evalCase,
                judgment: EvalJudgment(
                    outcome: .generationError("no completion recorded"),
                    emittedCalls: [], executionCovered: false
                )
            ))
            continue
        }
        results.append(EvalCaseResult(
            evalCase: evalCase, judgment: judge(evalCase, completions: completions)
        ))
    }

    let report = EvalReport(modelID: recorded.model, results: results)
    let directory = outputDirectory(arguments, index: 3)
    let slug = recorded.model.replacingOccurrences(of: "/", with: "_")
    try write(try report.jsonData(), to: directory.appendingPathComponent("results-\(slug).json"))
    try write(Data(report.markdown().utf8), to: directory.appendingPathComponent("results-\(slug).md"))
    print("\(report.passed)/\(report.total) overall")
    for caseClass in EvalCaseClass.allCases {
        let score = report.score(for: caseClass)
        guard score.total > 0 else { continue }
        print("  \(caseClass.rawValue): \(score.passed)/\(score.total)")
    }
}

/// Accumulates calls across a replayed loop so a multi-step case is scored on the whole
/// chain, exactly as the on-device harness scores a live one.
func judge(_ evalCase: EvalCase, completions: [String]) -> EvalJudgment {
    var calls: [ToolCall] = []
    var lastText = ""
    for completion in completions {
        do {
            let parsed = try ToolCallParser.parse(completion, tools: EvalToolCatalog.specs)
            calls.append(contentsOf: parsed.toolCalls)
            if !parsed.text.isEmpty { lastText = parsed.text }
        } catch {
            return EvalJudgment(
                outcome: .parseError("\(error)"),
                emittedCalls: calls.map(EvalJudge.summary),
                executionCovered: false
            )
        }
    }
    return EvalJudge.judge(evalCase, calls: calls, replyText: lastText)
}

func runPrompt(_ arguments: [String]) {
    let profile = arguments.count > 2
        ? PromptProfile.forModel(arguments[2])
        : PromptProfile.standard
    let prompt = PromptBuilder.systemPrompt(
        tools: EvalToolCatalog.specs,
        context: .init(
            currentDateTime: EvalClock.pinned.promptDateTime,
            registeredShortcuts: EvalToolCatalog.pinnedShortcuts
        ),
        profile: profile
    )
    if arguments.count > 3 {
        do {
            try write(Data(prompt.utf8), to: URL(fileURLWithPath: arguments[3]))
        } catch {
            FileHandle.standardError.write(Data("ax-eval: \(error)\n".utf8))
            exit(1)
        }
    } else {
        print(prompt)
    }
}

let arguments = CommandLine.arguments
do {
    switch arguments.count > 1 ? arguments[1] : "" {
    case "manifest": try runManifest(arguments)
    case "score": try runScore(arguments)
    case "prompt": runPrompt(arguments)
    default:
        throw CLIError.usage("ax-eval <prompt|manifest|score> …")
    }
} catch {
    FileHandle.standardError.write(Data("ax-eval: \(error)\n".utf8))
    exit(1)
}
