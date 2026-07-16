// Tests/ClaudeStatusBarCoreTests/Base64URLTests.swift
import XCTest
@testable import ClaudeStatusBarCore

final class Base64URLTests: XCTestCase {
    func test_encode_isURLSafe_andUnpadded() {
        // 0xFB 0xFF -> standard base64 "+/8=" ; url-safe unpadded -> "-_8"
        let out = Base64URL.encode(Data([0xFB, 0xFF]))
        XCTAssertEqual(out, "-_8")
        XCTAssertFalse(out.contains("="))
        XCTAssertFalse(out.contains("+"))
        XCTAssertFalse(out.contains("/"))
    }
}
