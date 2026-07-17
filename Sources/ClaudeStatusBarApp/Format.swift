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
        let h = secs / 3600, m = (secs % 3600) / 60
        if h > 0 { return "resets in \(h)h \(m)m" }
        return "resets in \(m)m"
    }
}
