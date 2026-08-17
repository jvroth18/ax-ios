import Foundation
import SwiftData
import AXCore

@Model
final class Interaction {
    var date: Date
    var transcript: String
    var reply: String
    /// Human-readable log of the tool calls made, e.g. "create_reminder(title: Call mom)".
    var toolSummary: String

    init(date: Date, transcript: String, reply: String, toolSummary: String) {
        self.date = date
        self.transcript = transcript
        self.reply = reply
        self.toolSummary = toolSummary
    }
}

enum HistoryStore {
    @MainActor
    static func record(transcript: String, turn: AgentLoop.Turn) {
        guard let container = try? ModelContainer(for: Interaction.self) else { return }
        let summary = turn.toolCalls.map { call in
            let args = call.arguments.map { "\($0.key): \($0.value.stringValue ?? "…")" }
                .joined(separator: ", ")
            return "\(call.name)(\(args))"
        }.joined(separator: "; ")
        let interaction = Interaction(
            date: Date(), transcript: transcript, reply: turn.reply, toolSummary: summary
        )
        container.mainContext.insert(interaction)
        try? container.mainContext.save()
    }
}
