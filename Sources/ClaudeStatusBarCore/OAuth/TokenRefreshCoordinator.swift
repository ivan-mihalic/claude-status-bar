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
        /// Úložiště nelze přečíst nebo do něj zapsat; nejde o zaniklý grant.
        case storeFailed(String)
    }

    private let oauth: OAuthClient
    private let store: TokenStore
    private var inFlight: [UUID: Task<TokenBundle, Error>] = [:]
    /// Tokens the server has already rotated but the store refused to keep. Held so the
    /// next attempt presents the *new* refresh token (the old one is spent) and retries
    /// the write, instead of walking into `invalid_grant`.
    private var unpersisted: [UUID: (previous: TokenBundle, refreshed: TokenBundle)] = [:]

    public init(oauth: OAuthClient, store: TokenStore) {
        self.oauth = oauth; self.store = store
    }

    /// The account's current bundle: whatever the store holds, unless a newer one is
    /// still waiting to be written.
    public func current(_ id: UUID) throws -> TokenBundle? {
        if let pending = unpersisted[id] {
            do { return try commit(pending.refreshed, for: id, matching: pending.previous) }
            catch Failure.rejected { return nil }
            catch { throw Failure.storeFailed("couldn't save the refreshed token") }
        }
        do { return try store.load(id) }
        catch {
            // Chyba přístupu není důkaz, že token chybí. Zpráva nikdy neobsahuje
            // popis libovolné chyby úložiště, který by mohl obsahovat token.
            let detail: String
            if case KeychainError.status(let status) = error {
                detail = " (Keychain status \(status))"
            } else {
                detail = ""
            }
            throw Failure.storeFailed("couldn't read stored credentials" + detail)
        }
    }

    /// Refreshes `stale`, coalescing concurrent callers onto one round trip.
    public func refresh(_ stale: TokenBundle, for id: UUID) async throws -> TokenBundle {
        if let running = inFlight[id] {
            return try await running.value      // join; never spend the token twice
        }
        // Someone finished a refresh while this caller was still holding an old bundle.
        if let fresh = try current(id), fresh != stale {
            return fresh
        }
        let task = Task<TokenBundle, Error> {
            try await self.performRefresh(stale, for: id)
        }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        return try await task.value
    }

    private func performRefresh(_ stale: TokenBundle, for id: UUID) async throws -> TokenBundle {
        let refreshed: TokenBundle
        do { refreshed = try await oauth.refresh(stale) }
        catch {
            let current: TokenBundle?
            do { current = try store.load(id) }
            catch { throw Failure.storeFailed("couldn't read stored credentials after refresh") }
            if let current, current != stale { return current }
            if error as? OAuthError == .invalidGrant { throw Failure.rejected }
            throw Failure.unreachable
        }

        do { return try commit(refreshed, for: id, matching: stale) }
        catch Failure.rejected { throw Failure.rejected }
        catch {
            unpersisted[id] = (stale, refreshed)
            throw Failure.storeFailed("couldn't save the refreshed token")
        }
    }

    private func commit(_ bundle: TokenBundle, for id: UUID,
                        matching previous: TokenBundle) throws -> TokenBundle {
        if try store.replace(bundle, for: id, matching: previous) {
            unpersisted[id] = nil
            return bundle
        }
        // Atomické přepsání selhalo kvůli novému importu nebo odstranění účtu.
        let current = try store.load(id)
        unpersisted[id] = nil
        guard let current else { throw Failure.rejected }
        return current
    }
}
