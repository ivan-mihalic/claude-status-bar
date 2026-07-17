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
        try await perform(previousRefreshToken: "") { host in
            OAuthRequests.exchange(tokenURL: host, config: config,
                                   code: code, verifier: verifier, state: state)
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
                throw OAuthError.invalidGrant   // don't retry other host on bad grant
            default:
                lastError = .http(resp.status)   // try next host
            }
        }
        throw lastError
    }
}
