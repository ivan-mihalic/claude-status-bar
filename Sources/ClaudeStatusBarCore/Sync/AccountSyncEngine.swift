// Sources/ClaudeStatusBarCore/Sync/AccountSyncEngine.swift
import Foundation

public enum SyncOutcome: Equatable {
    case success(UsageSnapshot)
    case needsReauth
    /// The server refused for capacity/permission reasons (429 or 403), carrying its
    /// requested wait when it sent one. Recoverable on its own — never a sign-in prompt.
    case rateLimited(retryAfter: TimeInterval?)
    case offline
    case failed(String)
}

public struct AccountSyncEngine {
    private let tokenStore: TokenStore
    private let oauth: OAuthClient
    private let usage: UsageAPIClient
    private let clock: Clock
    private let refreshWindow: TimeInterval

    public init(tokenStore: TokenStore, oauth: OAuthClient,
                usage: UsageAPIClient, clock: Clock,
                refreshWindow: TimeInterval = 300) {
        self.tokenStore = tokenStore; self.oauth = oauth
        self.usage = usage; self.clock = clock; self.refreshWindow = refreshWindow
    }

    public func syncOnce(accountID: UUID) async -> SyncOutcome {
        guard let bundle0 = try? tokenStore.load(accountID) else {
            return .needsReauth
        }
        // Proactive refresh if near expiry.
        var bundle = bundle0
        if bundle.isExpiring(within: refreshWindow, now: clock.now()) {
            switch await refresh(bundle, for: accountID) {
            case .refreshed(let r): bundle = r
            case .rejected:         return .needsReauth
            case .unreachable:      return .offline
            }
        }
        // Fetch usage; on 401 — and only on 401 — try exactly one reactive refresh.
        do {
            let snap = try await usage.fetch(accessToken: bundle.accessToken,
                                             now: clock.now())
            return .success(snap)
        } catch let e as UsageAPIError {
            if case .unauthorized = e {
                switch await refresh(bundle, for: accountID) {
                case .refreshed(let refreshed):
                    do {
                        let snap = try await usage.fetch(
                            accessToken: refreshed.accessToken, now: clock.now())
                        return .success(snap)
                    } catch let retryError {
                        // A fresh token that still can't read usage is only a sign-in
                        // problem if the server says *unauthorized* again. Anything else
                        // — a limit, a refusal, a 500 — must keep its own meaning, or
                        // running out of quota shows up as "sign in again".
                        return outcome(for: retryError, fallback: .needsReauth)
                    }
                case .rejected:    return .needsReauth
                case .unreachable: return .offline
                }
            }
            return outcome(for: e, fallback: .offline)
        } catch {
            return .offline   // network/URLError
        }
    }

    /// Maps a usage-fetch failure to its outcome. `fallback` covers a repeat 401.
    private func outcome(for error: Error, fallback: SyncOutcome) -> SyncOutcome {
        guard let e = error as? UsageAPIError else { return .offline }
        switch e {
        case .rateLimited(let retryAfter): return .rateLimited(retryAfter: retryAfter)
        // 403 is a refusal, not a bad token; treat it as a temporary block so the app
        // keeps retrying on its own instead of demanding credentials it already has.
        case .forbidden:                   return .rateLimited(retryAfter: nil)
        case .server:                      return .offline
        case .decoding:                    return .failed("decoding")
        case .unauthorized:                return fallback
        }
    }

    private enum RefreshResult {
        case refreshed(TokenBundle)
        /// The grant itself is gone (`invalid_grant`) — re-authentication really is needed.
        case rejected
        /// Couldn't reach the token host, or it failed transiently. The stored grant is
        /// probably fine, so this must not burn the account's sign-in state.
        case unreachable
    }

    private func refresh(_ bundle: TokenBundle, for id: UUID) async -> RefreshResult {
        do {
            let refreshed = try await oauth.refresh(bundle)
            try? tokenStore.save(refreshed, for: id)
            return .refreshed(refreshed)
        } catch OAuthError.invalidGrant {
            return .rejected
        } catch {
            return .unreachable
        }
    }
}
