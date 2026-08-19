import Foundation
import Observation
import UIKit
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

    /// Weights root: Documents so iOS never purges the ~1 GB models (Caches, the
    /// HubClient default, is purgeable) and they're visible in the Files app.
    /// Layout is HubCache's: <root>/models--<org>--<name>/{blobs,refs,snapshots}.
    /// Shared with KokoroSpeaker so voice weights get the same treatment.
    static let hubRoot: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask).first!
        .appendingPathComponent("huggingface/hub")

    private static let hubClient = HubClient(cache: HubCache(cacheDirectory: hubRoot))

    private init() {
        Self.migrateFromCachesIfNeeded()
    }

    /// Earlier builds let HubClient default to Caches; move anything there into
    /// Documents so users don't re-download (or silently lose) models.
    private static func migrateFromCachesIfNeeded() {
        let oldRoot = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface/hub")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: oldRoot.path) else { return }
        try? FileManager.default.createDirectory(at: hubRoot, withIntermediateDirectories: true)
        for entry in entries where entry.hasPrefix("models--") {
            let destination = hubRoot.appendingPathComponent(entry)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            try? FileManager.default.moveItem(at: oldRoot.appendingPathComponent(entry), to: destination)
        }
    }

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
        // Multi-GB downloads die if the screen locks; keep it awake until done.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
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
            // Expanded form of #huggingFaceLoadModelContainer so we can pass our
            // Documents-rooted HubClient instead of the default (Caches) one.
            let container = try await loadModelContainer(
                from: #hubDownloader(Self.hubClient),
                using: #huggingFaceTokenizerLoader(),
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
        var dir = Self.hubRoot.deletingLastPathComponent()  // Documents/huggingface
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
        try? FileManager.default.removeItem(at: repoDirectory(for: model))
    }

    func isDownloaded(_ model: CatalogModel) -> Bool {
        // An interrupted download leaves a snapshot with metadata but missing (or
        // dangling-symlink) weight shards — seen in the wild on Jordan's phone.
        // Only count a model as installed when a snapshot has ≥1 .safetensors entry
        // and every one of them resolves (fileExists follows symlinks).
        let snapshots = repoDirectory(for: model).appendingPathComponent("snapshots")
        guard let snapshotIDs = try? FileManager.default.contentsOfDirectory(atPath: snapshots.path)
        else { return false }
        for snapshotID in snapshotIDs {
            let dir = snapshots.appendingPathComponent(snapshotID)
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            let tensors = files.filter { $0.hasSuffix(".safetensors") }
            if !tensors.isEmpty,
               tensors.allSatisfy({ FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }) {
                return true
            }
        }
        return false
    }

    /// Actual bytes on disk, so the library can show real sizes next to the estimates.
    func sizeOnDisk(_ model: CatalogModel) -> Int64 {
        let dir = repoDirectory(for: model)
        guard let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])
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

    private func repoDirectory(for model: CatalogModel) -> URL {
        Self.hubRoot.appendingPathComponent("models--" + model.id.replacingOccurrences(of: "/", with: "--"))
    }
}
