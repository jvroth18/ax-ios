import Foundation
import SwiftUI
import AlarmKit
import AXCore

nonisolated struct AXTimerMetadata: AlarmMetadata {}

/// Countdown timers via AlarmKit (iOS 26). AlarmKit alerts cut through silent mode and
/// Focus, so the system requires explicit user authorization on first use.
struct TimerTool: AXTool {
    let spec = ToolSpec(
        name: "set_timer",
        description: "Start a countdown timer that alerts when it ends.",
        parameters: JSONSchema(
            type: .object,
            properties: [
                "minutes": JSONSchema(type: .number, description: "Duration in minutes"),
                "label": JSONSchema(type: .string, description: "What the timer is for, optional"),
            ],
            required: ["minutes"]
        ),
        risk: .safe
    )

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let minutes = call.number("minutes"), minutes > 0 else {
            throw AXToolError.badArgument("minutes", "must be a positive number")
        }

        let manager = AlarmManager.shared
        let state = try await manager.requestAuthorization()
        guard state == .authorized else {
            throw AXToolError.permissionDenied("Timers (AlarmKit)")
        }

        let label = call.string("label") ?? "Timer"
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: "\(label) done"),
            stopButton: AlarmButton(text: "Done", textColor: .white, systemImageName: "checkmark")
        )
        let attributes = AlarmAttributes<AXTimerMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: Color.orange
        )
        _ = try await manager.schedule(
            id: UUID(),
            configuration: .timer(duration: minutes * 60, attributes: attributes)
        )

        let pretty = minutes == minutes.rounded()
            ? "\(Int(minutes)) minute\(minutes == 1 ? "" : "s")"
            : String(format: "%.1f minutes", minutes)
        return .ok("Timer set for \(pretty).")
    }
}
