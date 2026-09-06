import Testing
import Foundation
import TestSupport
@testable import ClaudeStatusBarCore

private func deviceClient(_ http: MockHTTPClient) -> DeviceCodeAuthClient {
    let oauth = OAuthClient(http: http, endpoints: .openAI, config: .codex,
                            clock: ManualClock(Date(timeIntervalSince1970: 100)))
    return DeviceCodeAuthClient(http: http, oauth: oauth, config: .codex)
}

@Test func deviceCode_requestsAUserCodeUsingTheCodexClientID() async throws {
    let http = MockHTTPClient { request in
        #expect(request.url?.path == "/api/accounts/deviceauth/usercode")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json["client_id"] == OAuthConfig.codex.clientID)
        return HTTPResponse(status: 200, headers: [:], body: Data(
            #"{"device_auth_id":"device-id","user_code":"ABCD-1234","interval":"2"}"#.utf8))
    }

    let login = try await deviceClient(http).requestCode()
    #expect(login.userCode == "ABCD-1234")
    #expect(login.deviceAuthID == "device-id")
    #expect(login.interval == 2)
    #expect(login.verificationURL.absoluteString == "https://auth.openai.com/codex/device")
}

@Test func deviceCode_pendingAndSuccessfulPollUsesTheDeviceRedirect() async throws {
    final class Calls: @unchecked Sendable { var count = 0 }
    let calls = Calls()
    let http = MockHTTPClient { request in
        calls.count += 1
        if calls.count == 1 {
            #expect(request.url?.path == "/api/accounts/deviceauth/token")
            return HTTPResponse(status: 403, headers: [:], body: Data())
        }
        if calls.count == 2 {
            return HTTPResponse(status: 200, headers: [:], body: Data(
                #"{"authorization_code":"auth-code","code_challenge":"unused","code_verifier":"verifier"}"#.utf8))
        }
        #expect(request.url?.path == "/oauth/token")
        let form = String(data: try #require(request.httpBody), encoding: .utf8) ?? ""
        #expect(form.contains("redirect_uri=https://auth.openai.com/deviceauth/callback"))
        #expect(form.contains("code_verifier=verifier"))
        return HTTPResponse(status: 200, headers: [:], body: Data(
            #"{"access_token":"AT","refresh_token":"RT","expires_in":3600}"#.utf8))
    }
    let client = deviceClient(http)
    let login = DeviceCodeLogin(verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
                                userCode: "ABCD-1234", deviceAuthID: "device-id", interval: 1)
    #expect(try await client.poll(login) == .pending)
    guard case .complete(let bundle) = try await client.poll(login) else {
        Issue.record("expected completed device login"); return
    }
    #expect(bundle.accessToken == "AT")
    #expect(bundle.refreshToken == "RT")
}
