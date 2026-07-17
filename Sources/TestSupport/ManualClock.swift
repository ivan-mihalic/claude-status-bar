import Foundation
import ClaudeStatusBarCore

public final class ManualClock: Clock, @unchecked Sendable {
    private var current: Date
    public init(_ start: Date) { current = start }
    public func now() -> Date { current }
    public func advance(_ seconds: TimeInterval) { current.addTimeInterval(seconds) }
}
