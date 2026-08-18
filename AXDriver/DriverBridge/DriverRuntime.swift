#if AX_DRIVER
import Foundation

/// Owns the vision model's lifecycle for driver features. Loading the VLM unloads the
/// text model first (single-resident-model rule on 8 GB devices); the text model
/// lazily reloads on the next normal request.
@MainActor
final class DriverRuntime {
    static let shared = DriverRuntime()
    private(set) var planner: VLMPlanner?

    private init() {}

    func vlm() async throws -> VLMPlanner {
        if let planner { return planner }
        ModelManager.shared.unload()
        let loaded = try await VLMPlanner.load()
        planner = loaded
        return loaded
    }

    func unload() {
        planner = nil
    }
}
#endif
