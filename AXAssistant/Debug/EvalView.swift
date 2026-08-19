#if DEBUG
import SwiftUI
import AXCore

/// Debug golden-transcript eval against the currently loaded model. For cross-model
/// comparison, use the CLI eval harness on the Mac.
struct EvalView: View {
    let modelManager: ModelManager

    enum RowState: Equatable {
        case pending, running
        case done(EvalHarness.Outcome)
    }

    @State private var outcomes: [UUID: RowState] = [:]
    @State private var running = false

    var body: some View {
        List {
            Section {
                Button(running ? "Running…" : "Run all") { Task { await runAll() } }
                    .disabled(running || modelManager.container == nil)
                if let score {
                    Text("Score: \(score.passed)/\(score.total)")
                        .font(.headline)
                }
            }
            Section("Cases") {
                ForEach(EvalCase.golden) { evalCase in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("“\(evalCase.transcript)”")
                        Text("expects \(evalCase.expectedTool)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        rowLabel(outcomes[evalCase.id] ?? .pending)
                    }
                }
            }
        }
        .navigationTitle("Tool-call eval")
    }

    private var score: (passed: Int, total: Int)? {
        let finished = outcomes.values.compactMap { state -> EvalHarness.Outcome? in
            if case .done(let outcome) = state { return outcome }
            return nil
        }
        guard finished.count == EvalCase.golden.count else { return nil }
        return (finished.filter(\.passed).count, finished.count)
    }

    @ViewBuilder
    private func rowLabel(_ state: RowState) -> some View {
        switch state {
        case .pending:
            Label("pending", systemImage: "circle.dotted").foregroundStyle(.tertiary)
        case .running:
            ProgressView()
        case .done(.pass):
            Label("pass", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .done(let outcome):
            Label(outcome.label, systemImage: "xmark.circle").foregroundStyle(.red)
        }
    }

    private func runAll() async {
        guard let container = modelManager.container else { return }
        running = true
        defer { running = false }

        let registry = ToolRegistry.standard
        let system = EvalHarness.systemPrompt()
        for evalCase in EvalCase.golden {
            outcomes[evalCase.id] = .running
            let outcome = await EvalHarness.run(
                evalCase, container: container, system: system, registry: registry
            )
            outcomes[evalCase.id] = .done(outcome)
        }
    }
}
#endif
