import Foundation
import EventKit
import AXCore

struct CalendarCreateTool: AXTool {
    let spec = ToolSpec(
        name: "create_calendar_event",
        description: "Create a calendar event.",
        parameters: JSONSchema(
            type: .object,
            properties: [
                "title": JSONSchema(type: .string),
                "start": JSONSchema(
                    type: .string,
                    description: "Start in the user's local time, ISO 8601 without a timezone, e.g. 2026-08-17T17:00:00"
                ),
                "duration_minutes": JSONSchema(type: .integer, description: "Defaults to 60"),
                "location": JSONSchema(type: .string),
            ],
            required: ["title", "start"]
        ),
        risk: .confirm
    )

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let title = call.string("title") else { throw AXToolError.missingArgument("title") }
        guard let start = call.string("start")?.iso8601Date else {
            throw AXToolError.badArgument("start", "not ISO 8601")
        }

        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else {
            throw AXToolError.permissionDenied("Calendar")
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval((call.int("duration_minutes") ?? 60) * 60))
        event.location = call.string("location")
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
        return .ok("Event \"\(title)\" created for \(start.formatted()).")
    }
}

struct CalendarReadTool: AXTool {
    let isReadOnly = true

    let spec = ToolSpec(
        name: "read_next_events",
        description: "Read the user's upcoming calendar events.",
        parameters: JSONSchema(
            type: .object,
            properties: [
                "hours_ahead": JSONSchema(type: .integer, description: "Look-ahead window, default 24"),
            ]
        ),
        risk: .safe
    )

    func run(_ call: ToolCall) async throws -> ToolResult {
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else {
            throw AXToolError.permissionDenied("Calendar")
        }
        let hours = call.int("hours_ahead") ?? 24
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now,
            end: now.addingTimeInterval(TimeInterval(hours * 3600)),
            calendars: nil
        )
        let events = store.events(matching: predicate).prefix(10)
        guard !events.isEmpty else { return .ok("No events in the next \(hours) hours.") }
        let lines = events.map { "\($0.startDate.formatted(date: .abbreviated, time: .shortened)): \($0.title ?? "Untitled")" }
        return .ok(lines.joined(separator: "\n"))
    }
}
