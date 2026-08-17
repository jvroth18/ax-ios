import Foundation
import UIKit
import AVFoundation
import MediaPlayer
import AXCore

struct OpenAppTool: AXTool {
    /// Curated URL-scheme table. Contributions welcome — keep it to widely-installed apps.
    static let knownApps: [String: String] = [
        "settings": "App-Prefs:",
        "camera": "camera://",
        "photos": "photos-redirect://",
        "maps": "maps://",
        "music": "music://",
        "mail": "message://",
        "safari": "x-web-search://",
        "notes": "mobilenotes://",
        "reminders": "x-apple-reminderkit://",
        "calendar": "calshow://",
        "shortcuts": "shortcuts://",
        "messages": "messages://",
        "phone": "tel://",
        "spotify": "spotify://",
        "youtube": "youtube://",
        "whatsapp": "whatsapp://",
    ]

    let spec = ToolSpec(
        name: "open_app",
        description: "Open an app by name.",
        parameters: JSONSchema(
            type: .object,
            properties: [
                "app": JSONSchema(
                    type: .string,
                    description: "One of: \(knownApps.keys.sorted().joined(separator: ", "))",
                    enumValues: knownApps.keys.sorted()
                ),
            ],
            required: ["app"]
        ),
        risk: .safe
    )

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let app = call.string("app")?.lowercased() else { throw AXToolError.missingArgument("app") }
        guard let scheme = Self.knownApps[app], let url = URL(string: scheme) else {
            return .failure("I don't know how to open \(app).")
        }
        await MainActor.run { UIApplication.shared.open(url) }
        return .ok("Opening \(app).")
    }
}

struct OpenURLTool: AXTool {
    let spec = ToolSpec(
        name: "open_url",
        description: "Open a web page in the browser.",
        parameters: JSONSchema(
            type: .object,
            properties: ["url": JSONSchema(type: .string, description: "https URL")],
            required: ["url"]
        ),
        risk: .safe
    )

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let raw = call.string("url"), let url = URL(string: raw),
              url.scheme == "https" || url.scheme == "http" else {
            throw AXToolError.badArgument("url", "must be an http(s) URL")
        }
        await MainActor.run { UIApplication.shared.open(url) }
        return .ok("Opening \(url.host ?? raw).")
    }
}

struct FlashlightTool: AXTool {
    let spec = ToolSpec(
        name: "toggle_flashlight",
        description: "Turn the flashlight on or off.",
        parameters: JSONSchema(
            type: .object,
            properties: ["state": JSONSchema(type: .string, enumValues: ["on", "off"])],
            required: ["state"]
        ),
        risk: .safe
    )

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let state = call.string("state") else { throw AXToolError.missingArgument("state") }
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            throw AXToolError.notAvailable("No flashlight on this device.")
        }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if state == "on" {
            try device.setTorchModeOn(level: 1.0)
        } else {
            device.torchMode = .off
        }
        return .ok("Flashlight \(state).")
    }
}

struct MusicTool: AXTool {
    let spec = ToolSpec(
        name: "play_music",
        description: "Play, pause, or skip in Apple Music.",
        parameters: JSONSchema(
            type: .object,
            properties: [
                "action": JSONSchema(type: .string, enumValues: ["play", "pause", "next", "previous"]),
            ],
            required: ["action"]
        ),
        risk: .safe
    )

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let action = call.string("action") else { throw AXToolError.missingArgument("action") }
        let player = MPMusicPlayerController.systemMusicPlayer
        await MainActor.run {
            switch action {
            case "play": player.play()
            case "pause": player.pause()
            case "next": player.skipToNextItem()
            case "previous": player.skipToPreviousItem()
            default: break
            }
        }
        return .ok("Music: \(action).")
    }
}
