import Foundation
import Observation
import UIKit
import MLX

/// One completed model generation, built from MLX's `GenerateCompletionInfo` plus
/// timings measured around the stream.
struct GenerationRecord: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let modelID: String
    let promptTokens: Int
    let generationTokens: Int
    let promptTime: TimeInterval
    let generateTime: TimeInterval
    /// Wall-clock seconds from stream start to the first streamed chunk — the latency
    /// the user actually feels; includes prompt prefill.
    let timeToFirstToken: TimeInterval
    /// Process physical footprint (bytes) sampled right after the stream finished.
    let footprintBytes: Int
    /// MLX GPU peak memory (bytes) at completion.
    let gpuPeakBytes: Int

    var tokensPerSecond: Double { generateTime > 0 ? Double(generationTokens) / generateTime : 0 }
    var promptTokensPerSecond: Double { promptTime > 0 ? Double(promptTokens) / promptTime : 0 }
}

/// Point-in-time device + process stats for the dashboard's live section.
struct SystemSnapshot {
    let footprintBytes: Int
    let availableBytes: Int
    let gpuActiveBytes: Int
    let gpuCacheBytes: Int
    let gpuPeakBytes: Int
    let gpuCacheLimitBytes: Int
    let thermalState: ProcessInfo.ThermalState
    let batteryLevel: Float
    let lowPowerMode: Bool
}

/// Collects model-performance records and samples system stats. Fed by LLMGenerator
/// (per generation) and ModelManager (load timing); read by MetricsView.
@Observable @MainActor
final class MetricsStore {
    static let shared = MetricsStore()

    private(set) var generations: [GenerationRecord] = []
    private(set) var peakFootprintBytes: Int = 0
    /// Rolling traces (MB) fed by each systemSnapshot() call — the strip-chart paper.
    private(set) var footprintTrace: [Double] = []
    private(set) var gpuActiveTrace: [Double] = []
    private let maxTraceSamples = 240
    private(set) var loadedModelID: String?
    /// First run includes the weight download; subsequent launches are load-only.
    private(set) var modelLoadDuration: TimeInterval?

    private let maxRecords = 100

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    func record(_ record: GenerationRecord) {
        generations.append(record)
        if generations.count > maxRecords {
            generations.removeFirst(generations.count - maxRecords)
        }
        peakFootprintBytes = max(peakFootprintBytes, record.footprintBytes)
    }

    func recordModelLoad(id: String, duration: TimeInterval) {
        loadedModelID = id
        modelLoadDuration = duration
    }

    var averageTokensPerSecond: Double {
        guard !generations.isEmpty else { return 0 }
        return generations.map(\.tokensPerSecond).reduce(0, +) / Double(generations.count)
    }

    var averageTimeToFirstToken: Double {
        guard !generations.isEmpty else { return 0 }
        return generations.map(\.timeToFirstToken).reduce(0, +) / Double(generations.count)
    }

    func systemSnapshot() -> SystemSnapshot {
        let footprint = Self.processFootprintBytes()
        peakFootprintBytes = max(peakFootprintBytes, footprint)
        footprintTrace.append(Double(footprint) / 1_048_576)
        gpuActiveTrace.append(Double(MLX.GPU.activeMemory) / 1_048_576)
        if footprintTrace.count > maxTraceSamples {
            footprintTrace.removeFirst(footprintTrace.count - maxTraceSamples)
            gpuActiveTrace.removeFirst(gpuActiveTrace.count - maxTraceSamples)
        }
        return SystemSnapshot(
            footprintBytes: footprint,
            availableBytes: Int(os_proc_available_memory()),
            gpuActiveBytes: MLX.GPU.activeMemory,
            gpuCacheBytes: MLX.GPU.cacheMemory,
            gpuPeakBytes: MLX.GPU.peakMemory,
            gpuCacheLimitBytes: MLX.GPU.cacheLimit,
            thermalState: ProcessInfo.processInfo.thermalState,
            batteryLevel: UIDevice.current.batteryLevel,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    /// The M1 exit-criteria numbers, formatted for pasting into docs/MEMORY.md.
    var m1Report: String {
        let model = loadedModelID ?? "unknown"
        let peakMB = Double(max(peakFootprintBytes, Self.processFootprintBytes())) / 1_048_576
        let gpuPeakMB = Double(MLX.GPU.peakMemory) / 1_048_576
        let load = modelLoadDuration.map { String(format: "%.1fs", $0) } ?? "n/a"
        return """
        ## M1 measurements — \(Date().formatted(date: .abbreviated, time: .shortened))
        - Model: \(model) (load: \(load))
        - Generations recorded: \(generations.count)
        - Generation: avg \(String(format: "%.1f", averageTokensPerSecond)) tok/s, \
        avg TTFT \(String(format: "%.2f", averageTimeToFirstToken))s
        - Peak process footprint: \(String(format: "%.0f", peakMB)) MB
        - Peak MLX GPU memory: \(String(format: "%.0f", gpuPeakMB)) MB
        """
    }

    /// `phys_footprint` — the same number Xcode's memory gauge and jetsam use.
    nonisolated static func processFootprintBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint)
    }
}
