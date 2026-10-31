import Foundation

/// An sRGB colour persisted with an account. Keeping this in the core model avoids making
/// saved account metadata depend on SwiftUI's platform-specific `Color` representation.
public struct AccountRingColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.opacity = min(max(opacity, 0), 1)
    }

    public static func suggested(for provider: Provider) -> AccountRingColor {
        switch provider {
        case .claude: return AccountRingColor(red: 0.85, green: 0.42, blue: 0.24)
        case .codex:  return AccountRingColor(red: 0.20, green: 0.78, blue: 0.65)
        case .cursor: return AccountRingColor(red: 0.55, green: 0.62, blue: 0.95)
        }
    }
}
