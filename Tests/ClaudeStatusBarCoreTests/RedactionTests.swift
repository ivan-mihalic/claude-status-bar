// Tests/ClaudeStatusBarCoreTests/RedactionTests.swift
import Testing
import Foundation
@testable import ClaudeStatusBarCore

@Test func masksAnthropicTokens() {
    let s = "auth=sk-ant-oat01-ABCdef123-_ end refresh=sk-ant-ort01-ZZZ999 done"
    let r = Redaction.redact(s)
    #expect(!r.contains("ABCdef123"))
    #expect(!r.contains("ZZZ999"))
    #expect(r.contains("sk-ant-oat01-***"))
    #expect(r.contains("sk-ant-ort01-***"))
    #expect(r.contains("done"))
}
