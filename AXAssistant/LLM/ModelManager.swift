import Foundation
import Observation
import MLX
import MLXLMCommon
import MLXLLM
import MLXHuggingFace
import HuggingFace  // HubClient, used inside the macro expansion
import Tokenizers   // AutoTokenizer, used inside the macro expansion

/// Downloads, loads, and unloads the on-device model. Enforces the single-resident-model
/// rule: on an 8 GB iPhone only one large model may be in memory at a time.
@Observable @MainActor
final class ModelManager {
    /// Single shared instance: tools (e.g. the driver's summarize_app) must be able to
    /// unload the text model to honor the single-resident-model rule.
    static let shared = ModelManager()

    enum ModelChoice: String, CaseIterable, Identifiable {
        case qwen3_1_7b = "mlx-community/Qwen3-1.7B-4bit"
        case qwen25_1_5b = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .qwen3_1_7b: return "Qwen3 1.7B (recommended)"
            case .qwen25_1_5b: return "Qwen2.5 1.5B (smaller)"
            }
        }
        var approximateSize: String {
            switch self {
            case .qwen3_1_7b: return "1.1 GB"
            case .qwen25_1_5b: return "0.9 GB"
            }
        }
    }

    enum State {
        case idle
        case downloading(progress: Double)
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var container: ModelContainer?

    var choice: ModelChoice {
        get { ModelChoice(rawValue: UserDefaults.standard.string(forKey: "modelChoice") ?? "") ?? .qwen3_1_7b }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "modelChoice") }
    }

    /// Loads silently at launch if weights are already on disk; otherwise stays idle so
    /// ModelDownloadView can show the explicit download step (with size + Wi-Fi warning).
    func loadIfDownloaded() async {
        guard container == nil, isDownloaded(choice) else { return }
        await load()
    }

    func downloadAndLoad() async {
        await load()
    }

    private func load() async {
        state = .downloading(progress: 0)
        do {
            // Keep Metal's buffer cache small: latency cost is minor, jetsam risk is real.
            MLX.GPU.set(cacheLimit: 512 * 1024 * 1024)

            // The macro supplies the Hugging Face downloader + tokenizer loader (3.x API).
            // The handler is a typed local: the expression checker can't infer closure
            // types through the macro expansion.
            let handler: @Sendable (Progress) -> Void = { [weak self] progress in
                let fraction = progress.fractionCompleted
                Task { @MainActor in self?.reportDownloadProgress(fraction) }
            }
            let container = try await #huggingFaceLoadModelContainer(
                configuration: configuration(for: choice),
                progressHandler: handler
            )
            state = .loading
            self.container = container
            excludeWeightsFromBackup()
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func reportDownloadProgress(_ fraction: Double) {
        state = .downloading(progress: fraction)
    }

    private func configuration(for choice: ModelChoice) -> ModelConfiguration {
        switch choice {
        case .qwen3_1_7b: return LLMRegistry.qwen3_1_7b_4bit
        case .qwen25_1_5b: return ModelConfiguration(id: choice.rawValue)
        }
    }

    /// Weights are re-downloadable; don't let them bloat the user's iCloud backup.
    private func excludeWeightsFromBackup() {
        guard var dir = Self.hubCacheDirectory else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
    }

    /// Called on memory warnings and before AXDriver loads its vision model.
    func unload() {
        container = nil
        MLX.GPU.clearCache()
        state = .idle
    }

    func deleteDownloadedModel() {
        unload()
        // Weights live in the Hub cache inside Application Support; removing the
        // directory forces a fresh download next time.
        if let dir = Self.hubCacheDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    private func isDownloaded(_ choice: ModelChoice) -> Bool {
        guard let dir = Self.hubCacheDirectory else { return false }
        let repoDir = dir.appendingPathComponent("models/\(choice.rawValue)")
        return FileManager.default.fileExists(atPath: repoDir.path)
    }

    /// swift-transformers' default HubApi download base. Deliberately in Documents so the
    /// ~1 GB of weights is visible (and deletable) in the Files app.
    private static var hubCacheDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("huggingface")
    }
}
