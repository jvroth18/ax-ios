#if AX_DRIVER
import Foundation
import UIKit
import MLX
import MLXLMCommon
import MLXVLM
import MLXHuggingFace
import HuggingFace  // HubClient, used inside the macro expansion
import Tokenizers   // AutoTokenizer, used inside the macro expansion
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
    /// The macro's factory registry routes VLM configurations to the VLM factory.
    static func load() async throws -> VLMPlanner {
        let container = try await #huggingFaceLoadModelContainer(
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

        guard let ciImage = CIImage(image: screenshot) else {
            return .stuck(reason: "Could not read the screenshot")
        }
        // ChatSession wraps prepare+generate; a fresh session per step is correct because
        // the prompt already carries the step log.
        let session = ChatSession(
            container,
            generateParameters: GenerateParameters(maxTokens: 128, temperature: 0.1)
        )
        let output = try await session.respond(to: prompt, image: .ciImage(ciImage))
        return try Self.parse(output)
    }

    /// Plain screenshot comprehension (no action planning) — the Path-2 read workflows.
    func describe(prompt: String, screenshot: UIImage) async throws -> String {
        guard let ciImage = CIImage(image: screenshot) else { return "" }
        let session = ChatSession(
            container,
            generateParameters: GenerateParameters(maxTokens: 256, temperature: 0.2)
        )
        return try await session.respond(to: prompt, image: .ciImage(ciImage))
    }

    static func parse(_ output: String) throws -> Action {
        // Take the first {...} in the output; small VLMs often add stray prose.
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}") else {
            return .stuck(reason: "Model produced no JSON: \(output.prefix(80))")
        }
        let json = String(output[start...end])
        // Keep these operations separate. In AX_DRIVER device builds, Swift 6.2's
        // type checker can fail to produce a diagnostic for the nested generic call.
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let decoded: [String: JSONValue] = try decoder.decode(
            [String: JSONValue].self,
            from: data
        )
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
