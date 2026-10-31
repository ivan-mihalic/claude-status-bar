import Testing
import Foundation
@testable import ClaudeStatusBarCore
import TestSupport

private let fetchedAt = Date(timeIntervalSince1970: 1_793_000_000)

// Strážce invariantu: Google hlásí *zbývající* podíl, aplikace zobrazuje *spotřebu*.
// Převrácení by ukazovalo vyčerpaný účet jako prázdný.
@Test func antigravity_turnsRemainingQuotaIntoUsedPercentPerModelFamily() async throws {
    let models = Data("""
    {"models":{
      "claude-sonnet-4-5":{"displayName":"Claude Sonnet 4.5","quotaInfo":{"remainingFraction":0.75,"resetTime":"2026-10-31T15:00:00Z"}},
      "claude-opus-4-5-thinking":{"quotaInfo":{"remainingFraction":0.2,"resetTime":"2026-10-31T14:00:00Z"}},
      "gemini-3-pro-high":{"quotaInfo":{"remainingFraction":1,"resetTime":"2026-10-31T16:00:00Z"}},
      "gemini-3-flash":{"quotaInfo":{"resetTime":"2026-10-31T17:00:00Z"}},
      "tab_flash_lite_preview":{"quotaInfo":{"remainingFraction":0}},
      "gemini-old":{"disabled":true,"quotaInfo":{"remainingFraction":0}}
    }}
    """.utf8)
    let http = MockHTTPClient { request in
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer at")
        if request.url!.absoluteString.hasSuffix("/v1internal:loadCodeAssist") {
            return HTTPResponse(status: 200, headers: [:],
                                body: Data(#"{"cloudaicompanionProject":"proj-1"}"#.utf8))
        }
        #expect(request.url!.absoluteString
                == "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String]
        #expect(body == ["project": "proj-1"])
        return HTTPResponse(status: 200, headers: [:], body: models)
    }
    let tokens = TokenBundle(accessToken: "at", refreshToken: "rt",
                             expiresAt: fetchedAt.addingTimeInterval(3600), scopes: [])

    let snap = try await AntigravityUsageAPIClient(http: http).fetch(tokens: tokens, now: fetchedAt)

    // Nejhorší model rodiny určuje rodinu.
    #expect(snap.session?.label == "Claude")
    #expect(snap.session?.utilization == 80)
    #expect(snap.session?.resetsAt == ISO8601DateFormatter().date(from: "2026-10-31T14:00:00Z"))
    #expect(snap.weekAll?.label == "Gemini Pro")
    #expect(snap.weekAll?.utilization == 0)
    // Chybějící podíl = vyčerpáno.
    #expect(snap.weekPremium.map(\.label) == ["Gemini Flash"])
    #expect(snap.weekPremium.first?.utilization == 100)
}

// Strážce invariantu: Google vyžaduje client_secret i při refreshi a odpověď ho nevrací.
// Kdyby ho obnovený bundle ztratil, další refresh by účet po hodině odhlásil.
@Test func antigravity_userSecretTravelsWithTheGrantAcrossRefreshes() async throws {
    let http = MockHTTPClient { request in
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        #expect(body.contains("client_secret=user-secret"))
        return HTTPResponse(status: 200, headers: [:],
                            body: Data(#"{"access_token":"AT2","expires_in":3599}"#.utf8))
    }
    let client = OAuthClient(http: http, endpoints: .google, config: .antigravity,
                             clock: ManualClock(fetchedAt))
    let stale = TokenBundle(accessToken: "AT", refreshToken: "RT", expiresAt: fetchedAt,
                            scopes: [], clientSecret: "user-secret")

    let once = try await client.refresh(stale)
    let twice = try await client.refresh(once)

    #expect(once.clientSecret == "user-secret")
    #expect(twice.refreshToken == "RT")
    #expect(http.requests.count == 2)
}
