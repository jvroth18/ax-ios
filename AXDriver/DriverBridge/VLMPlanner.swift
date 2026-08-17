#if AX_DRIVER
import Foundation
import UIKit
import MLX
import MLXLMCommon
import MLXVLM
import AXCore

/// Decides the next UI action from a screenshot + goal using an on-device vision model.
/// EXPERIMENTAL: 2B-class VLM grounding is hit-or-miss; every step is shown to the user.
struct VLMPlanner {

    static let modelID = "mlx-community/Qwen2-VL-2B-Instruct-4bit"  // ~1.3 GB, 8GB-safe

    enum Action: Equatable {
        case tap(xFraction: Double, yFraction: Double, why: String)
        case type(text: String)
        case launch(bundleID: String)
        case home
        case done(summary: String)
        case stuck(reason: String)
    }

    let container: ModelContainer

    /// Loads the VLM. Caller must unload the text model first (single-resident-model rule).
    static func load() async throws -> VLMPlanner {
        let container = try await VLMModelFactory.shared.loadContainer(
            configuration: ModelConfiguration(id: modelID)
        )
        return VLMPlanner(container: container)
    }

    func nextAction(goal: String, stepsSoFar: [String], screenshot: UIImage) async throws -> Action {
        let prompt = """
        You control an iPhone by looking at screenshots. Goal: \(goal)
        Steps already taken: \(stepsSoFar.isEmpty ? "none" : stepsSoFar.joined(separator: "; "))

        Reply with EXACTLY ONE JSON object, no other text:
        {"action": "tap", "x": 0.0-1.0, "y": 0.0-1.0, "why": "..."}
        {"action": "type", "text": "..."}
        {"action": "launch", "bundle_id": "..."}
        {"action": "home"}
        {"action": "done", "summary": "..."}
        {"action": "stuck", "reason": "..."}
        Coordinates are fractions of screen width/height.
        """

        let output = try await container.perform { context in
            let input = try await context.processor.prepare(
                input: UserInput(chat: [.user(prompt, images: [.ciImage(CIImage(image: screenshot)!)])])
            )
            var text = ""
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(maxTokens: 128, temperature: 0.1),
                context: context
            )
            for await generation in stream {
                if case .chunk(let chunk) = generation { text += chunk }
            }
            return text
        }
        return try Self.parse(output)
    }

    static func parse(_ output: String) throws -> Action {
        // Take the first {...} in the output; small VLMs often add stray prose.
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}") else {
            return .stuck(reason: "Model produced no JSON: \(output.prefix(80))")
        }
        let json = String(output[start...end])
        let decoded = try JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8))
        switch decoded["action"]?.stringValue {
        case "tap":
            guard let x = decoded["x"]?.numberValue, let y = decoded["y"]?.numberValue else {
                return .stuck(reason: "tap without coordinates")
            }
            return .tap(xFraction: x, yFraction: y, why: decoded["why"]?.stringValue ?? "")
        case "type":
            return .type(text: decoded["text"]?.stringValue ?? "")
        case "launch":
            return .launch(bundleID: decoded["bundle_id"]?.stringValue ?? "")
        case "home":
            return .home
        case "done":
            return .done(summary: decoded["summary"]?.stringValue ?? "Done.")
        default:
            return .stuck(reason: decoded["reason"]?.stringValue ?? "Unrecognized action")
        }
    }
}
#endif
