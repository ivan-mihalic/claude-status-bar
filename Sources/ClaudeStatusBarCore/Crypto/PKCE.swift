// Sources/ClaudeStatusBarCore/Crypto/PKCE.swift
import Foundation
import CryptoKit
import Security

public struct PKCE: Equatable {
    public let verifier: String
    public let challenge: String

    public static func generate() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Base64URL.encode(Data(bytes)) // 43 chars, url-safe
        return PKCE(verifier: verifier, challenge: challenge(for: verifier))
    }

    public static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Base64URL.encode(Data(digest))
    }
}
