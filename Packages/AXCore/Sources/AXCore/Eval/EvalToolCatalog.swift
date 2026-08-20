import Foundation

/// A platform-free mirror of `ToolRegistry.standard.specs`.
///
/// WHY a mirror: `ToolCallParser.parse` needs the specs to validate a completion, and the
/// real tools live in the iOS app target (EventKit, AlarmKit, UIKit, MediaPlayer) which a
/// SwiftPM test on macOS cannot import. Without this, none of the scoring could run under
/// `swift test` or the CLI, which is precisely why the published eval numbers were never
/// reproducible.
///
/// The duplication is guarded, not ignored: `EvalToolCatalog.drift(from:)` diffs this
/// table against the live registry and the on-device harness surfaces the result in every
/// report, so a spec change here-or-there shows up as a warning instead of silently
/// scoring against a stale catalog.
public enum EvalToolCatalog {

    /// Kept in sync with `OpenAppTool.knownApps.keys`.
    public static let knownApps = [
        "calendar", "camera", "mail", "maps", "messages", "music", "notes", "phone",
        "photos", "reminders", "safari", "settings", "shortcuts", "spotify", "whatsapp",
        "youtube",
    ]

    public static let specs: [ToolSpec] = [
        ToolSpec(
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
        ),
        ToolSpec(
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
        ),
        ToolSpec(
            name: "read_next_events",
            description: "Read the user's upcoming calendar events.",
            parameters: JSONSchema(
                type: .object,
                properties: [
                    "hours_ahead": JSONSchema(type: .integer, description: "Look-ahead window, default 24"),
                ]
            ),
            risk: .safe
        ),
        ToolSpec(
            name: "find_contact",
            description: "Look up a contact's phone number by name.",
            parameters: JSONSchema(
                type: .object,
                properties: ["name": JSONSchema(type: .string)],
                required: ["name"]
            ),
            risk: .safe
        ),
        ToolSpec(
            name: "call_number",
            description: "Start a phone call to a number (get the number with find_contact first).",
            parameters: JSONSchema(
                type: .object,
                properties: ["number": JSONSchema(type: .string, description: "Digits, may include +")],
                required: ["number"]
            ),
            risk: .confirm
        ),
        ToolSpec(
            name: "compose_message",
            description: """
            Open Messages with a recipient and prefilled text. iOS never allows sending \
            silently — the user reviews and taps Send themselves.
            """,
            parameters: JSONSchema(
                type: .object,
                properties: [
                    "number": JSONSchema(type: .string, description: "Recipient phone number"),
                    "body": JSONSchema(type: .string, description: "Message text"),
                ],
                required: ["number", "body"]
            ),
            risk: .safe
        ),
        ToolSpec(
            name: "open_app",
            description: "Open an app by name.",
            parameters: JSONSchema(
                type: .object,
                properties: [
                    "app": JSONSchema(
                        type: .string,
                        description: "One of: \(knownApps.joined(separator: ", "))",
                        enumValues: knownApps
                    ),
                ],
                required: ["app"]
            ),
            risk: .safe
        ),
        ToolSpec(
            name: "open_url",
            description: "Open a web page in the browser.",
            parameters: JSONSchema(
                type: .object,
                properties: ["url": JSONSchema(type: .string, description: "https URL")],
                required: ["url"]
            ),
            risk: .safe
        ),
        ToolSpec(
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
        ),
        ToolSpec(
            name: "toggle_flashlight",
            description: "Turn the flashlight on or off.",
            parameters: JSONSchema(
                type: .object,
                properties: ["state": JSONSchema(type: .string, enumValues: ["on", "off"])],
                required: ["state"]
            ),
            risk: .safe
        ),
        ToolSpec(
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
        ),
        ToolSpec(
            name: "run_shortcut",
            description: """
            Run one of the user's registered Shortcuts by exact name, optionally passing text input. \
            Only names the user registered are allowed.
            """,
            parameters: JSONSchema(
                type: .object,
                properties: [
                    "name": JSONSchema(type: .string, description: "Exact registered shortcut name"),
                    "input": JSONSchema(type: .string, description: "Optional text input"),
                ],
                required: ["name"]
            ),
            risk: .confirm
        ),
        ToolSpec(
            name: "wait",
            description: "Pause for a number of seconds before the next action.",
            parameters: JSONSchema(
                type: .object,
                properties: [
                    "seconds": JSONSchema(type: .number, description: "How long to pause, 0.1 to 30"),
                ],
                required: ["seconds"]
            ),
            risk: .safe
        ),
        ToolSpec(
            name: "repeat_steps",
            description: """
            Run a sequence of simple actions, optionally repeating it. Use this for anything \
            repetitive ("blink the light 10 times", "toggle it on and off with a pause"). \
            Steps are written as "tool:value" separated by commas, using each tool's single \
            main argument, e.g. "toggle_flashlight:on, wait:0.5, toggle_flashlight:off, wait:0.5". \
            Only tools with one required argument can be used as steps, and actions that need \
            confirmation (calls, messages, shortcuts, calendar events) cannot be repeated — \
            call those directly instead.
            """,
            parameters: JSONSchema(
                type: .object,
                properties: [
                    "steps": JSONSchema(
                        type: .string,
                        description: "Comma-separated \"tool:value\" steps, in order"
                    ),
                    "times": JSONSchema(
                        type: .integer,
                        description: "How many times to repeat the whole sequence (default 1, max 50)"
                    ),
                ],
                required: ["steps"]
            ),
            risk: .safe
        ),
    ]

    /// The shortcut list pinned into the eval system prompt, so `run_shortcut` cases are
    /// deterministic regardless of what the tester happens to have registered.
    public static let pinnedShortcuts = ["Goodnight"]

    /// Human-readable differences between this mirror and a live registry's specs.
    /// Empty means the mirror is current. Parameter *descriptions* are compared too, not
    /// just shapes: the description is what the model reads when deciding what to emit, so
    /// a reworded one can move a score on its own and must not go unnoticed.
    public static func drift(from live: [ToolSpec]) -> [String] {
        var problems: [String] = []
        let mine = Dictionary(uniqueKeysWithValues: specs.map { ($0.name, $0) })
        let theirs = Dictionary(uniqueKeysWithValues: live.map { ($0.name, $0) })
        for name in Set(theirs.keys).subtracting(mine.keys).sorted() {
            problems.append("live registry has \"\(name)\", eval catalog does not")
        }
        for name in Set(mine.keys).subtracting(theirs.keys).sorted() {
            problems.append("eval catalog has \"\(name)\", live registry does not")
        }
        for name in Set(mine.keys).intersection(theirs.keys).sorted() {
            guard let a = mine[name], let b = theirs[name] else { continue }
            if a.parameters != b.parameters { problems.append("\"\(name)\" parameter schema differs") }
            if a.risk != b.risk { problems.append("\"\(name)\" risk differs (\(a.risk) vs \(b.risk))") }
        }
        return problems
    }
}
