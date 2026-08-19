import Foundation
import Observation
import MLX
import MLXLMCommon
import MLXLLM
import MLXHuggingFace
import HuggingFace  // HubClient, used inside the macro expansion
import Tokenizers   // AutoTokenizer, used inside the macro expansion

/// Downloads, loads, and unloads on-device models from the catalog. Enforces the
/// single-resident-model rule: on an 8 GB iPhone only one model may be in memory
/// at a time.
@Observable @MainActor
final class ModelManager {
    /// Single shared instance: tools (e.g. the driver's summarize_app) must be able to
    /// unload the text model to honor the single-resident-model rule.
    static let shared = ModelManager()

    enum State {
        case idle
        case downloading(progress: Double)
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var container: ModelContainer?

    /// The selected catalog model. Stored by HF repo id; unknown ids (e.g. a model
    /// removed from the catalog) fall back to the default.
    var choice: CatalogModel {
        get {
            let stored = UserDefaults.standard.string(forKey: "modelChoice") ?? ""
            return ModelCatalog.model(id: stored) ?? ModelCatalog.defaultModel
        }
        set { UserDefaults.standard.set(newValue.id, forKey: "modelChoice") }
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
        let loadStart = Date()
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
                configuration: ModelConfiguration(id: choice.id),
                progressHandler: handler
            )
            state = .loading
            self.container = container
            excludeWeightsFromBackup()
            state = .ready
            MetricsStore.shared.recordModelLoad(
                id: choice.id,
                duration: Date().timeIntervalSince(loadStart)
            )
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func reportDownloadProgress(_ fraction: Double) {
        state = .downloading(progress: fraction)
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

    /// Ejects the current model (if any) and makes `model` current. Loads it if the
    /// weights are on disk; otherwise goes idle so ModelDownloadView offers the download.
    func switchTo(_ model: CatalogModel) async {
        if model == choice, case .ready = state { return }
        unload()
        choice = model
        if isDownloaded(model) {
            await load()
        }
    }

    /// Deletes one model's weights. If it's the loaded one, ejects it first.
    func delete(_ model: CatalogModel) {
        if model == choice, container != nil {
            unload()
        }
        if let dir = repoDirectory(for: model) {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    func isDownloaded(_ model: CatalogModel) -> Bool {
        guard let dir = repoDirectory(for: model) else { return false }
        return FileManager.default.fileExists(atPath: dir.path)
    }

    /// Actual bytes on disk, so the library can show real sizes next to the estimates.
    func sizeOnDisk(_ model: CatalogModel) -> Int64 {
        guard let dir = repoDirectory(for: model),
              let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    var totalBytesOnDisk: Int64 {
        ModelCatalog.all.filter(isDownloaded).map(sizeOnDisk).reduce(0, +)
    }

    private func repoDirectory(for model: CatalogModel) -> URL? {
        Self.hubCacheDirectory?.appendingPathComponent("models/\(model.id)")
    }

    /// swift-transformers' default HubApi download base. Deliberately in Documents so the
    /// weights are visible (and deletable) in the Files app.
    private static var hubCacheDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("huggingface")
    }
}
