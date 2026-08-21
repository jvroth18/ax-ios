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
                    description: "One of: \(OpenAppTool.knownApps.keys.sorted().joined(separator: ", "))",
                    enumValues: OpenAppTool.knownApps.keys.sorted()
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

private enum TorchController {
    static func set(_ isOn: Bool) throws {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            throw AXToolError.notAvailable("No flashlight on this device.")
        }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if isOn {
            try device.setTorchModeOn(level: 1.0)
        } else {
            device.torchMode = .off
        }
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
        guard ["on", "off"].contains(state) else {
            throw AXToolError.badArgument("state", "must be on or off")
        }
        try TorchController.set(state == "on")
        return .ok("Flashlight \(state).")
    }
}

/// Converts source text to International Morse in deterministic code, then drives the
/// physical torch. The model supplies language, never timing or dot/dash strings: small
/// models are good at choosing this tool, while code is better at counting exact units.
struct MorseFlashlightTool: AXTool {
    let spec = ToolSpec(
        name: "signal_morse_code",
        description: "Flash text as International Morse code using the iPhone flashlight. Pass the original text; this tool performs the encoding and timing.",
        parameters: JSONSchema(
            type: .object,
            properties: [
                "text": JSONSchema(
                    type: .string,
                    description: "The original letters, numbers, words, or punctuation to signal; do not translate it to dots and dashes"
                ),
            ],
            required: ["text"]
        ),
        risk: .safe
    )

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let text = call.string("text") else { throw AXToolError.missingArgument("text") }
        let transmission: MorseCode.Transmission
        do {
            transmission = try MorseCode.encode(text)
        } catch let error as MorseCode.EncodingError {
            throw AXToolError.badArgument("text", error.description)
        }

        // The torch must finish off even when the user taps Stop, the app backgrounds,
        // a sleep is cancelled, or AVFoundation fails midway through the signal.
        defer { try? TorchController.set(false) }
        for pulse in transmission.pulses {
            try Task.checkCancellation()
            try TorchController.set(pulse.isOn)
            let nanoseconds = UInt64(
                Double(pulse.units) * MorseCode.unitSeconds * 1_000_000_000
            )
            try await Task.sleep(nanoseconds: nanoseconds)
        }

        return .ok(
            "Signaled \"\(transmission.normalizedText)\" in Morse code "
                + "(\(transmission.notation))."
        )
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
