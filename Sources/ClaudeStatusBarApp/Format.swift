import Foundation

public enum Format {
    public static func percent(_ u: Double) -> String { "\(Int(u.rounded()))%" }

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
