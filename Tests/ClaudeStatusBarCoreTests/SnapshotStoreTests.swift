// Tests/ClaudeStatusBarCoreTests/SnapshotStoreTests.swift
import Testing
import Foundation
@testable import ClaudeStatusBarCore

@Test func saveLoad_roundtrip_and_noSecretsOnDisk() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("csb-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = SnapshotStore(fileURL: tmp)

    #expect(try store.load() == [])   // missing file -> empty

    let acct = Account(id: UUID(), label: "work@example.com", accountUuid: "u",
                       syncInterval: 300, status: .ok,
                       lastSnapshot: nil, lastSyncedAt: nil)
    try store.save([acct])
    #expect(try store.load() == [acct])

    let raw = try String(contentsOf: tmp, encoding: .utf8)
    #expect(!raw.lowercased().contains("accesstoken"))
    #expect(!raw.contains("sk-ant-"))
}
