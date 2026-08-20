import Foundation

/// The frozen "now" every eval case is scored against.
///
/// WHY this exists: the only thing that tells the model what "tomorrow at noon" means is
/// the `Current date and time:` line `PromptBuilder.Context` injects, which the app fills
/// from `AgentLoop.formattedNow()` — i.e. the wall clock. Scoring a date against a moving
/// clock makes a case unreproducible: the same completion is correct on Tuesday and wrong
/// on Wednesday. So the harness pins one instant, injects *that* into the system prompt,
/// and resolves every expected date from it. A recorded completion can therefore be
/// re-scored months later and get the same answer.
public struct EvalClock: Sendable, Equatable {
    public let reference: Date
    public let timeZone: TimeZone

    public init(reference: Date, timeZone: TimeZone) {
        self.reference = reference
        self.timeZone = timeZone
    }

    /// Gregorian calendar fixed to the clock's zone, with a POSIX locale so weekday and
    /// month arithmetic never depends on the host's region settings.
    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// Exactly the shape `AgentLoop.formattedNow()` produces, e.g.
    /// "Wednesday 2026-08-19 14:30, America/New_York" — so the pinned prompt is
    /// byte-identical in structure to the one real users get.
    public var promptDateTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE yyyy-MM-dd HH:mm"
        return "\(formatter.string(from: reference)), \(timeZone.identifier)"
    }

    /// The one clock the shipped suite is written against: Wednesday 2026-08-19, 14:30
    /// America/New_York (EDT, UTC-4).
    ///
    /// Mid-week and mid-afternoon on purpose: "tomorrow", "tonight", "this weekend",
    /// "Friday" and "next Monday" all resolve to distinct, unambiguous days from here,
    /// and 14:30 is late enough that "at 9" is unambiguously tomorrow morning but early
    /// enough that "tonight at 9" is still today.
    public static let pinned = EvalClock(
        reference: {
            var calendar = Calendar(identifier: .gregorian)
            let zone = TimeZone(identifier: "America/New_York")!
            calendar.timeZone = zone
            var components = DateComponents()
            components.year = 2026
            components.month = 8
            components.day = 19
            components.hour = 14
            components.minute = 30
            // Force-unwrap: these components are a valid Gregorian date by construction.
            return calendar.date(from: components)!
        }(),
        timeZone: TimeZone(identifier: "America/New_York")!
    )
}

/// A date the model is expected to have resolved, expressed relative to `EvalClock`.
///
/// Cases never hard-code "2026-08-20T12:00:00" — they say "the day after the reference,
/// at 12:00". Re-pinning the clock therefore re-derives every expectation instead of
/// invalidating the suite.
public enum DateExpectation: Sendable, Equatable, Codable {
    /// A wall-clock time on a day offset from the reference day (0 = same day).
    case wallClock(dayOffset: Int, hour: Int, minute: Int)
    /// A pure duration from the reference instant, for "in 20 minutes"-style requests.
    case relative(seconds: TimeInterval)

    public func resolve(clock: EvalClock) -> Date {
        switch self {
        case .wallClock(let dayOffset, let hour, let minute):
            let calendar = clock.calendar
            let startOfDay = calendar.startOfDay(for: clock.reference)
            let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) ?? startOfDay
            return calendar.date(
                bySettingHour: hour, minute: minute, second: 0, of: day
            ) ?? day
        case .relative(let seconds):
            return clock.reference.addingTimeInterval(seconds)
        }
    }

    /// Human-readable form for failure messages, e.g. "2026-08-20 12:00 -0400".
    public func describe(clock: EvalClock) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = clock.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm ZZZ"
        return formatter.string(from: resolve(clock: clock))
    }
}
