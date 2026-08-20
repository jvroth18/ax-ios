import Foundation

/// Date-string reading for the eval, deliberately split into two questions:
///
/// 1. **What instant did the model mean?** (`parse`) — maximally permissive. If the model
///    said "2026-08-20 12:00" it meant noon local, and the eval should say the *semantics*
///    are right even if the app can't swallow that spelling.
/// 2. **Would the shipping tool accept this spelling?** (`hasExplicitZone`, and the
///    contracts in `ToolContract`) — strict, mirroring `ISO8601DateFormatter`.
///
/// Keeping them apart is the whole point: the confirmed `create_reminder` bug is exactly
/// the case where (1) passes and (2) fails, and a harness that only asked one of the two
/// questions could not see it.
public enum EvalDateParser {

    /// Formats accepted for "what instant did the model mean". Zone-less forms are read in
    /// `timeZone`, which is what a phone would do with them.
    private static let localFormats = [
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy/MM/dd HH:mm",
        "yyyy-MM-dd",
    ]

    public static func parse(_ raw: String, timeZone: TimeZone) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if hasExplicitZone(trimmed) {
            let iso = ISO8601DateFormatter()
            iso.timeZone = timeZone
            for options in [
                ISO8601DateFormatter.Options([.withInternetDateTime, .withFractionalSeconds]),
                ISO8601DateFormatter.Options([.withInternetDateTime]),
            ] {
                iso.formatOptions = options
                if let date = iso.date(from: trimmed) { return date }
            }
            // Some models emit "…T17:00+04:00" with no seconds, which ISO8601DateFormatter
            // rejects. Fall through to DateFormatter, which is happy to parse it.
            for format in ["yyyy-MM-dd'T'HH:mmXXXXX", "yyyy-MM-dd'T'HH:mm:ssXXXXX"] {
                if let date = formatter(format, timeZone).date(from: trimmed) { return date }
            }
            return nil
        }

        for format in localFormats {
            if let date = formatter(format, timeZone).date(from: trimmed) { return date }
        }
        return nil
    }

    /// True when the string carries a UTC offset or "Z" — the thing
    /// `ISO8601DateFormatter(.withInternetDateTime)` requires and small models routinely omit.
    public static func hasExplicitZone(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only the *time* half can carry a zone; the date half is full of hyphens.
        guard let separator = trimmed.firstIndex(where: { $0 == "T" || $0 == "t" || $0 == " " }) else {
            return false
        }
        let time = trimmed[trimmed.index(after: separator)...]
        return time.contains("Z") || time.contains("z") || time.contains("+") || time.contains("-")
    }

    private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}
