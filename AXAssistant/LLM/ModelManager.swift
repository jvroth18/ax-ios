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
    nonisolated static let hubRoot: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask).first!
        .appendingPathComponent("huggingface/hub")

    private static let hubClient: HubClient = {
        // A stalled transfer must fail loudly, not hang at 0% forever (observed
        // on-device: a weights download dead for 2h with no error). 60s without
        // bytes kills the request; resume picks up from completed blobs.
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.waitsForConnectivity = true
        return HubClient(
            session: URLSession(configuration: config),
            cache: HubCache(cacheDirectory: hubRoot)
        )
    }()

    /// The in-flight download/load, so Cancel can actually cancel it.
    private var loadTask: Task<Void, Never>?

    /// Library downloads that don't switch the active model: id → fraction.
    private(set) var downloadProgress: [String: Double] = [:]
    /// Why a library download failed, id → message. Never fail silently.
    private(set) var downloadErrors: [String: String] = [:]
    private var downloadTasks: [String: Task<Void, Never>] = [:]
    private var storagePrepared = false

    /// Fetch a model's weights without unloading or switching the current model,
    /// so the Library can stock up while you keep chatting.
    func download(_ model: CatalogModel) {
        guard downloadTasks[model.id] == nil, !isDownloaded(model) else { return }
        guard let repoID = Repo.ID(rawValue: model.id) else { return }
        downloadErrors[model.id] = nil
        downloadProgress[model.id] = 0
        UIApplication.shared.isIdleTimerDisabled = true
        let task = Task {
            defer {
                downloadTasks[model.id] = nil
                downloadProgress[model.id] = nil
                if downloadTasks.isEmpty, loadTask == nil {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            }
            do {
                _ = try await Self.hubClient.downloadSnapshot(
                    of: repoID,
                    revision: "main",
                    matching: ["*.safetensors", "*.json", "*.jinja", "*.txt"],
                    progressHandler: { @MainActor progress in
                        ModelManager.shared.downloadProgress[model.id] = progress.fractionCompleted
                    }
                )
            } catch is CancellationError {
                // User cancelled; no message needed.
            } catch {
                downloadErrors[model.id] = error.localizedDescription
            }
        }
        downloadTasks[model.id] = task
    }

    func cancelDownload(of model: CatalogModel) {
        downloadTasks[model.id]?.cancel()
    }

    func isDownloading(_ model: CatalogModel) -> Bool {
        downloadTasks[model.id] != nil
    }

    private init() {
        // iOS jetsam kills the app under memory pressure (looks like a crash);
        // shed the model first so the OS reclaims ~2 GB instead.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { ModelManager.shared.handleMemoryWarning() }
        }
    }

    /// Legacy-cache migration used to run in `init`, blocking SwiftUI's first frame while
    /// it walked gigabytes of model files. Run it after launch on a background executor.
    /// Never delete repositories merely because a catalog version no longer lists them:
    /// downloaded models are user data and catalog changes must not disturb them.
    private func prepareStorageIfNeeded() async {
        guard !storagePrepared else { return }
        await Task.detached(priority: .utility) {
            Self.migrateFromCachesIfNeeded()
        }.value
        storagePrepared = true
    }

    private func handleMemoryWarning() {
        // Trim MLX's buffer cache only. Do NOT unload the model — that would drop
        // the user to the download screen mid-session; if memory is truly critical
        // the OS will jetsam us regardless, and unloading proactively is worse UX.
        MLX.GPU.clearCache()
    }

    /// Earlier builds let HubClient default to Caches; move anything there into
    /// Documents so users don't re-download (or silently lose) models.
    nonisolated private static func migrateFromCachesIfNeeded() {
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
    ///
    /// Re-entrant: on a cold start RootView's launch task and the held Action Button
    /// request both want the model up, and two concurrent loads would put two copies of
    /// multi-GB weights in memory on a device that can barely hold one. A second caller
    /// joins the load already running instead of starting its own.
    func loadIfDownloaded() async {
        await prepareStorageIfNeeded()
        if let loadTask { return await loadTask.value }
        guard container == nil, isDownloaded(choice) else { return }
        let task = Task { await load() }
        loadTask = task
        await task.value
        if loadTask == task { loadTask = nil }
    }

    /// Blocks until the model is resident, and reports whether it got there.
    ///
    /// The Action Button path needs this: the intent foregrounds the app and the scene
    /// turns active a second or more (1.7B; longer for a 4B) before the launch load
    /// finishes, so asking "is it ready?" once always answers no. Returns false — never
    /// hangs — when readiness isn't coming: no weights on disk, a failed load, or one the
    /// user cancelled. Honors cancellation of the calling task.
    func waitUntilReady() async -> Bool {
        while !Task.isCancelled {
            switch state {
            case .ready:
                return container != nil
            case .downloading, .loading:
                // In flight; ModelDownloadView is already showing the progress. Polling
                // beats withObservationTracking here — that fires once per change and
                // would need re-arming around every branch below.
                try? await Task.sleep(for: .milliseconds(100))
            case .failed:
                return false
            case .idle:
                // Either nothing has started yet (the launch task and the scene-phase
                // change race on a cold start) or there is nothing to start.
                guard isDownloaded(choice) else { return false }
                await loadIfDownloaded()
                if case .ready = state { return container != nil }
                return false  // ran and didn't stick: cancelled or failed
            }
        }
        return false
    }

    func downloadAndLoad() async {
        loadTask?.cancel()
        let task = Task { await load() }
        loadTask = task
        await task.value
        // Don't park a finished task in loadTask: cancelDownload() would then "cancel" a
        // corpse, and loadIfDownloaded() would join it instead of loading.
        if loadTask == task { loadTask = nil }
    }

    /// Abandon an in-flight download and return to the clean idle state.
    /// Completed blobs stay on disk; a later Get resumes from them.
    func cancelDownload() {
        loadTask?.cancel()
        loadTask = nil
        state = .idle
    }

    private func load() async {
        state = .downloading(progress: 0)
        // Multi-GB downloads die if the screen locks; keep it awake until done.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        let loadStart = Date()
        do {
            // Single-resident rule: free the voice model + Metal cache before pulling
            // a multi-GB LLM into memory, or the two together trip jetsam and the OS
            // kills the app mid-load (the "crash" on the 4B abliterated model).
            KokoroSpeaker.shared.freeModel()
            MLX.GPU.clearCache()
            // Keep Metal's buffer cache small: latency cost is minor, jetsam risk is
            // real (iOS kills at a ~3.4 GB per-process limit). 256 MB leaves more
            // headroom for a 2+ GB model's weights + KV cache.
            MLX.GPU.set(cacheLimit: 256 * 1024 * 1024)

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
        } catch is CancellationError {
            state = .idle
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
        // Abandon any in-flight load: unloading exists to free memory (AXDriver does it
        // before pulling in a vision model), and a load left running would re-populate
        // the container we just shed. Clearing it also stops loadIfDownloaded() from
        // joining a finished task and skipping the reload. Cancelling a finished task
        // is a no-op.
        loadTask?.cancel()
        loadTask = nil
        MLX.GPU.clearCache()
        state = .idle
    }

    /// Ejects the current model (if any) and makes `model` current. Loads it if the
    /// weights are on disk; otherwise goes idle so ModelDownloadView offers the download.
    func switchTo(_ model: CatalogModel) async {
        if model == choice, case .ready = state { return }
        unload()
        choice = model
        // Through the tracked path so a concurrent loadIfDownloaded() joins this load
        // rather than starting a second one.
        await loadIfDownloaded()
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

    /// Commit recorded by Hugging Face's cache for the installed `main` ref. This is
    /// read-only metadata used by eval reports; it never changes or cleans the model.
    func installedRevision(of model: CatalogModel) -> String? {
        let ref = repoDirectory(for: model).appendingPathComponent("refs/main")
        guard let raw = try? String(contentsOf: ref, encoding: .utf8) else { return nil }
        let revision = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return revision.isEmpty ? nil : revision
    }

    var totalBytesOnDisk: Int64 {
        ModelCatalog.all.filter(isDownloaded).map(sizeOnDisk).reduce(0, +)
    }

    private func repoDirectory(for model: CatalogModel) -> URL {
        Self.hubRoot.appendingPathComponent("models--" + model.id.replacingOccurrences(of: "/", with: "--"))
    }
}
