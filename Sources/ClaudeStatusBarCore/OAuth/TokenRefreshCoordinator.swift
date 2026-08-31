// Sources/ClaudeStatusBarCore/OAuth/TokenRefreshCoordinator.swift
import Foundation

/// Owns every refresh of an account's grant.
///
/// The server rotates the refresh token: presenting the same one twice answers
/// `invalid_grant`, which the app can only read as "sign in again". Two syncs of one
/// account overlap routinely — a poll and a manual Sync, or every account's timer firing
/// at once when the Mac wakes — so without a single owner the second one presents a token
/// the first has already spent and the account is signed out while its grant is alive.
public actor TokenRefreshCoordinator {
    public enum Failure: Error, Equatable {
        /// `invalid_grant` — the grant really is gone.
        case rejected
        /// Network trouble or a transient refusal. The stored grant is presumably fine.
        case unreachable
        /// Refreshed, but the new token could not be persisted.
        case storeFailed(String)
    }

    private let oauth: OAuthClient
    private let store: TokenStore
    private var inFlight: [UUID: Task<TokenBundle, Error>] = [:]
    /// Tokens the server has already rotated but the store refused to keep. Held so the
    /// next attempt presents the *new* refresh token (the old one is spent) and retries
    /// the write, instead of walking into `invalid_grant`.
    private var unpersisted: [UUID: TokenBundle] = [:]

    public init(oauth: OAuthClient, store: TokenStore) {
        self.oauth = oauth; self.store = store
    }

    /// The account's current bundle: whatever the store holds, unless a newer one is
    /// still waiting to be written.
    public func current(_ id: UUID) -> TokenBundle? {
        if let pending = unpersisted[id] {
            persist(pending, for: id)
            return pending
        }
        return try? store.load(id)
    }

    /// Refreshes `stale`, coalescing concurrent callers onto one round trip.
    public func refresh(_ stale: TokenBundle, for id: UUID) async throws -> TokenBundle {
        if let running = inFlight[id] {
            return try await running.value      // join; never spend the token twice
        }
        // Someone finished a refresh while this caller was still holding an old bundle.
        if let fresh = current(id), fresh.accessToken != stale.accessToken {
            return fresh
        }
        let task = Task<TokenBundle, Error> { [oauth] in
            do { return try await oauth.refresh(stale) }
            catch OAuthError.invalidGrant { throw Failure.rejected }
            catch { throw Failure.unreachable }
        }
        inFlight[id] = task
        defer { inFlight[id] = nil }

        let refreshed = try await task.value
        guard persist(refreshed, for: id) else {
            unpersisted[id] = refreshed
            throw Failure.storeFailed("couldn't save the refreshed token")
        }
        return refreshed
    }

    @discardableResult
    private func persist(_ bundle: TokenBundle, for id: UUID) -> Bool {
        do {
            try store.save(bundle, for: id)
            unpersisted[id] = nil
            return true
        } catch {
            return false
        }
    }
}
