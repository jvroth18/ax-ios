import Foundation

/// Parses the date-times models hand tools as arguments.
///
/// The prompt asks for ISO 8601, but small models are loose about it: they drop the
/// timezone, drop the seconds, drop the time entirely, or separate date and time with a
/// space. `ISO8601DateFormatter` rejects every one of those — its `.withInternetDateTime`
/// option demands a full date-time *with* a zone designator — so a tool that reaches for a
/// formatter directly ends up rejecting the exact shape the prompt taught the model to
/// emit. Every tool that takes a date goes through here instead.
///
/// A value with no zone designator is a wall-clock time in the *user's* timezone: "remind
/// me at five" means five where they're standing, never five UTC. Zoned values are taken
/// at face value.
public enum DateArgument {

    public struct Parsed: Equatable, Sendable {
        /// The instant the string denotes.
        public let date: Date
        /// False when the string carried only a calendar date ("2026-08-17"), so callers
        /// can make an untimed reminder instead of one that fires at midnight.
        public let hasTime: Bool

        public init(date: Date, hasTime: Bool) {
            self.date = date
            self.hasTime = hasTime
        }
    }

    /// Accepted shapes, each with an optional trailing `Z` / `±HH:MM` / `±HHMM`:
    /// `2026-08-17T17:00:00.500`, `2026-08-17T17:00:00`, `2026-08-17T17:00`,
    /// `2026-08-17 17:00`, `2026-08-17`. Anything else returns nil — a wrong date is worse
    /// than a "didn't understand that" the model can retry.
    ///
    /// Components are resolved through `Calendar`, not by offsetting a UTC-parsed instant,
    /// so DST transitions land on the right second.
    public static func parse(_ raw: String) -> Parsed? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = try? pattern.wholeMatch(in: text),
              let year = Int(match.year), let month = Int(match.month), let day = Int(match.day),
              isRealDate(year: year, month: month, day: day)
        else { return nil }

        // Absent time fields mean midnight; out-of-range ones mean the model made the
        // value up, and rolling "T25:00" over into the next day would be a lie.
        let hour = match.hour.flatMap { Int($0) } ?? 0
        let minute = match.minute.flatMap { Int($0) } ?? 0
        let second = match.second.flatMap { Int($0) } ?? 0
        guard hour < 24, minute < 60, second < 60 else { return nil }

        let zone: TimeZone
        if let designator = match.zone {
            guard let parsed = timeZone(designator: String(designator)) else { return nil }
            zone = parsed
        } else {
            zone = .current
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let date = calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        )) else { return nil }

        return Parsed(date: date, hasTime: match.hour != nil)
    }

    // MARK: - Internals

    /// Month, day, and hour take one or two digits: zero-padding is what the prompt asks
    /// for, but "2026-8-17T9:00" is a shape models produce and it means one thing only.
    private static let pattern = #/(?<year>\d{4})-(?<month>\d{1,2})-(?<day>\d{1,2})(?:[Tt ](?<hour>\d{1,2}):(?<minute>\d{2})(?::(?<second>\d{2})(?:[.,]\d+)?)?)?(?<zone>[Zz]|[+-]\d{2}:?\d{2})?/#

    /// Whether year-month-day is a real calendar date (rejects "2026-02-31"). Checked in
    /// UTC: day-of-month validity is calendar arithmetic, and doing it in a zone with a
    /// DST transition that day could make a real date look invalid.
    private static func isRealDate(year: Int, month: Int, day: Int) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let wanted = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: wanted) else { return false }
        return calendar.dateComponents([.year, .month, .day], from: date) == wanted
    }

    /// `Z`, `+05:30`, `-0400`. Nil only for an offset the OS won't accept.
    private static func timeZone(designator: String) -> TimeZone? {
        if designator.caseInsensitiveCompare("Z") == .orderedSame {
            return TimeZone(secondsFromGMT: 0)
        }
        let digits = designator.dropFirst().filter(\.isNumber)
        guard digits.count == 4,
              let hours = Int(digits.prefix(2)),
              let minutes = Int(digits.suffix(2))
        else { return nil }
        let magnitude = hours * 3600 + minutes * 60
        return TimeZone(secondsFromGMT: designator.hasPrefix("-") ? -magnitude : magnitude)
    }
}

public extension String {
    /// The instant this date argument denotes, or nil if it isn't a date Morse understands.
    /// See `DateArgument.parse` for the accepted shapes and the local-time rule.
    var iso8601Date: Date? { DateArgument.parse(self)?.date }
}
