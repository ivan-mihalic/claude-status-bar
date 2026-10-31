// Sources/ClaudeStatusBarCore/Usage/AntigravityUsage.swift
import Foundation

/// The part of `POST /v1internal:fetchAvailableModels` that carries quota.
///
/// Google reports quota per model as the fraction still *remaining*, with the moment it
/// refills. Shape verified on 2026-10-31 against opencode-antigravity-auth
/// (src/plugin/quota.ts); every field is optional because the endpoint is internal and
/// unrelated catalogue entries (tab completion, chat) come back without quota.
public struct AntigravityModelsDTO: Decodable, Sendable {
    public struct QuotaInfo: Decodable, Sendable {
        public let remainingFraction: Double?
        public let resetTime: String?
    }

    public struct Model: Decodable, Sendable {
        public let displayName: String?
        public let disabled: Bool?
        public let quotaInfo: QuotaInfo?
    }

    public let models: [String: Model]?
}

public enum AntigravityUsageAdapter {
    /// Antigravity pools quota by model family, not by time window, so the families stand in
    /// for the windows: Claude in the session slot, Gemini Pro as the
    /// main window and Gemini Flash as the extra one. Every view then shows all three.
    public enum Group: String, CaseIterable, Sendable {
        case claude, geminiPro, geminiFlash

        public var key: String {
            switch self {
            case .claude: return "antigravity_claude"
            case .geminiPro: return "antigravity_gemini_pro"
            case .geminiFlash: return "antigravity_gemini_flash"
            }
        }

        public var label: String {
            switch self {
            case .claude: return "Claude"
            case .geminiPro: return "Gemini Pro"
            case .geminiFlash: return "Gemini Flash"
            }
        }
    }

    public static func group(model: String, displayName: String?) -> Group? {
        let name = "\(model) \(displayName ?? "")".lowercased()
        if name.contains("claude") { return .claude }
        guard name.contains("gemini") else { return nil }
        return name.contains("flash") ? .geminiFlash : .geminiPro
    }

    public static func normalize(_ dto: AntigravityModelsDTO,
                                 fetchedAt: Date) throws -> UsageSnapshot {
        var worst: [Group: (used: Double, resets: Date)] = [:]
        for (name, model) in dto.models ?? [:] {
            guard model.disabled != true,
                  let quota = model.quotaInfo,
                  let group = group(model: name, displayName: model.displayName) else { continue }
            // Missing fraction = exhausted: Google drops the field once a model hits zero.
            let remaining = min(max(quota.remainingFraction ?? 0, 0), 1)
            let used = (1 - remaining) * 100
            let resets = quota.resetTime.flatMap(parseDate) ?? fetchedAt
            if let current = worst[group], current.used >= used { continue }
            worst[group] = (used, resets)
        }
        guard !worst.isEmpty else { throw UsageAdapterError.missingCoreWindows }

        func window(_ group: Group) -> UsageWindow? {
            worst[group].map {
                UsageWindow(key: group.key, label: group.label,
                            utilization: $0.used, resetsAt: $0.resets)
            }
        }
        return UsageSnapshot(session: window(.claude),
                             weekAll: window(.geminiPro),
                             weekPremium: [window(.geminiFlash)].compactMap { $0 },
                             fetchedAt: fetchedAt)
    }

    private static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// Reads Antigravity quota from Google's Cloud Code backend, the same calls the Antigravity
/// app makes: `loadCodeAssist` resolves the account's managed project, then
/// `fetchAvailableModels` returns per-model quota for it.
public struct AntigravityUsageAPIClient: UsageFetching {
    /// The consumer Antigravity app talks to the daily host only; mixing hosts can resolve a
    /// different entitlement.
    public static let host = "https://daily-cloudcode-pa.googleapis.com"
    public static let userAgent =
        "antigravity/hub/2.24.0 (aidev_client; os_type=darwin; arch=arm64; cl=1000335682)"

    private let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    public func fetch(tokens: TokenBundle, now: Date) async throws -> UsageSnapshot {
        let project = try await loadProject(accessToken: tokens.accessToken, now: now)
        var body: [String: String] = [:]
        if let project { body["project"] = project }
        let resp = try await http.send(request("v1internal:fetchAvailableModels",
                                               token: tokens.accessToken, body: body))
        try Self.check(resp, now: now)
        do {
            let dto = try JSONDecoder().decode(AntigravityModelsDTO.self, from: resp.body)
            return try AntigravityUsageAdapter.normalize(dto, fetchedAt: now)
        } catch { throw UsageAPIError.decoding }
    }

    /// The managed project, or nil when Google assigns none (some Workspace accounts) —
    /// `fetchAvailableModels` then answers for the caller's default.
    private func loadProject(accessToken: String, now: Date) async throws -> String? {
        let resp = try await http.send(request("v1internal:loadCodeAssist", token: accessToken,
                                               body: ["metadata": ["ideType": "ANTIGRAVITY"]]))
        try Self.check(resp, now: now)
        guard let root = try? JSONSerialization.jsonObject(with: resp.body) as? [String: Any]
        else { return nil }
        let value = root["cloudaicompanionProject"]
        let id = (value as? String) ?? ((value as? [String: Any])?["id"] as? String)
        return id.flatMap { $0.isEmpty ? nil : $0 }
    }

    private func request(_ method: String, token: String, body: [String: Any]) -> URLRequest {
        var req = URLRequest(url: URL(string: "\(Self.host)/\(method)")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    private static func check(_ resp: HTTPResponse, now: Date) throws {
        switch resp.status {
        case 200: return
        case 401: throw UsageAPIError.unauthorized
        case 403: throw UsageAPIError.forbidden
        case 429: throw UsageAPIError.rateLimited(
            retryAfter: RetryAfter.seconds(from: resp.headers, now: now))
        default:  throw UsageAPIError.server(resp.status)
        }
    }
}
