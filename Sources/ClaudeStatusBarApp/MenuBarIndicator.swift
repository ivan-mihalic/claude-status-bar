import Foundation

public enum IndicatorLevel: Equatable, Sendable { case ok, warn, critical, unknown }

public enum MenuBarIndicator {
    public static func level(maxUtilization: Double?) -> IndicatorLevel {
        guard let u = maxUtilization else { return .unknown }
        if u >= 90 { return .critical }
        if u >= 70 { return .warn }
        return .ok
    }
    public static func label(maxUtilization: Double?) -> String {
        guard let u = maxUtilization else { return "—" }
        return Format.percent(u)
    }
}
