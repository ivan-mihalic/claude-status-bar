// Sources/ClaudeStatusBarCore/Storage/SnapshotStore.swift
import Foundation

public struct SnapshotStore {
    private let fileURL: URL
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
        return try d.decode([Account].self, from: data)
    }

    public func save(_ accounts: [Account]) throws {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try e.encode(accounts)
        try data.write(to: fileURL, options: .atomic)
    }
}
