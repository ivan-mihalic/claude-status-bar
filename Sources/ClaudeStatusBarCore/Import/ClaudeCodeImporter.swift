// Sources/ClaudeStatusBarCore/Import/ClaudeCodeImporter.swift
import Foundation
import Security

public protocol SecretReader: Sendable { func read() throws -> Data? }
public protocol TextFileReader: Sendable { func read(_ url: URL) throws -> Data? }

public struct ImportedAccount: Equatable, Sendable {
    public let bundle: TokenBundle
    public let email: String?
    public let accountUuid: String?
}

public enum ImportError: Error, Equatable { case noCredentials, malformed }

public struct ClaudeCodeImporter {
    private let secretReader: SecretReader
    private let fileReader: TextFileReader
    private let configURL: URL

    public init(secretReader: SecretReader, fileReader: TextFileReader,
                configURL: URL) {
        self.secretReader = secretReader
        self.fileReader = fileReader
        self.configURL = configURL
    }

    private struct Credentials: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let refreshToken: String
            let expiresAt: Double      // ms epoch
            let scopes: [String]?
        }
        let claudeAiOauth: OAuth
    }
    private struct Config: Decodable {
        struct OAuthAccount: Decodable {
            let accountUuid: String?
            let emailAddress: String?
        }
        let oauthAccount: OAuthAccount?
    }

    public func `import`() throws -> ImportedAccount {
        guard let data = try secretReader.read() else { throw ImportError.noCredentials }
        let creds: Credentials
        do { creds = try JSONDecoder().decode(Credentials.self, from: data) }
        catch { throw ImportError.malformed }

        let o = creds.claudeAiOauth
        let bundle = TokenBundle(
            accessToken: o.accessToken,
            refreshToken: o.refreshToken,
            expiresAt: Date(timeIntervalSince1970: o.expiresAt / 1000.0),
            scopes: o.scopes ?? [])

        var email: String?; var uuid: String?
        if let cfg = try? fileReader.read(configURL),
           let parsed = try? JSONDecoder().decode(Config.self, from: cfg) {
            email = parsed.oauthAccount?.emailAddress
            uuid = parsed.oauthAccount?.accountUuid
        }
        return ImportedAccount(bundle: bundle, email: email, accountUuid: uuid)
    }
}

// Real keychain reader for the Claude Code credential item.
public struct KeychainSecretReader: SecretReader {
    private let service: String
    private let account: String
    public init(service: String = "Claude Code-credentials",
                account: String = NSUserName()) {
        self.service = service; self.account = account
    }
    public func read() throws -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        return out as? Data
    }
}

public struct DiskFileReader: TextFileReader {
    public init() {}
    public func read(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
}
