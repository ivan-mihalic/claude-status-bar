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

/// One provider's half of a sync: who refreshes its grant, and where its numbers come from.
///
/// Bundled together because they must match — refreshing a ChatGPT grant against Anthropic's
/// token host would fail in a way that reads as "sign in again", which is the most damaging
/// wrong answer this app can give.
public struct ProviderBackend: Sendable {
    public let tokens: TokenRefreshCoordinator
    public let usage: any UsageFetching

    public init(tokens: TokenRefreshCoordinator, usage: any UsageFetching) {
        self.tokens = tokens; self.usage = usage
    }

    public init(tokenStore: TokenStore, oauth: OAuthClient, usage: any UsageFetching) {
        self.init(tokens: TokenRefreshCoordinator(oauth: oauth, store: tokenStore), usage: usage)
    }
}

public struct AccountSyncEngine {
    private let backends: [Provider: ProviderBackend]
    private let clock: Clock
    private let refreshWindow: TimeInterval

    public init(backends: [Provider: ProviderBackend], clock: Clock,
                refreshWindow: TimeInterval = 300) {
        self.backends = backends; self.clock = clock; self.refreshWindow = refreshWindow
    }

    public init(tokenStore: TokenStore, oauth: OAuthClient,
                usage: UsageAPIClient, clock: Clock,
                refreshWindow: TimeInterval = 300) {
        self.init(tokens: TokenRefreshCoordinator(oauth: oauth, store: tokenStore),
                  usage: usage, clock: clock, refreshWindow: refreshWindow)
    }

    public init(tokens: TokenRefreshCoordinator, usage: UsageAPIClient,
                clock: Clock, refreshWindow: TimeInterval = 300) {
        self.init(backends: [.claude: ProviderBackend(tokens: tokens, usage: usage)],
                  clock: clock, refreshWindow: refreshWindow)
    }

    public func syncOnce(accountID: UUID, provider: Provider = .claude) async -> SyncOutcome {
        // A provider with no backend is a configuration mistake, not a signed-out account:
        // saying "sign in again" would send the user round a loop that cannot succeed.
        guard let backend = backends[provider] else {
            return .failed("No usage client configured for \(provider.title)")
        }
        let tokens = backend.tokens
        let usage = backend.usage
        guard let bundle0 = await tokens.current(accountID) else {
            return .needsReauth
        }
        // Proactive refresh if near expiry.
        var bundle = bundle0
        if bundle.isExpiring(within: refreshWindow, now: clock.now()) {
            switch await refresh(bundle, for: accountID, tokens: tokens) {
            case .refreshed(let r):     bundle = r
            case .rejected:             return .needsReauth
            case .unreachable:          return .offline
            case .storeFailed(let why): return .failed(why)
            }
        }
        // Fetch usage; on 401 — and only on 401 — try exactly one reactive refresh.
        do {
            let snap = try await usage.fetch(accessToken: bundle.accessToken,
                                             now: clock.now())
            return .success(snap)
        } catch let e as UsageAPIError {
            if case .unauthorized = e {
                switch await refresh(bundle, for: accountID, tokens: tokens) {
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
                case .rejected:             return .needsReauth
                case .unreachable:          return .offline
                case .storeFailed(let why): return .failed(why)
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
        /// Refreshed, but the rotated token couldn't be stored. Reported rather than
        /// swallowed: a lost rotation shows up days later as an unexplained sign-out.
        case storeFailed(String)
    }

    private func refresh(_ bundle: TokenBundle, for id: UUID,
                         tokens: TokenRefreshCoordinator) async -> RefreshResult {
        do {
            return .refreshed(try await tokens.refresh(bundle, for: id))
        } catch TokenRefreshCoordinator.Failure.rejected {
            return .rejected
        } catch TokenRefreshCoordinator.Failure.storeFailed(let why) {
            return .storeFailed(why)
        } catch {
            return .unreachable
        }
    }
}
