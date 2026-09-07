import Testing
import Foundation
@testable import ClaudeStatusBarCore
import TestSupport

private func codexFixture() throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "codex_usage", withExtension: "json",
                                             subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private let fetchedAt = Date(timeIntervalSince1970: 1_788_177_574)

private func jwt(accountID: String) -> String {
    let payload = Data(#"{"https://api.openai.com/auth":{"chatgpt_account_id":"\#(accountID)"}}"#.utf8)
    return "header.\(Base64URL.encode(payload)).signature"
}

@Test func codex_usage_routesTheRequestToTheAccountInTheAccessToken() async throws {
    let http = MockHTTPClient { request in
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "account-123")
        return HTTPResponse(status: 200, headers: [:], body: try codexFixture())
    }
    let client = CodexUsageAPIClient(http: http)

    _ = try await client.fetch(accessToken: jwt(accountID: "account-123"), now: fetchedAt)
}

@Test func codex_decodesTheLiveResponseShape() throws {
    // The fixture is a real 200 from /backend-api/wham/usage with its identifiers redacted,
    // captured 2026-08-31 — not a shape invented from field names in a binary.
    let dto = try JSONDecoder().decode(CodexUsageDTO.self, from: codexFixture())
    #expect(dto.planType == "plus")
    #expect(dto.rateLimit?.primaryWindow?.limitWindowSeconds == 18_000)
    #expect(dto.rateLimit?.secondaryWindow?.limitWindowSeconds == 604_800)
    #expect(dto.rateLimit?.primaryWindow?.resetAt != nil)
}

@Test func codex_normalizesIntoTheSameSnapshotEveryOtherViewAlreadySpeaks() throws {
    let dto = try JSONDecoder().decode(CodexUsageDTO.self, from: codexFixture())
    let snap = try CodexUsageAdapter.normalize(dto, fetchedAt: fetchedAt)
    #expect(snap.session?.key == "five_hour")
    #expect(snap.weekAll?.key == "seven_day")
    // Codex reports no per-model weekly allowance, so there is nothing to invent here.
    #expect(snap.weekPremium.isEmpty)
    #expect(snap.fetchedAt == fetchedAt)
}

@Test func codex_prefersTheAbsoluteResetOverACountdown() throws {
    // `reset_after_seconds` is measured from when the server answered. A snapshot that sat
    // through a laptop sleeping would otherwise count down from the wrong moment.
    let json = """
    {"plan_type":"plus","rate_limit":{
      "primary_window":{"used_percent":10,"limit_window_seconds":18000,
                        "reset_after_seconds":18000,"reset_at":1788195574},
      "secondary_window":{"used_percent":20,"limit_window_seconds":604800,
                          "reset_after_seconds":604800,"reset_at":1788782374}}}
    """
    let dto = try JSONDecoder().decode(CodexUsageDTO.self, from: Data(json.utf8))
    let snap = try CodexUsageAdapter.normalize(dto, fetchedAt: fetchedAt)
    #expect(snap.session?.resetsAt == Date(timeIntervalSince1970: 1_788_195_574))
    #expect(snap.weekAll?.resetsAt == Date(timeIntervalSince1970: 1_788_782_374))
}

@Test func codex_fallsBackToTheCountdownWhenNoAbsoluteResetIsSent() throws {
    let json = """
    {"rate_limit":{
      "primary_window":{"used_percent":5,"limit_window_seconds":18000,"reset_after_seconds":900},
      "secondary_window":{"used_percent":5,"limit_window_seconds":604800}}}
    """
    let dto = try JSONDecoder().decode(CodexUsageDTO.self, from: Data(json.utf8))
    let snap = try CodexUsageAdapter.normalize(dto, fetchedAt: fetchedAt)
    #expect(snap.session?.resetsAt == fetchedAt.addingTimeInterval(900))
    // No countdown either: fall back to the window's own length rather than "now".
    #expect(snap.weekAll?.resetsAt == fetchedAt.addingTimeInterval(604_800))
}

@Test func codex_refusesAPayloadWithoutAnyWindow() throws {
    // An empty snapshot would render as a confident 0%, which is worse than an error.
    let json = #"{"plan_type":"plus","rate_limit":{"primary_window":null,"secondary_window":null}}"#
    let dto = try JSONDecoder().decode(CodexUsageDTO.self, from: Data(json.utf8))
    #expect(throws: UsageAdapterError.missingCoreWindows) {
        try CodexUsageAdapter.normalize(dto, fetchedAt: fetchedAt)
    }
    let empty = try JSONDecoder().decode(CodexUsageDTO.self, from: Data(#"{}"#.utf8))
    #expect(throws: UsageAdapterError.missingCoreWindows) {
        try CodexUsageAdapter.normalize(empty, fetchedAt: fetchedAt)
    }
}

@Test func codex_keepsAValidSingleWeeklyWindow() throws {
    let json = """
    {"rate_limit":{"primary_window":{"used_percent":27,"limit_window_seconds":604800,
                                        "reset_after_seconds":3600},
                   "secondary_window":null}}
    """
    let dto = try JSONDecoder().decode(CodexUsageDTO.self, from: Data(json.utf8))
    let snap = try CodexUsageAdapter.normalize(dto, fetchedAt: fetchedAt)

    #expect(snap.allWindows.count == 1)
    #expect(snap.allWindows.first?.key == "seven_day")
    #expect(snap.allWindows.first?.utilization == 27)
}

@Test func codex_clampsNonsensePercentages() throws {
    let json = """
    {"rate_limit":{"primary_window":{"used_percent":140,"limit_window_seconds":18000},
                   "secondary_window":{"used_percent":-3,"limit_window_seconds":604800}}}
    """
    let dto = try JSONDecoder().decode(CodexUsageDTO.self, from: Data(json.utf8))
    let snap = try CodexUsageAdapter.normalize(dto, fetchedAt: fetchedAt)
    #expect(snap.session?.utilization == 100)
    #expect(snap.weekAll?.utilization == 0)
}

@Test func codex_labelsAnUnfamiliarWindowByItsLengthInsteadOfGuessing() {
    #expect(CodexUsageAdapter.label(forWindowSeconds: 18_000) == "Session")
    #expect(CodexUsageAdapter.label(forWindowSeconds: 604_800) == "Week")
    #expect(CodexUsageAdapter.label(forWindowSeconds: 3600) == "1-hour window")
    #expect(CodexUsageAdapter.label(forWindowSeconds: 259_200) == "3-day window")
    #expect(CodexUsageAdapter.key(forWindowSeconds: 3600) == "window_3600")
}
