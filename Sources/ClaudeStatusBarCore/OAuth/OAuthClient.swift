// Sources/ClaudeStatusBarCore/OAuth/OAuthClient.swift
import Foundation

public enum OAuthError: Error, Equatable {
    case invalidGrant
    case http(Int)
    case allHostsFailed
    case decoding
}

public struct OAuthClient: Sendable {
    private let http: HTTPClient
    private let endpoints: OAuthEndpoints
    private let config: OAuthConfig
    private let clock: Clock

    public init(http: HTTPClient, endpoints: OAuthEndpoints,
                config: OAuthConfig, clock: Clock) {
        self.http = http; self.endpoints = endpoints
        self.config = config; self.clock = clock
    }

    public func exchange(code: String, verifier: String,
                         state: String) async throws -> TokenBundle {
        try await exchange(code: code, verifier: verifier,
                           redirectURI: config.redirectURI, state: state)
    }

    public func exchange(code: String, verifier: String, redirectURI: String,
                         state: String? = nil) async throws -> TokenBundle {
        try await perform(previousRefreshToken: "") { host in
            OAuthRequests.exchange(tokenURL: host, config: config,
                                   code: code, verifier: verifier, state: state,
                                   redirectURI: redirectURI)
        }
    }

    public func refresh(_ bundle: TokenBundle) async throws -> TokenBundle {
        try await perform(previousRefreshToken: bundle.refreshToken) { host in
            OAuthRequests.refresh(tokenURL: host, config: config,
                                  refreshToken: bundle.refreshToken)
        }
    }

    private func perform(previousRefreshToken: String,
                         _ build: (URL) -> URLRequest) async throws -> TokenBundle {
        var lastError: OAuthError = .allHostsFailed
        for host in endpoints.tokenHosts {
            let resp: HTTPResponse
            do { resp = try await http.send(build(host)) }
            catch { lastError = .allHostsFailed; continue }

            switch resp.status {
            case 200:
                do {
                    let tr = try JSONDecoder().decode(TokenResponse.self, from: resp.body)
                    return tr.bundle(now: clock.now(), previousRefreshToken: previousRefreshToken)
                } catch { throw OAuthError.decoding }
            case 400:
                // RFC 6749 §5.2 puts `invalid_request`, `invalid_client` and
                // `unsupported_grant_type` on the same 400 as `invalid_grant`. Only the
                // last one means the grant itself is gone; reading every 400 as a dead
                // grant signs the user out over a refusal they could have waited out.
                if Self.errorCode(resp.body) == "invalid_grant" {
                    throw OAuthError.invalidGrant   // don't retry other host on bad grant
                }
                lastError = .http(400)
            default:
                lastError = .http(resp.status)   // try next host
            }
        }
        throw lastError
    }

    /// The `error` field of an OAuth error response, or nil when the body carries none.
    /// A body we can't read is deliberately *not* treated as a dead grant.
    static func errorCode(_ body: Data) -> String? {
        struct ErrorBody: Decodable { let error: String? }
        if let code = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error {
            return code
        }
        // Some gateways wrap the OAuth error; a body that names invalid_grant at all is
        // still a dead grant. An empty or unreadable body names nothing and is retried.
        if let text = String(data: body, encoding: .utf8), text.contains("invalid_grant") {
            return "invalid_grant"
        }
        return nil
    }
}
