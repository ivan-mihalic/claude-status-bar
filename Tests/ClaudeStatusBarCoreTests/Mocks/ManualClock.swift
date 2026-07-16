import Foundation
@testable import ClaudeStatusBarCore

final class ManualClock: Clock, @unchecked Sendable {
    private var current: Date
    init(_ start: Date) { current = start }
    func now() -> Date { current }
    func advance(_ seconds: TimeInterval) { current.addTimeInterval(seconds) }
}
