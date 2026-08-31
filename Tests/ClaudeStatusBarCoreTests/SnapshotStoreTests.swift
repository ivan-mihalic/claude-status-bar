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

@Test func roundtrip_populatedDatesAndRateLimitedStatus() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("csb-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = SnapshotStore(fileURL: tmp)

    let reset = Date(timeIntervalSince1970: 1_700_000_000)
    let fetched = Date(timeIntervalSince1970: 1_700_000_500)
    let retry = Date(timeIntervalSince1970: 1_700_000_900)
    let win = UsageWindow(key: "five_hour", label: "Session", utilization: 42.0, resetsAt: reset)
    let weekAll = UsageWindow(key: "seven_day", label: "Week (all)", utilization: 10.0, resetsAt: reset)
    let premium = UsageWindow(key: "seven_day_fable", label: "Week (Fable)", utilization: 5.0, resetsAt: reset)
    let snap = UsageSnapshot(session: win, weekAll: weekAll, weekPremium: [premium], fetchedAt: fetched)
    let acct = Account(id: UUID(), label: "u@example.com", accountUuid: "uuid",
                       syncInterval: 300, status: .rateLimited(retryAt: retry),
                       lastSnapshot: snap, lastSyncedAt: fetched)

    try store.save([acct])
    #expect(try store.load() == [acct])
}

// Každý sync dosud přepsal celý soubor, i když se v něm nic nezměnilo. Zápis je
// atomický (write + rename), takže to není zadarmo — a při intervalu 5 minut na
// účet to je zápis na disk každých pár desítek sekund za nic.
@Test func save_skipsTheWriteWhenNothingChanged() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("csb-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = SnapshotStore(fileURL: tmp)

    let acct = Account(id: UUID(), label: "a", accountUuid: "u",
                       syncInterval: 300, status: .ok, lastSnapshot: nil, lastSyncedAt: nil)

    #expect(try store.save([acct]) == true)     // první zápis proběhne
    #expect(try store.save([acct]) == false)    // druhý identický už ne
    #expect(try store.save([acct]) == false)

    var changed = acct
    changed.label = "b"
    #expect(try store.save([changed]) == true)  // změna zapsat musí
    #expect(try store.load() == [changed])      // a musí být na disku
}

// Přeskakování se nesmí opřít o paměť procesu tam, kde soubor mezitím zmizel —
// jinak by se stav po ručním smazání nikdy neobnovil.
@Test func save_writesAgainWhenTheFileDisappeared() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("csb-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = SnapshotStore(fileURL: tmp)

    let acct = Account(id: UUID(), label: "a", accountUuid: "u",
                       syncInterval: 300, status: .ok, lastSnapshot: nil, lastSyncedAt: nil)
    #expect(try store.save([acct]) == true)
    try FileManager.default.removeItem(at: tmp)
    #expect(try store.save([acct]) == true)
    #expect(try store.load() == [acct])
}
