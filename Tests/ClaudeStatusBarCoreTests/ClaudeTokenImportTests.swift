import Testing
import Foundation
@testable import ClaudeStatusBarCore

@Test(arguments: ["sk-ant-oat01-wrong-kind", "sk-ant-ort01-", "sk-ant-ort01-a\nb", "sk-ant-ort01-ž", String(repeating: "sk-ant-ort01-", count: 1000)])
func importToken_rejectsMalformedRefreshToken(refresh: String) {
    #expect(throws: ClaudeTokenImportError.invalidRefreshToken) {
        _ = try ClaudeTokenImport.bundle(from: "sk-ant-oat01-access", refreshToken: refresh)
    }
}

@Test func importToken_preservesOpaqueExpiryAndTrimsBothFields() throws {
    let bundle = try ClaudeTokenImport.bundle(from: " sk-ant-oat01-access\n", refreshToken: "\nsk-ant-ort01-refresh ")
    #expect(bundle.accessToken == "sk-ant-oat01-access")
    #expect(bundle.refreshToken == "sk-ant-ort01-refresh")
    #expect(bundle.expiresAt == .distantFuture)
    #expect(bundle.scopes.isEmpty)
}
