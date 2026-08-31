// Sources/ClaudeStatusBarApp/Accounts/AccountManager.swift
import Foundation
import ClaudeStatusBarCore

public enum AccountError: Error, Equatable {
    /// Re-authentication was asked for an account that is no longer in the list
    /// (e.g. it was deleted in another window while the browser round-trip was open).
    case unknownAccount
}

@MainActor
public final class AccountManager {
    private let appState: AppState
    private let login: OAuthLoginService
    private let tokenStore: TokenStore
    private let snapshotStore: SnapshotStore

    public init(appState: AppState, login: OAuthLoginService, tokenStore: TokenStore,
                snapshotStore: SnapshotStore) {
        self.appState = appState; self.login = login; self.tokenStore = tokenStore
        self.snapshotStore = snapshotStore
    }

    /// Opens the browser and returns the pending PKCE login. Used both when adding a
    /// new account and when re-authenticating an existing one — the flow is identical
    /// up to the point where the exchanged token is filed under an account id.
    public func beginLogin() -> PendingLogin { login.begin() }

    public func finishAdd(_ pending: PendingLogin, code: String, label: String,
                          interval: Int = Account.intervalDefault) async throws -> Account {
        let id = UUID()
        _ = try await login.complete(pending, code: code, accountID: id)
        let account = Account(id: id, label: label, accountUuid: nil,
                              syncInterval: max(60, interval), status: .never,
                              lastSnapshot: nil, lastSyncedAt: nil)
        appState.upsert(account)
        persist()
        return account
    }

    /// Re-signs in to an account that already exists: the new token replaces the old
    /// one under the *same* account id, so the tile keeps its name, menu-bar prefix,
    /// interval and position instead of a duplicate appearing next to it.
    public func reauth(_ id: UUID, _ pending: PendingLogin, code: String) async throws {
        guard appState.accounts.contains(where: { $0.id == id }) else {
            throw AccountError.unknownAccount
        }
        _ = try await login.complete(pending, code: code, accountID: id)
        // Re-read after the await — the account may have been removed meanwhile.
        guard var account = appState.accounts.first(where: { $0.id == id }) else {
            try? tokenStore.delete(id)
            throw AccountError.unknownAccount
        }
        account.status = .never          // "syncing…" until the first fetch lands
        appState.upsert(account)
        persist()
    }

    public func remove(_ id: UUID) {
        do { try tokenStore.delete(id) }
        catch { appState.report("Couldn't delete stored credentials: \(error)") }
        appState.remove(id)
        persist()
    }

    /// Moves a tile one slot up (-1) or down (+1) and persists the new order.
    public func move(_ id: UUID, by offset: Int) {
        guard appState.move(id, by: offset) else { return }
        persist()
    }

    public func setInterval(_ id: UUID, seconds: Int) {
        guard var a = appState.accounts.first(where: { $0.id == id }) else { return }
        a.syncInterval = seconds
        appState.upsert(a)
        persist()
    }

    public func setPrefix(_ id: UUID, _ prefix: String) {
        guard var a = appState.accounts.first(where: { $0.id == id }) else { return }
        a.menuBarPrefix = prefix.isEmpty ? nil : prefix
        appState.upsert(a)
        persist()
    }

    /// Show or hide this account's ring in the notch panel. The account keeps syncing either
    /// way — this is about the panel being readable, not about pausing an account.
    public func setShownInNotch(_ id: UUID, _ shown: Bool) {
        guard var a = appState.accounts.first(where: { $0.id == id }) else { return }
        a.showInNotch = shown
        appState.upsert(a)
        persist()
    }

    /// Show or hide this account's percentages in the menu-bar label. It keeps syncing and
    /// still drives the gauge icon either way.
    public func setShownInMenuBar(_ id: UUID, _ shown: Bool) {
        guard var a = appState.accounts.first(where: { $0.id == id }) else { return }
        a.showInMenuBar = shown
        appState.upsert(a)
        persist()
    }

    public func setLabel(_ id: UUID, _ label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var a = appState.accounts.first(where: { $0.id == id }) else { return }
        a.label = trimmed
        appState.upsert(a)
        persist()
    }

    private func persist() {
        do { try snapshotStore.save(appState.accounts) }
        catch { appState.report("Couldn't save accounts: \(error)") }
    }
}
