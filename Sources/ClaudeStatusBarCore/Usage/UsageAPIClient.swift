// Sources/ClaudeStatusBarCore/Usage/UsageAPIClient.swift
import Foundation

public enum UsageAPIError: Error, Equatable {
    case unauthorized, rateLimited, server(Int), decoding
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
        case 401, 403: throw UsageAPIError.unauthorized
        case 429:      throw UsageAPIError.rateLimited
        default:       throw UsageAPIError.server(resp.status)
        }
    }
}
