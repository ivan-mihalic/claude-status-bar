// Tests/ClaudeStatusBarCoreTests/PKCETests.swift
import Testing
import Foundation
import CryptoKit
@testable import ClaudeStatusBarCore

@Test func challenge_isBase64URLSha256OfVerifier() {
    // RFC 7636 Appendix B known vector.
    let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    let expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    #expect(PKCE.challenge(for: verifier) == expected)
}

@Test func generate_producesValidPair() {
    let p = PKCE.generate()
    #expect((43...128).contains(p.verifier.count))
    #expect(PKCE.challenge(for: p.verifier) == p.challenge)
    // URL-safe charset only
    let allowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    #expect(p.verifier.unicodeScalars.first { !allowed.contains($0) } == nil)
}
