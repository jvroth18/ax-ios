#if DEBUG
import SwiftUI
import UIKit
import AXCore

/// Debug tool-calling eval against the currently loaded model.
///
/// Scores are reported per case class, because they mean different things: `singleTool` is
/// table stakes, `dateExtraction` decides whether the model can be trusted with a calendar,
/// and `negative` measures the failure that actually costs a user something — a tool firing
/// when none should. A run writes a JSON + Markdown artifact to Documents/evals.
///
/// The same suite and scoring run on a Mac without MLX:
///   cd Packages/AXCore && swift run ax-eval prompt|manifest|score
struct EvalView: View {
    let modelManager: ModelManager

    enum RowState: Equatable {
        case pending, running
        case done(EvalJudgment)
    }

    @State private var states: [String: RowState] = [:]
    @State private var running = false
    @State private var report: EvalReport?
    @State private var savedPath: String?
    @State private var saveError: String?

    var body: some View {
        List {
            Section {
                Button(running ? "Running…" : "Run all \(EvalSuite.all.count) cases") {
                    Task { await runAll() }
                }
                .disabled(running || modelManager.container == nil)

                if let report {
                    LabeledContent("Overall") {
                        Text("\(report.passed)/\(report.total)")
                            .font(.headline.monospacedDigit())
                    }
                    if report.uncoveredPasses > 0 {
                        Label(
                            "\(report.uncoveredPasses) passing case(s) had no execution check",
                            systemImage: "questionmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    ForEach(report.catalogDrift, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button("Copy Markdown report") {
                        UIPasteboard.general.string = report.markdown()
                    }
                    if let savedPath {
                        Text("Saved to \(savedPath)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let saveError {
                        Text(saveError).font(.caption2).foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Suite \(EvalSuite.version)")
            } footer: {
                Text("\"Now\" is pinned to \(EvalClock.pinned.promptDateTime) so relative dates "
                     + "have one correct answer.")
            }

            ForEach(EvalCaseClass.allCases, id: \.self) { caseClass in
                let cases = EvalSuite.cases(in: caseClass)
                if !cases.isEmpty {
                    Section {
                        ForEach(cases) { evalCase in
                            row(evalCase)
                        }
                    } header: {
                        HStack {
                            Text(caseClass.title)
                            Spacer()
                            Text(classScore(caseClass))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle("Tool-call eval")
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ evalCase: EvalCase) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("“\(evalCase.transcript)”")
            Text("expects \(evalCase.expectationSummary)")
                .font(.caption)
                .foregroundStyle(.secondary)
            switch states[evalCase.id] ?? .pending {
            case .pending:
                Label("pending", systemImage: "circle.dotted").foregroundStyle(.tertiary)
            case .running:
                ProgressView()
            case .done(let judgment) where judgment.passed:
                Label(
                    judgment.executionCovered ? "pass" : "pass (arguments only)",
                    systemImage: judgment.executionCovered
                        ? "checkmark.circle.fill" : "checkmark.circle"
                )
                .foregroundStyle(judgment.executionCovered ? .green : .orange)
            case .done(let judgment):
                VStack(alignment: .leading, spacing: 2) {
                    Label(judgment.outcome.label, systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                    ForEach(judgment.emittedCalls, id: \.self) { call in
                        Text(call).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.callout)
    }

    private func classScore(_ caseClass: EvalCaseClass) -> String {
        let cases = EvalSuite.cases(in: caseClass)
        let finished = cases.compactMap { evalCase -> EvalJudgment? in
            if case .done(let judgment) = states[evalCase.id] ?? .pending { return judgment }
            return nil
        }
        guard !finished.isEmpty else { return "—" }
        return "\(finished.filter(\.passed).count)/\(finished.count)"
    }

    // MARK: - Running

    private func runAll() async {
        guard let container = modelManager.container else { return }
        running = true
        savedPath = nil
        saveError = nil
        report = nil
        let cases = EvalSuite.all
        states = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, RowState.pending) })
        states[cases[0].id] = .running
        defer { running = false }

        // The harness reports each case as it lands; the row after it becomes the spinner,
        // so a long run shows where it is instead of freezing on "Running…".
        let finished = await EvalHarness.runAll(container: container, cases: cases) { evalCase, judgment in
            states[evalCase.id] = .done(judgment)
            if let index = cases.firstIndex(where: { $0.id == evalCase.id }),
               index + 1 < cases.count {
                states[cases[index + 1].id] = .running
            }
        }
        report = finished
        do {
            savedPath = try EvalHarness.writeReport(finished).lastPathComponent
        } catch {
            saveError = "Could not write the report: \(error.localizedDescription)"
        }
    }
}
#endif
