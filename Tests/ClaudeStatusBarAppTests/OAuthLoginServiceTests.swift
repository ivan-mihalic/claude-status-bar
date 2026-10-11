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
    let pending = svc.begin()!
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
    let pending = svc.begin()!
    let id = UUID()
    let bundle = try await svc.complete(pending, code: "CODE#" + pending.state, accountID: id)
    #expect(bundle.accessToken == "AT")
    #expect(try store.load(id)?.accessToken == "AT")   // persisted under accountID
}

@Test func complete_cancelledAfterExchangeDoesNotPersistCredentials() async throws {
    let store = InMemoryTokenStore()
    let http = MockHTTPClient { _ in
        withUnsafeCurrentTask { $0?.cancel() }
        return HTTPResponse(status: 200, headers: [:], body: Data(
            #"{"access_token":"AT","refresh_token":"RT","expires_in":28800}"#.utf8))
    }
    let svc = service(http, store, SpyBrowser())
    let pending = svc.begin()!
    let id = UUID()
    let operation = Task {
        await #expect(throws: CancellationError.self) {
            _ = try await svc.complete(pending, code: "CODE", accountID: id)
        }
    }
    await operation.value
    #expect(try store.load(id) == nil)
}

@Test func complete_rejectsPastedStateFromOtherLoginBeforeExchange() async throws {
    let store = InMemoryTokenStore()
    let http = MockHTTPClient()
    let svc = service(http, store, SpyBrowser())
    let pending = svc.begin()!
    let id = UUID()
    await #expect(throws: LoginError.stateMismatch) {
        _ = try await svc.complete(pending, code: "CODE#different-attempt", accountID: id)
    }
    #expect(http.requests.isEmpty)
    #expect(try store.load(id) == nil)
}

@Test(arguments: ["#", "&state="])
func complete_acceptsMatchingPastedState(separator: String) async throws {
    let store = InMemoryTokenStore()
    let http = MockHTTPClient { request in
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("code=CODE&"))
        return HTTPResponse(status: 200, headers: [:], body: Data(
            #"{"access_token":"AT","refresh_token":"RT","expires_in":28800}"#.utf8))
    }
    let svc = service(http, store, SpyBrowser())
    let pending = svc.begin()!
    _ = try await svc.complete(pending, code: " CODE" + separator + pending.state + "\n", accountID: UUID())
}

@Test func complete_emptyCodeDoesNotExchangeOrPersist() async {
    let http = MockHTTPClient()
    let svc = service(http, InMemoryTokenStore(), SpyBrowser())
    let pending = svc.begin()!
    await #expect(throws: LoginError.invalidCode) {
        _ = try await svc.complete(pending, code: "#" + pending.state, accountID: UUID())
    }
    #expect(http.requests.isEmpty)
}
