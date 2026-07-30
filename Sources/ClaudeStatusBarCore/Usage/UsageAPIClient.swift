// Sources/ClaudeStatusBarCore/Usage/UsageAPIClient.swift
import Foundation

public enum UsageAPIError: Error, Equatable {
    /// 401 — the access token is stale or invalid. The only status worth spending a
    /// token refresh on.
    case unauthorized
    /// 403 — the request was understood and refused (Anthropic's `permission_error`).
    /// A refresh cannot fix it, so it must never be mistaken for a sign-in problem.
    case forbidden
    /// 429 — with the server's requested wait, when it sent one.
    case rateLimited(retryAfter: TimeInterval?)
    case server(Int)
    case decoding
}

public struct UsageAPIClient: Sendable {
    public static let endpoint =
        URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let http: HTTPClient
    private let userAgent: String

    public init(http: HTTPClient, userAgent: String = "claude-code/1.0.0") {
        self.http = http; self.userAgent = userAgent
    }

    public func fetch(accessToken: String, now: Date) async throws -> UsageSnapshot {
        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let resp = try await http.send(req)
        switch resp.status {
        case 200:
            do {
                let dto = try UsageJSON.decoder()
                    .decode(UsageResponseDTO.self, from: resp.body)
                return try UsageAdapter.normalize(dto, fetchedAt: now)
            } catch { throw UsageAPIError.decoding }
        case 401: throw UsageAPIError.unauthorized
        case 403: throw UsageAPIError.forbidden
        case 429: throw UsageAPIError.rateLimited(
            retryAfter: RetryAfter.seconds(from: resp.headers, now: now))
        default:  throw UsageAPIError.server(resp.status)
        }
    }
}
