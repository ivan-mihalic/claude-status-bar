// Tests/ClaudeStatusBarCoreTests/ClaudeCodeImporterTests.swift
import Testing
import Foundation
@testable import ClaudeStatusBarCore

private struct FakeSecret: SecretReader {
    let data: Data?
    func read() throws -> Data? { data }
}
private struct FakeFile: TextFileReader {
    let data: Data?
    func read(_ url: URL) throws -> Data? { data }
}

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json",
                                              subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Test func import_parsesBundleAndEmail() throws {
    let imp = ClaudeCodeImporter(
        secretReader: FakeSecret(data: try fixture("cc_credentials")),
        fileReader: FakeFile(data: try fixture("claude_config")),
        configURL: URL(fileURLWithPath: "/dev/null"))
    let acct = try imp.`import`()
    #expect(acct.bundle.accessToken == "sk-ant-oat01-FAKEACCESS")
    #expect(acct.bundle.refreshToken == "sk-ant-ort01-FAKEREFRESH")
    // expiresAt is ms epoch -> seconds
    #expect(acct.bundle.expiresAt == Date(timeIntervalSince1970: 1_893_456_000))
    #expect(acct.email == "work@example.com")
    #expect(acct.accountUuid == "11111111-2222-3333-4444-555555555555")
}

@Test func import_noCredentials_throws() {
    let imp = ClaudeCodeImporter(
        secretReader: FakeSecret(data: nil),
        fileReader: FakeFile(data: nil),
        configURL: URL(fileURLWithPath: "/dev/null"))
    #expect(throws: ImportError.noCredentials) {
        try imp.`import`()
    }
}

@Test func import_missingConfig_stillReturnsBundleWithoutEmail() throws {
    let imp = ClaudeCodeImporter(
        secretReader: FakeSecret(data: try fixture("cc_credentials")),
        fileReader: FakeFile(data: nil),
        configURL: URL(fileURLWithPath: "/dev/null"))
    let acct = try imp.`import`()
    #expect(acct.email == nil)
    #expect(acct.bundle.accessToken == "sk-ant-oat01-FAKEACCESS")
}
