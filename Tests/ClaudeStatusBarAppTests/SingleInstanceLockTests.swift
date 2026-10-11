import Testing
import Foundation
@testable import ClaudeStatusBarApp

@Test func singleInstance_preventsSecondOwnerAndReleasesWhenOwnerExits() throws {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-lock-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("instance.lock")
    var first: SingleInstanceLock? = try SingleInstanceLock(fileURL: file)
    #expect(first != nil)
    #expect(throws: SingleInstanceLockError.alreadyRunning) {
        _ = try SingleInstanceLock(fileURL: file)
    }
    first = nil
    let next = try SingleInstanceLock(fileURL: file)
    withExtendedLifetime(next) {
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}

@Test func singleInstance_cannotStartWhenLockLocationIsUnavailable() throws {
    let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-file-\(UUID())")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data().write(to: file)
    #expect(throws: SingleInstanceLockError.unavailable) {
        _ = try SingleInstanceLock(fileURL: file.appendingPathComponent("instance.lock"))
    }
}
