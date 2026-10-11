import Foundation

public enum ClaudeTokenImportError: Error, Equatable, LocalizedError {
    case invalidToken
    case wrongProvider

    public var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Paste a Claude OAuth access token starting with sk-ant-oat01-, not an API key or authorization code."
        case .wrongProvider:
            return "Claude OAuth tokens can only be used with Claude accounts."
        }
    }
}

public enum ClaudeTokenImport {
    public static func bundle(from rawToken: String) throws -> TokenBundle {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "sk-ant-oat01-"
        guard token.hasPrefix(prefix), token.count > prefix.count,
              token.utf8.count <= 8192,
              token.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
            throw ClaudeTokenImportError.invalidToken
        }
        // Opaque token neobsahuje ověřitelné datum expirace ani refresh token.
        // Platnost rozhoduje server; nepředstíráme rok od dnešního importu.
        return TokenBundle(accessToken: token, refreshToken: "",
                           expiresAt: .distantFuture, scopes: [])
    }
}
