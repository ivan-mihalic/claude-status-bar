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
    public let energyMonitor = EnergyMonitor()
    /// Set by the scene so the notch panel can react to the same conditions the sync loop
    /// does — it has to come from up there, because the panel controller lives in the scene.
    public var onEnergyConditionsChanged: ((EnergyConditions) -> Void)?

    private let snapshotStore: SnapshotStore

    public init() {
        let http = URLSessionHTTPClient()
        let clock = SystemClock()
        let tokenStore = KeychainTokenStore(service: "cz.mihalic.claude-status-bar.tokens")
        let snapStore = SnapshotStore(fileURL: SnapshotStore.defaultURL())
        self.snapshotStore = snapStore

        // One OAuth client per provider: each has its own token host and client id, and
        // refreshing a grant against the wrong host fails in the one way that reads as
        // "sign in again".
        let anthropic = OAuthClient(http: http, endpoints: .production,
                                    config: .claudeCode, clock: clock)
        let openAI = OAuthClient(http: http, endpoints: .openAI, config: .codex, clock: clock)

        let login = OAuthLoginService(
            backends: [
                .claude: LoginBackend(oauth: anthropic, endpoints: .production, config: .claudeCode),
                .codex:  LoginBackend(
                    oauth: openAI, endpoints: .openAI, config: .codex,
                    deviceCode: DeviceCodeAuthClient(http: http, oauth: openAI, config: .codex)),
            ],
            tokenStore: tokenStore, opener: SystemBrowserOpener())

        self.accountManager = AccountManager(appState: appState, login: login, tokenStore: tokenStore,
                                             snapshotStore: snapStore)
        self.syncCoordinator = SyncCoordinator(
            appState: appState,
            engine: AccountSyncEngine(
                backends: [
                    .claude: ProviderBackend(tokenStore: tokenStore, oauth: anthropic,
                                             usage: UsageAPIClient(http: http)),
                    .codex:  ProviderBackend(tokenStore: tokenStore, oauth: openAI,
                                             usage: CodexUsageAPIClient(http: http)),
                ],
                clock: clock),
            clock: clock, snapshotStore: snapStore)
    }

    public func bootstrap() {
        do { (try snapshotStore.load()).forEach { appState.upsert($0) } }
        catch { appState.report("Couldn't load saved accounts: \(error)") }
        energyMonitor.onChange = { [weak self] conditions in
            guard let self else { return }
            self.syncCoordinator.updateConditions(conditions)
            self.onEnergyConditionsChanged?(conditions)
        }
        energyMonitor.start()
        syncCoordinator.updateConditions(energyMonitor.conditions)
        syncCoordinator.start()
    }
}
