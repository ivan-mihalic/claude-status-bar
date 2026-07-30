// Sources/ClaudeStatusBarCore/HTTP/RetryAfter.swift
import Foundation

/// Reads how long a server asked us to wait before retrying.
///
/// Follows the same order Anthropic's own SDK uses: the non-standard, more precise
/// `retry-after-ms` first, then `retry-after` as seconds, then `retry-after` as an
/// HTTP-date. A value that isn't a positive wait is treated as absent.
public enum RetryAfter {
    public static func seconds(from headers: [String: String], now: Date) -> TimeInterval? {
        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        if let ms = header("retry-after-ms").flatMap(Double.init) {
            return positive(ms / 1000)
        }
        guard let raw = header("retry-after")?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let secs = Double(raw) { return positive(secs) }
        if let date = httpDate(raw) { return positive(date.timeIntervalSince(now)) }
        return nil
    }

    private static func positive(_ v: TimeInterval) -> TimeInterval? {
        v > 0 ? v : nil
    }

    private static func httpDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        for format in ["EEE, dd MMM yyyy HH:mm:ss 'GMT'",     // RFC 1123
                       "EEEE, dd-MMM-yy HH:mm:ss 'GMT'",       // RFC 850
                       "EEE MMM d HH:mm:ss yyyy"] {            // asctime
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
