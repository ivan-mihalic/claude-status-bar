// Sources/ClaudeStatusBarApp/Accounts/AccountManager.swift
import Foundation
import ClaudeStatusBarCore

@MainActor
public final class AccountManager {
    private let appState: AppState
    private let login: OAuthLoginService
    private let tokenStore: TokenStore
    private let snapshotStore: SnapshotStore
    private let importer: ClaudeCodeImporter?

    public init(appState: AppState, login: OAuthLoginService, tokenStore: TokenStore,
                snapshotStore: SnapshotStore, importer: ClaudeCodeImporter?) {
        self.appState = appState; self.login = login; self.tokenStore = tokenStore
        self.snapshotStore = snapshotStore; self.importer = importer
    }

    public func beginAdd(label: String?) -> PendingLogin { login.begin() }

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

    /// Best-effort: detect the email of the account currently logged into Claude Code,
    /// to pre-fill the label. The token itself is NOT used — the app runs its own OAuth.
    public func detectClaudeCodeEmail() -> String? {
        (try? importer?.import())?.email
    }

    public func remove(_ id: UUID) {
        do { try tokenStore.delete(id) }
        catch { appState.report("Couldn't delete stored credentials: \(error)") }
        appState.remove(id)
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
