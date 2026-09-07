// Sources/ClaudeStatusBarCore/Usage/UsageFetching.swift
import Foundation

/// One provider's usage endpoint, reduced to the only thing the sync engine needs from it.
///
/// The engine stays provider-agnostic on purpose: every provider ends up as the same
/// `UsageSnapshot`, so the dashboard, the menu bar and the notch never learn that a second
/// service exists.
public protocol UsageFetching: Sendable {
    func fetch(tokens: TokenBundle, now: Date) async throws -> UsageSnapshot
}

extension UsageAPIClient: UsageFetching {
    public func fetch(tokens: TokenBundle, now: Date) async throws -> UsageSnapshot {
        try await fetch(accessToken: tokens.accessToken, now: now)
    }
}

/// `GET https://chatgpt.com/backend-api/wham/usage` — the endpoint Codex CLI reads its own
/// `/status` limits from. Verified live on 2026-08-31 (200 with a Plus account's windows);
/// the sibling path `/backend-api/api/codex/usage` answers 403 and is not used.
public struct CodexUsageAPIClient: UsageFetching {
    public static let endpoint =
        URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    private let http: HTTPClient
    private let userAgent: String

    public init(http: HTTPClient, userAgent: String = "codex-cli") {
        self.http = http; self.userAgent = userAgent
    }

    public func fetch(tokens: TokenBundle, now: Date) async throws -> UsageSnapshot {
        try await fetch(accessToken: tokens.accessToken, accountID: tokens.accountID, now: now)
    }

    public func fetch(accessToken: String, now: Date) async throws -> UsageSnapshot {
        try await fetch(accessToken: accessToken, accountID: nil, now: now)
    }

    private func fetch(accessToken: String, accountID: String?,
                       now: Date) async throws -> UsageSnapshot {
        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = accountID ?? ChatGPTTokenClaims.accountID(from: accessToken) {
            req.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let resp = try await http.send(req)
        switch resp.status {
        case 200:
            do {
                let dto = try JSONDecoder().decode(CodexUsageDTO.self, from: resp.body)
                return try CodexUsageAdapter.normalize(dto, fetchedAt: now)
            } catch { throw UsageAPIError.decoding }
        case 401: throw UsageAPIError.unauthorized
        // ChatGPT answers 403 with an HTML block page for a wrong path or a blocked client.
        // Same meaning as Anthropic's refusal: not a credential problem, so never a sign-in
        // prompt.
        case 403: throw UsageAPIError.forbidden
        case 429: throw UsageAPIError.rateLimited(
            retryAfter: RetryAfter.seconds(from: resp.headers, now: now))
        default:  throw UsageAPIError.server(resp.status)
        }
    }
}
