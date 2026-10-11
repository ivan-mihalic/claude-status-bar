import Foundation

public enum ClaudeTokenImportError: Error, Equatable, LocalizedError {
    case invalidToken
    case invalidRefreshToken
    case wrongProvider

    public var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Paste a Claude OAuth access token starting with sk-ant-oat01-, not an API key or authorization code."
        case .invalidRefreshToken:
            return "Paste the matching Claude OAuth refresh token starting with sk-ant-ort01-, or leave it empty."
        case .wrongProvider:
            return "Claude OAuth tokens can only be used with Claude accounts."
        }
    }
}

public enum ClaudeTokenImport {
    public static func bundle(from rawToken: String, refreshToken rawRefreshToken: String = "") throws -> TokenBundle {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "sk-ant-oat01-"
        guard token.hasPrefix(prefix), token.count > prefix.count,
              token.utf8.count <= 8192,
              token.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
            throw ClaudeTokenImportError.invalidToken
        }
        let refreshToken = rawRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !refreshToken.isEmpty {
            let refreshPrefix = "sk-ant-ort01-"
            guard refreshToken.hasPrefix(refreshPrefix), refreshToken.count > refreshPrefix.count,
                  refreshToken.utf8.count <= 8192,
                  refreshToken.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
                throw ClaudeTokenImportError.invalidRefreshToken
            }
        }
        // Opaque token neobsahuje ověřitelné datum expirace ani refresh token.
        // Platnost rozhoduje server; nepředstíráme rok od dnešního importu.
        return TokenBundle(accessToken: token, refreshToken: refreshToken,
                           expiresAt: .distantFuture, scopes: [])
    }
}
