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
                "due": JSONSchema(
                    type: .string,
                    description: "Due date-time in the user's local time, ISO 8601 without a timezone, e.g. 2026-08-17T17:00:00. Optional."
                ),
            ],
            required: ["title"]
        ),
        risk: .safe
    )

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let title = call.string("title") else { throw AXToolError.missingArgument("title") }

        // Parse before asking for permission: a bad argument shouldn't cost the user a
        // permission prompt, and DateArgument accepts every shape the prompt teaches.
        var due: DateArgument.Parsed?
        if let dueString = call.string("due") {
            guard let parsed = DateArgument.parse(dueString) else {
                throw AXToolError.badArgument("due", "not ISO 8601")
            }
            due = parsed
        }

        let store = EKEventStore()
        guard try await store.requestFullAccessToReminders() else {
            throw AXToolError.permissionDenied("Reminders")
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders()
        if let due {
            // A date with no time ("remind me on Friday") becomes an untimed reminder —
            // date components only, no alarm — rather than one that fires at midnight.
            var fields: Set<Calendar.Component> = [.year, .month, .day]
            if due.hasTime { fields.formUnion([.hour, .minute]) }
            reminder.dueDateComponents = Calendar.current.dateComponents(fields, from: due.date)
            if due.hasTime { reminder.addAlarm(EKAlarm(absoluteDate: due.date)) }
        }
        try store.save(reminder, commit: true)
        let when = due.map { " for \($0.hasTime ? $0.date.formatted() : $0.date.formatted(date: .abbreviated, time: .omitted))" } ?? ""
        return .ok("Reminder \"\(title)\" created\(when).")
    }
}

extension ISO8601DateFormatter {
    /// STRICT, despite the name: `.withInternetDateTime` REQUIRES a timezone designator,
    /// so "2026-08-17T17:00:00" — the very form the system prompt teaches the model to
    /// emit — returns nil here, as do "…T17:00" and "2026-08-17". Setting `timeZone` does
    /// not change that; it only affects formatting. This used to be create_reminder's
    /// parser, which is why the tool rejected its own documented argument shape.
    ///
    /// Nothing calls this any more — tools must use `DateArgument.parse` (AXCore). It is
    /// kept, unused, only as the named record of a trap that cost a shipped feature: if
    /// you find yourself reaching for a formatter here, this is the one you'd get.
    /// ISO8601DateFormatter is documented thread-safe; options are never mutated after init.
    nonisolated(unsafe) static let lenient: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }()
}
