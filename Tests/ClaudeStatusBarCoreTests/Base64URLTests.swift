// Tests/ClaudeStatusBarCoreTests/Base64URLTests.swift
import Testing
import Foundation
@testable import ClaudeStatusBarCore

@Test func encode_isURLSafe_andUnpadded() {
    // 0xFB 0xFF -> standard base64 "+/8=" ; url-safe unpadded -> "-_8"
    let out = Base64URL.encode(Data([0xFB, 0xFF]))
    #expect(out == "-_8")
    #expect(!out.contains("="))
    #expect(!out.contains("+"))
    #expect(!out.contains("/"))
}
