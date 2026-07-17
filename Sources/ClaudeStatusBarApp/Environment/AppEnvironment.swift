// Sources/ClaudeStatusBarApp/Environment/AppEnvironment.swift
import Foundation
import Observation
import ClaudeStatusBarCore

@MainActor
@Observable
public final class AppEnvironment {
    public let appState = AppState()
    public let accountManager: AccountManager
    public let syncCoordinator: SyncCoordinator

    private let snapshotStore: SnapshotStore

    public init() {
        let http = URLSessionHTTPClient()
        let clock = SystemClock()
        let tokenStore = KeychainTokenStore(service: "cz.mihalic.claude-status-bar.tokens")
        let snapStore = SnapshotStore(fileURL: SnapshotStore.defaultURL())
        self.snapshotStore = snapStore

        let oauth = OAuthClient(http: http, endpoints: .production, config: .claudeCode, clock: clock)
        let login = OAuthLoginService(oauth: oauth, endpoints: .production, config: .claudeCode,
                                      tokenStore: tokenStore, opener: SystemBrowserOpener())
        let importer = ClaudeCodeImporter(
            secretReader: KeychainSecretReader(),
            fileReader: DiskFileReader(),
            configURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json"))

        self.accountManager = AccountManager(appState: appState, login: login, tokenStore: tokenStore,
                                             snapshotStore: snapStore, importer: importer)
        self.syncCoordinator = SyncCoordinator(
            appState: appState,
            engine: AccountSyncEngine(tokenStore: tokenStore, oauth: oauth,
                                      usage: UsageAPIClient(http: http), clock: clock),
            clock: clock, snapshotStore: snapStore)
    }

    public func bootstrap() {
        if let saved = try? snapshotStore.load() { saved.forEach { appState.upsert($0) } }
        syncCoordinator.start()
    }
}
