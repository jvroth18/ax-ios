import SwiftUI

/// Ablation Lab: runs the golden tool-calling eval across every installed model in turn
/// (loading each one, honoring the single-resident rule) and tabulates score and speed —
/// which model actually earns its place on your phone.
struct AblationView: View {
    let modelManager: ModelManager
    @Environment(\.dismiss) private var dismiss

    struct Row: Identifiable {
        let id: String
        let name: String
        var status: String
        var passed: Int?
        var total: Int?
        var avgTokensPerSecond: Double?
        var failures: [String] = []
    }

    @State private var rows: [Row] = []
    @State private var running = false
    @State private var expandedRow: String?

    var body: some View {
        ZStack {
            W95Desktop()
            W95Window(title: "Ablation Lab", onClose: { dismiss() }) {
                VStack(spacing: 4) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            W95GroupBox(label: "What this does") {
                                Text("Runs \(EvalCase.golden.count) golden voice requests against every installed model, one after another, and scores whether each picks the right tool with the right arguments. Models load and unload in turn — expect a few minutes.")
                                    .font(W95.ui(12))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Button(running ? "Running…" : "Run Ablation") { Task { await runAblation() } }
                                .buttonStyle(W95ButtonStyle(bold: true))
                                .disabled(running || installedModels.isEmpty)
                            if installedModels.isEmpty {
                                Text("No models installed. Get some in the Model Library first.")
                                    .font(W95.ui(12))
                                    .foregroundStyle(W95.maroon)
                            }
                            if !rows.isEmpty {
                                resultsTable
                            }
                        }
                        .padding(8)
                    }
                    .w95Well(background: W95.face)
                    W95StatusBar(fields: [statusLine])
                }
                .padding(4)
                .background(W95.face)
            }
            .padding(6)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var installedModels: [CatalogModel] {
        ModelCatalog.all.filter(modelManager.isDownloaded)
    }

    private var statusLine: String {
        if running { return "Working — leave the app open…" }
        if rows.isEmpty { return "\(installedModels.count) installed model(s) ready" }
        return "Done — best score first"
    }

    private var resultsTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Model").font(W95.ui(11, bold: true)).frame(maxWidth: .infinity, alignment: .leading)
                Text("Score").font(W95.ui(11, bold: true)).frame(width: 52, alignment: .trailing)
                Text("tok/s").font(W95.ui(11, bold: true)).frame(width: 52, alignment: .trailing)
            }
            .padding(6)
            .background(W95.navy)
            .foregroundStyle(.white)
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.name)
                            .font(W95.ui(12, bold: true))
                            .foregroundStyle(W95.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(scoreText(row))
                            .font(W95.mono(11, bold: true))
                            .foregroundStyle(scoreColor(row))
                            .frame(width: 52, alignment: .trailing)
                        Text(row.avgTokensPerSecond.map { String(format: "%.0f", $0) } ?? "—")
                            .font(W95.mono(11))
                            .foregroundStyle(W95.text)
                            .frame(width: 52, alignment: .trailing)
                    }
                    if row.status != "done" {
                        Text(row.status).font(W95.ui(11)).foregroundStyle(W95.shadow)
                    }
                    if expandedRow == row.id, !row.failures.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(row.failures, id: \.self) { failure in
                                Text("✗ \(failure)")
                                    .font(W95.mono(10))
                                    .foregroundStyle(W95.maroon)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(6)
                .background(.white)
                .overlay(Rectangle().fill(W95.shadow.opacity(0.3)).frame(height: 1), alignment: .bottom)
                .onTapGesture {
                    expandedRow = expandedRow == row.id ? nil : row.id
                }
            }
            Text("Tap a row to see its failures.")
                .font(W95.ui(10))
                .foregroundStyle(W95.shadow)
                .padding(4)
        }
        .overlay(W95BevelOverlay(sunken: true))
    }

    private func scoreText(_ row: Row) -> String {
        guard let passed = row.passed, let total = row.total else { return "…" }
        return "\(passed)/\(total)"
    }

    private func scoreColor(_ row: Row) -> Color {
        guard let passed = row.passed, let total = row.total, total > 0 else { return W95.shadow }
        let ratio = Double(passed) / Double(total)
        if ratio >= 0.8 { return Color(red: 0, green: 0.5, blue: 0) }
        if ratio >= 0.5 { return Color(red: 0.7, green: 0.45, blue: 0) }
        return .red
    }

    private func runAblation() async {
        running = true
        defer { running = false }
        let original = modelManager.choice
        let models = installedModels
        rows = models.map { Row(id: $0.id, name: $0.name, status: "queued") }

        let registry = ToolRegistry.standard
        let system = EvalHarness.systemPrompt()

        for model in models {
            setStatus(model.id, "loading…")
            await modelManager.switchTo(model)
            guard let container = modelManager.container else {
                setStatus(model.id, "failed to load")
                continue
            }
            var passed = 0
            var failures: [String] = []
            var speeds: [Double] = []
            for (index, evalCase) in EvalCase.golden.enumerated() {
                setStatus(model.id, "case \(index + 1)/\(EvalCase.golden.count)…")
                let before = MetricsStore.shared.generations.count
                let outcome = await EvalHarness.run(
                    evalCase, container: container, system: system, registry: registry
                )
                if outcome.passed {
                    passed += 1
                } else {
                    failures.append("\(evalCase.expectedTool): \(outcome.label)")
                }
                // The generator reports each run to MetricsStore; read the speed back.
                if MetricsStore.shared.generations.count > before,
                   let record = MetricsStore.shared.generations.last {
                    speeds.append(record.tokensPerSecond)
                }
            }
            update(model.id) { row in
                row.status = "done"
                row.passed = passed
                row.total = EvalCase.golden.count
                row.avgTokensPerSecond = speeds.isEmpty ? nil : speeds.reduce(0, +) / Double(speeds.count)
                row.failures = failures
            }
        }

        rows.sort { ($0.passed ?? -1) > ($1.passed ?? -1) }
        // Put the model the user had loaded back.
        await modelManager.switchTo(original)
    }

    private func setStatus(_ id: String, _ status: String) {
        update(id) { $0.status = status }
    }

    private func update(_ id: String, _ transform: (inout Row) -> Void) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        transform(&rows[index])
    }
}
