import Foundation

public enum Format {
    public static func percent(_ u: Double) -> String { "\(Int(u.rounded()))%" }

    /// Relative "last synced" label, minutes-first per the UI, e.g. "Synced 5 min ago".
    public static func relativeSync(from date: Date?, now: Date) -> String {
        guard let date else { return "Never synced" }
        let secs = Int(now.timeIntervalSince(date))
        if secs < 5 { return "Synced just now" }
        if secs < 60 { return "Synced \(secs)s ago" }
        let mins = secs / 60
        if mins < 60 { return "Synced \(mins) min ago" }
        let hrs = mins / 60
        if hrs < 24 { return "Synced \(hrs)h ago" }
        return "Synced \(hrs / 24)d ago"
    }

    public static func bar(_ u: Double, width: Int = 24) -> String {
        let filled = max(0, min(width, Int((u / 100.0 * Double(width)).rounded())))
        return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
    }

    public static func resetCountdown(to date: Date, now: Date) -> String {
        let secs = Int(date.timeIntervalSince(now))
        if secs <= 0 { return "resetting…" }
        let d = secs / 86400
        let h = (secs % 86400) / 3600
        let m = (secs % 3600) / 60
        var parts: [String] = []
        if d > 0 { parts.append("\(d)d") }
        if d > 0 || h > 0 { parts.append("\(h)h") }
        parts.append("\(m)m")
        return "resets in " + parts.joined(separator: " ")
    }

    /// Default zone for absolute stamps in the notch panel.
    public static let displayTimeZone = TimeZone(identifier: "Europe/Prague") ?? .current

    /// When an account last synced, for the notch popover.
    ///
    /// An age is readable for about a day; past that "27h ago" stops meaning anything and a
    /// date does the job better. The zone is a parameter rather than `.current` so the stamp
    /// keeps meaning the same thing on a laptop that has travelled.
    public static func lastSync(_ date: Date?, now: Date,
                                timeZone: TimeZone = displayTimeZone) -> String {
        guard let date else { return "Never" }
        // A snapshot restored after a clock change can sit in the future; "-3h ago" reads
        // as a bug, so anything not in the past is simply "just now".
        let secs = Int(now.timeIntervalSince(date))
        if secs < 5 { return "just now" }
        if secs < 60 { return "\(secs)s ago" }
        if secs < 3600 { return "\(secs / 60) min ago" }
        if secs < 86_400 { return "\(secs / 3600)h ago" }
        return absoluteReset(date, timeZone: timeZone)
    }

    /// Absolute reset moment, e.g. "Thu 23.7. 00:59" (day-of-week + date + time), in the
    /// given locale/time zone (defaults to the user's system settings).
    public static func absoluteReset(_ date: Date, locale: Locale = .current,
                                     timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.dateFormat = "EEE d.M. HH:mm"
        return f.string(from: date)
    }
}
