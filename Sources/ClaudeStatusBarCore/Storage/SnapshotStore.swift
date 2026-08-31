// Sources/ClaudeStatusBarCore/Storage/SnapshotStore.swift
import Foundation

/// Persists the account list.
///
/// A class, not a struct, because it remembers what it last wrote: every sync used to
/// rewrite the whole file whether or not anything in it had changed, and an atomic write is
/// a write plus a rename, not a free operation.
public final class SnapshotStore {
    private let fileURL: URL
    /// Bytes of the last successful write, so an unchanged save can be skipped.
    private var lastWritten: Data?

    public init(fileURL: URL) { self.fileURL = fileURL }

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("cz.mihalic.claude-status-bar", isDirectory: true)
        try? FileManager.default.createDirectory(at: base,
            withIntermediateDirectories: true)
        return base.appendingPathComponent("accounts.json")
    }

    public func load() throws -> [Account] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let accounts = try d.decode([Account].self, from: data)
        // What was just read *is* what is on disk, so a save of the same thing is a no-op.
        lastWritten = data
        return accounts
    }

    /// Writes the list, unless the bytes are identical to the last successful write and the
    /// file is still there.
    ///
    /// - Returns: whether anything was actually written. The caller does not need this, but
    ///   without it there is no way to prove the skip happens.
    @discardableResult
    public func save(_ accounts: [Account]) throws -> Bool {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try e.encode(accounts)
        // The file check is not paranoia: remembering bytes alone would mean a file deleted
        // underneath us never came back.
        if data == lastWritten, FileManager.default.fileExists(atPath: fileURL.path) {
            return false
        }
        try data.write(to: fileURL, options: .atomic)
        // Only after the write succeeds — a failed write must not be remembered as done.
        lastWritten = data
        return true
    }
}
