// Tests/ClaudeStatusBarCoreTests/UsageAdapterTests.swift
import Testing
import Foundation
@testable import ClaudeStatusBarCore

private func dto(_ name: String) throws -> UsageResponseDTO {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json",
                                              subdirectory: "Fixtures"))
    return try UsageJSON.decoder().decode(UsageResponseDTO.self,
                                          from: Data(contentsOf: url))
}

@Test func normalize_full_mapsWindowsAndLabels() throws {
    let snap = try UsageAdapter.normalize(dto("usage_full"),
                                          fetchedAt: .init(timeIntervalSince1970: 0))
    #expect(snap.session.label == "Session")
    #expect(snap.session.utilization == 33.0)
    #expect(snap.weekAll.label == "Week (all)")
    #expect(snap.weekPremium.map(\.key) == ["seven_day_sonnet"])
    #expect(snap.weekPremium.first?.label == "Week (Sonnet)")
}

@Test func normalize_unknownModel_labelsFromKey() throws {
    let snap = try UsageAdapter.normalize(dto("usage_unknown_model"),
                                          fetchedAt: .init(timeIntervalSince1970: 0))
    #expect(snap.weekPremium.map(\.key) == ["seven_day_fable"])
    #expect(snap.weekPremium.first?.label == "Week (Fable)")
}

@Test func normalize_missingCoreWindows_throws() throws {
    // usage_malformed has no valid five_hour/seven_day windows
    #expect(throws: UsageAdapterError.missingCoreWindows) {
        try UsageAdapter.normalize(dto("usage_malformed"),
                                   fetchedAt: .init(timeIntervalSince1970: 0))
    }
}
