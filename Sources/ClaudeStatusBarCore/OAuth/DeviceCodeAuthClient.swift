import Foundation

public struct DeviceCodeLogin: Equatable, Sendable {
    public let verificationURL: URL
    public let userCode: String
    public let deviceAuthID: String
    public let interval: TimeInterval

    public init(verificationURL: URL, userCode: String, deviceAuthID: String,
                interval: TimeInterval) {
        self.verificationURL = verificationURL
        self.userCode = userCode
        self.deviceAuthID = deviceAuthID
        self.interval = interval
    }
}

public enum DeviceCodeError: Error, Equatable {
    case unavailable
    case http(Int)
    case decoding
    case timedOut
}

extension DeviceCodeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Device-code sign-in is not enabled for this account."
        case .http(let status): return "Device-code sign-in failed (HTTP \(status))."
        case .decoding: return "OpenAI returned an unreadable device-code response."
        case .timedOut: return "The device code expired before sign-in finished."
        }
    }
}

public enum DeviceCodePollResult: Equatable, Sendable {
    case pending
    case complete(TokenBundle)
}

/// ChatGPT subscription login for a device that cannot receive a localhost callback.
/// The endpoint shapes mirror the Codex CLI device-code implementation.
public struct DeviceCodeAuthClient: Sendable {
    private struct UserCodeRequest: Encodable { let client_id: String }
    private struct UserCodeResponse: Decodable {
        let device_auth_id: String
        let user_code: String
        let interval: TimeInterval?

        private enum CodingKeys: String, CodingKey {
            case device_auth_id, user_code, usercode, interval
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            device_auth_id = try c.decode(String.self, forKey: .device_auth_id)
            user_code = try c.decodeIfPresent(String.self, forKey: .user_code)
                ?? c.decode(String.self, forKey: .usercode)
            if let number = try? c.decodeIfPresent(Double.self, forKey: .interval) {
                interval = number
            } else if let text = try? c.decodeIfPresent(String.self, forKey: .interval) {
                interval = Double(text)
            } else {
                interval = nil
            }
        }
    }
    private struct PollRequest: Encodable {
        let device_auth_id: String
        let user_code: String
    }
    private struct CodeResponse: Decodable {
        let authorization_code: String
        let code_verifier: String
    }

    private let http: any HTTPClient
    private let oauth: OAuthClient
    private let config: OAuthConfig
    private let issuer: URL

    public init(http: any HTTPClient, oauth: OAuthClient, config: OAuthConfig,
                issuer: URL = URL(string: "https://auth.openai.com")!) {
        self.http = http; self.oauth = oauth; self.config = config; self.issuer = issuer
    }

    public func requestCode() async throws -> DeviceCodeLogin {
        let url = issuer.appending(path: "api/accounts/deviceauth/usercode")
        let response = try await http.send(jsonRequest(url, UserCodeRequest(client_id: config.clientID)))
        guard response.status != 404 else { throw DeviceCodeError.unavailable }
        guard (200..<300).contains(response.status) else { throw DeviceCodeError.http(response.status) }
        guard let decoded = try? JSONDecoder().decode(UserCodeResponse.self, from: response.body),
              let verificationURL = URL(string: "codex/device", relativeTo: issuer)?.absoluteURL else {
            throw DeviceCodeError.decoding
        }
        return DeviceCodeLogin(verificationURL: verificationURL,
                               userCode: decoded.user_code,
                               deviceAuthID: decoded.device_auth_id,
                               interval: min(max(decoded.interval ?? 5, 1), 60))
    }

    public func poll(_ login: DeviceCodeLogin) async throws -> DeviceCodePollResult {
        let url = issuer.appending(path: "api/accounts/deviceauth/token")
        let body = PollRequest(device_auth_id: login.deviceAuthID, user_code: login.userCode)
        let response = try await http.send(jsonRequest(url, body))
        if response.status == 403 || response.status == 404 { return .pending }
        guard (200..<300).contains(response.status) else { throw DeviceCodeError.http(response.status) }
        guard let code = try? JSONDecoder().decode(CodeResponse.self, from: response.body) else {
            throw DeviceCodeError.decoding
        }
        let redirect = issuer.appending(path: "deviceauth/callback").absoluteString
        let bundle = try await oauth.exchange(code: code.authorization_code,
                                              verifier: code.code_verifier,
                                              redirectURI: redirect)
        return .complete(bundle)
    }

    public func complete(_ login: DeviceCodeLogin,
                         timeout: TimeInterval = 15 * 60) async throws -> TokenBundle {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            switch try await poll(login) {
            case .complete(let bundle): return bundle
            case .pending:
                try await Task.sleep(nanoseconds: UInt64(login.interval * 1_000_000_000))
            }
        }
        throw DeviceCodeError.timedOut
    }

    private func jsonRequest<T: Encodable>(_ url: URL, _ body: T) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }
}
