import SwiftUI
import UIKit

/// "System Monitor": needle gauges for the model's speed, Task-Manager-style history
/// charts for throughput and memory, and the M1 report exporter.
struct MetricsView: View {
    private let store = MetricsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var copiedReport = false

    // Sampling runs app-wide in MetricsStore; this screen just renders it.
    private var snapshot: SystemSnapshot? { store.lastSnapshot }

    /// M1 budget: stay under 2.5 GB in the memory gauge.
    private let footprintBudget = 2_500.0 * 1_048_576

    var body: some View {
        ZStack {
            W95Desktop()
            W95Window(title: "System Monitor", onClose: { dismiss() }) {
                VStack(spacing: 4) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            gaugesRow
                            W95GroupBox(label: "History") {
                                AXStripChart(
                                    values: store.generations.map(\.tokensPerSecond),
                                    maxValue: 60,
                                    label: "Tokens/sec per run",
                                    trailing: "avg \(String(format: "%.1f", store.averageTokensPerSecond)) · n=\(store.generations.count)"
                                )
                                AXStripChart(
                                    values: store.footprintTrace,
                                    maxValue: footprintBudget / 1_048_576,
                                    label: "App memory (2s ticks, budget 2500 MB)",
                                    trailing: snapshot.map { "now \(megabytes($0.footprintBytes)) · peak \(megabytes(store.peakFootprintBytes))" } ?? ""
                                )
                                AXStripChart(
                                    values: store.gpuActiveTrace,
                                    maxValue: max(store.gpuActiveTrace.max() ?? 1, 1) * 1.25,
                                    label: "MLX active memory",
                                    trailing: snapshot.map { "peak \(megabytes($0.gpuPeakBytes))" } ?? "",
                                    color: Color(red: 1.0, green: 0.85, blue: 0.0)
                                )
                            }
                            if let last = store.generations.last {
                                lastGenerationBox(last)
                            }
                            if let snapshot {
                                deviceBox(snapshot)
                            }
                            HStack(spacing: 6) {
                                Button(copiedReport ? "Copied ✓" : "Copy M1 Report") {
                                    UIPasteboard.general.string = store.m1Report
                                    copiedReport = true
                                }
                                .buttonStyle(W95ButtonStyle(bold: true))
                                ShareLink(item: store.m1Report) { Text("Share…") }
                                    .buttonStyle(W95ButtonStyle())
                            }
                        }
                        .padding(8)
                    }
                    .w95Well(background: W95.face)
                    W95StatusBar(fields: [
                        store.loadedModelID.map { "Model: \($0.replacingOccurrences(of: "mlx-community/", with: ""))" } ?? "No model loaded",
                        thermalText,
                    ])
                }
                .padding(4)
                .background(W95.face)
            }
            .padding(6)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var gaugesRow: some View {
        HStack(spacing: 8) {
            AXNeedleGauge(
                value: store.generations.last?.tokensPerSecond ?? 0,
                maxValue: 60,
                label: "Output tok/s",
                unit: "t/s",
                redline: 0.9
            )
            AXNeedleGauge(
                value: store.generations.last?.timeToFirstToken ?? 0,
                maxValue: 10,
                label: "First token",
                unit: "s",
                // M2 target is <4s to first token; past that is the red zone.
                redline: 0.4
            )
        }
    }

    private func lastGenerationBox(_ record: GenerationRecord) -> some View {
        W95GroupBox(label: "Last generation") {
            statRow("Prompt", "\(record.promptTokens) tok @ \(String(format: "%.0f", record.promptTokensPerSecond))/s")
            statRow("Output", "\(record.generationTokens) tok in \(String(format: "%.1f", record.generateTime)) s")
            statRow("First token", String(format: "%.2f s", record.timeToFirstToken))
        }
    }

    private func deviceBox(_ snapshot: SystemSnapshot) -> some View {
        W95GroupBox(label: "Device") {
            statRow("Memory headroom", megabytes(snapshot.availableBytes))
            statRow("MLX cache", "\(megabytes(snapshot.gpuCacheBytes)) / \(megabytes(snapshot.gpuCacheLimitBytes)) limit")
            if snapshot.batteryLevel >= 0 {
                statRow("Battery", "\(Int(snapshot.batteryLevel * 100))%\(snapshot.lowPowerMode ? " · Low Power" : "")")
            }
            if let load = store.modelLoadDuration {
                statRow("Model load", String(format: "%.1f s", load))
            }
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(W95.ui(12)).foregroundStyle(W95.text)
            Spacer()
            Text(value).font(W95.mono(11, bold: true)).foregroundStyle(W95.navy)
        }
    }

    private var thermalText: String {
        switch snapshot?.thermalState {
        case .nominal, nil: return "Thermal: OK"
        case .fair: return "Thermal: warm"
        case .serious: return "Thermal: throttling!"
        case .critical: return "Thermal: CRITICAL"
        @unknown default: return "Thermal: ?"
        }
    }

    private func megabytes(_ bytes: Int) -> String {
        String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }
}
