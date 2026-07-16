import Testing
import Foundation
@testable import ClaudeStatusBarCore

@Test func delaySequence_capsAt300() {
    let b = Backoff.usage
    #expect(b.delay(forFailureCount: 0) == 0)   // no failures
    #expect(b.delay(forFailureCount: 1) == 30)
    #expect(b.delay(forFailureCount: 2) == 60)
    #expect(b.delay(forFailureCount: 3) == 120)
    #expect(b.delay(forFailureCount: 4) == 240)
    #expect(b.delay(forFailureCount: 5) == 300)
    #expect(b.delay(forFailureCount: 99) == 300) // stays capped
}
