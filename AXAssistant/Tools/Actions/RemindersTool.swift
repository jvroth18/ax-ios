import Foundation
import EventKit
import AXCore

struct RemindersTool: AXTool {
    let spec = ToolSpec(
        name: "create_reminder",
        description: "Create a reminder in the Reminders app, optionally with a due date.",
        parameters: JSONSchema(
            type: .object,
            properties: [
                "title": JSONSchema(type: .string, description: "What to remind the user about"),
                "due": JSONSchema(type: .string, description: "Due date-time, ISO 8601, optional"),
            ],
            required: ["title"]
        ),
        risk: .safe
    )

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let title = call.string("title") else { throw AXToolError.missingArgument("title") }

        let store = EKEventStore()
        guard try await store.requestFullAccessToReminders() else {
            throw AXToolError.permissionDenied("Reminders")
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders()
        if let dueString = call.string("due") {
            guard let date = ISO8601DateFormatter.lenient.date(from: dueString) else {
                throw AXToolError.badArgument("due", "not ISO 8601")
            }
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date
            )
            reminder.addAlarm(EKAlarm(absoluteDate: date))
        }
        try store.save(reminder, commit: true)
        return .ok("Reminder \"\(title)\" created\(call.string("due").map { " for \($0)" } ?? "").")
    }
}

extension ISO8601DateFormatter {
    /// Accepts both "2026-08-17T17:00:00" (no zone — treated as local) and full ISO forms.
    /// ISO8601DateFormatter is documented thread-safe; options are never mutated after init.
    nonisolated(unsafe) static let lenient: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }()
}

extension String {
    /// Models often omit the timezone; normalize before parsing.
    var iso8601Date: Date? {
        if let date = ISO8601DateFormatter.lenient.date(from: self) { return date }
        return ISO8601DateFormatter.lenient.date(from: self + "Z").map { date in
            // Re-interpret the "Z" we appended as local time
            date.addingTimeInterval(-TimeInterval(TimeZone.current.secondsFromGMT(for: date)))
        }
    }
}
