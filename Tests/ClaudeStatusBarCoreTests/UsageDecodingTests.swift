// Tests/ClaudeStatusBarCoreTests/UsageDecodingTests.swift
import Testing
import Foundation
@testable import ClaudeStatusBarCore

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json",
                                              subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Test func full_decodesWindows_skipsNullAndExtraUsage() throws {
    let dto = try UsageJSON.decoder()
        .decode(UsageResponseDTO.self, from: fixture("usage_full"))
    #expect(dto.windows["five_hour"]?.utilization == 33.0)
    #expect(dto.windows["seven_day"]?.utilization == 13.0)
    #expect(dto.windows["seven_day_sonnet"] != nil)
    #expect(dto.windows["seven_day_opus"] == nil)   // null -> dropped
    #expect(dto.windows["extra_usage"] == nil)      // wrong shape -> dropped
}

@Test func unknownModelKey_isCaptured() throws {
    let dto = try UsageJSON.decoder()
        .decode(UsageResponseDTO.self, from: fixture("usage_unknown_model"))
    #expect(dto.windows["seven_day_fable"]?.utilization == 12.0)
}

@Test func malformed_windowsAreDropped_notThrown() throws {
    let dto = try UsageJSON.decoder()
        .decode(UsageResponseDTO.self, from: fixture("usage_malformed"))
    #expect(dto.windows.isEmpty)
}
