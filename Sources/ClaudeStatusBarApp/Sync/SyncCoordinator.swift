// Sources/ClaudeStatusBarApp/Sync/SyncCoordinator.swift
import Foundation
import ClaudeStatusBarCore

@MainActor
public final class SyncCoordinator {
    private let appState: AppState
    private let engine: AccountSyncEngine
    private let clock: Clock
    private let snapshotStore: SnapshotStore
    private var counters: [UUID: Int] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init(appState: AppState, engine: AccountSyncEngine, clock: Clock, snapshotStore: SnapshotStore) {
        self.appState = appState; self.engine = engine; self.clock = clock; self.snapshotStore = snapshotStore
    }

    public func syncNow(_ id: UUID) async {
        guard appState.accounts.contains(where: { $0.id == id }) else { return }
        let outcome = await engine.syncOnce(accountID: id)
        // Re-fetch after the await: the account may have been removed (or its
        // interval changed) while syncOnce was in flight — never resurrect a removed account.
        guard let account = appState.accounts.first(where: { $0.id == id }) else {
            counters[id] = nil
            return
        }
        let reduced = SyncReducer.reduce(
            SyncState(account: account, consecutiveRateLimits: counters[id] ?? 0),
            outcome: outcome, now: clock.now())
        counters[id] = reduced.consecutiveRateLimits
        appState.upsert(reduced.account)
        try? snapshotStore.save(appState.accounts)
    }

    public func nextDelay(for id: UUID, now: Date) -> TimeInterval {
        guard let a = appState.accounts.first(where: { $0.id == id }) else { return 300 }
        return SyncScheduler.nextInterval(base: a.effectiveInterval, status: a.status,
                                          consecutiveRateLimits: counters[id] ?? 0, now: now)
    }

    public func start() {
        stop()
        for (index, account) in appState.accounts.enumerated() {
            let id = account.id
            let stagger = SyncScheduler.staggerOffset(index: index, spacing: 5)
            tasks[id] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(stagger * 1_000_000_000))
                while !Task.isCancelled {
                    await self?.syncNow(id)
                    let delay = self?.nextDelay(for: id, now: self?.clock.now() ?? Date()) ?? 300
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
    }

    public func stop() { tasks.values.forEach { $0.cancel() }; tasks.removeAll() }

    public func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        counters[id] = nil
    }

    deinit { tasks.values.forEach { $0.cancel() } }
}
