// Sources/ClaudeStatusBarCore/Sync/AccountSyncEngine.swift
import Foundation

public enum SyncOutcome: Equatable {
    case success(UsageSnapshot)
    case needsReauth
    case rateLimited
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
            case .some(let refreshed): bundle = refreshed
            case .none: return .needsReauth
            }
        }
        // Fetch usage; on unauthorized, try exactly one reactive refresh.
        do {
            let snap = try await usage.fetch(accessToken: bundle.accessToken,
                                             now: clock.now())
            return .success(snap)
        } catch let e as UsageAPIError {
            switch e {
            case .rateLimited: return .rateLimited
            case .server:      return .offline
            case .decoding:    return .failed("decoding")
            case .unauthorized:
                guard let refreshed = await refresh(bundle, for: accountID) else {
                    return .needsReauth
                }
                do {
                    let snap = try await usage.fetch(
                        accessToken: refreshed.accessToken, now: clock.now())
                    return .success(snap)
                } catch { return .needsReauth }
            }
        } catch {
            return .offline   // network/URLError
        }
    }

    private func refresh(_ bundle: TokenBundle, for id: UUID) async -> TokenBundle? {
        do {
            let refreshed = try await oauth.refresh(bundle)
            try? tokenStore.save(refreshed, for: id)
            return refreshed
        } catch { return nil }
    }
}
