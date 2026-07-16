import Testing
import Foundation
@testable import ClaudeStatusBarApp
@testable import ClaudeStatusBarCore
import TestSupport

final class SpyBrowser: BrowserOpener, @unchecked Sendable {
    var opened: [URL] = []
    func open(_ url: URL) { opened.append(url) }
}

private func service(_ http: MockHTTPClient, _ store: TokenStore, _ browser: SpyBrowser) -> OAuthLoginService {
    OAuthLoginService(
        oauth: OAuthClient(http: http, endpoints: .production, config: .claudeCode,
                           clock: ManualClock(Date(timeIntervalSince1970: 0))),
        endpoints: .production, config: .claudeCode, tokenStore: store, opener: browser)
}

@Test func begin_opensAuthorizeURLWithChallenge() {
    let browser = SpyBrowser()
    let svc = service(MockHTTPClient(), InMemoryTokenStore(), browser)
    let pending = svc.begin()
    #expect(browser.opened.count == 1)
    let q = URLComponents(url: browser.opened[0], resolvingAgainstBaseURL: false)!.queryItems!
    #expect(q.contains { $0.name == "code_challenge" && $0.value == pending.pkce.challenge })
    #expect(q.contains { $0.name == "state" && $0.value == pending.state })
}
@Test func complete_exchangesCode_storesToken() async throws {
    let store = InMemoryTokenStore()
    let http = MockHTTPClient { _ in
        HTTPResponse(status: 200, headers: [:],
            body: Data(#"{"access_token":"AT","refresh_token":"RT","expires_in":28800,"scope":"user:profile"}"#.utf8))
    }
    let svc = service(http, store, SpyBrowser())
    let pending = svc.begin()
    let id = UUID()
    let bundle = try await svc.complete(pending, code: "CODE#state=x", accountID: id)
    #expect(bundle.accessToken == "AT")
    #expect(try store.load(id)?.accessToken == "AT")   // persisted under accountID
}
