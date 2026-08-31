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
    // Per-account sync ordering: `issued` hands out the next sequence number, `applied`
    // remembers the newest one whose result actually landed. The poll loop and a manual
    // Sync click overlap, and without this the request that finishes LAST wins — a stale
    // timeout would write .offline over a newer successful fetch.
    private var issued: [UUID: Int] = [:]
    private var applied: [UUID: Int] = [:]
    /// Machine conditions the poll loop has to respect. Pushed in from the app layer so
    /// this stays testable — see `EnergyPolicy`.
    public private(set) var conditions = EnergyConditions()

    /// Whether the poll loop is alive. Exists so a test can prove that a sleeping screen
    /// really stops it, rather than trusting that it did.
    public var isRunning: Bool { !tasks.isEmpty }

    public init(appState: AppState, engine: AccountSyncEngine, clock: Clock, snapshotStore: SnapshotStore) {
        self.appState = appState; self.engine = engine; self.clock = clock; self.snapshotStore = snapshotStore
    }

    public func syncNow(_ id: UUID) async {
        guard appState.accounts.contains(where: { $0.id == id }) else { return }
        // Claim the sequence number BEFORE the await, so it records when this request
        // started, not when it happened to come back.
        let mySeq = (issued[id] ?? 0) + 1
        issued[id] = mySeq
        // The provider is read before the await: an account edited mid-flight must not have
        // its numbers fetched from the wrong service.
        let provider = appState.accounts.first { $0.id == id }?.effectiveProvider ?? .claude
        let outcome = await engine.syncOnce(accountID: id, provider: provider)
        // Re-fetch after the await: the account may have been removed (or its
        // interval changed) while syncOnce was in flight — never resurrect a removed account.
        guard let account = appState.accounts.first(where: { $0.id == id }) else {
            // Only the newest in-flight request clears the bookkeeping; an older one
            // finishing later would reset the sequence under a request still running.
            if mySeq == issued[id] { counters[id] = nil; issued[id] = nil; applied[id] = nil }
            return
        }
        // A newer sync already landed, so this outcome describes a state that has been
        // superseded — drop it whole, counter included, rather than half-applying it.
        guard mySeq > (applied[id] ?? 0) else { return }
        applied[id] = mySeq
        let reduced = SyncReducer.reduce(
            SyncState(account: account, consecutiveRateLimits: counters[id] ?? 0),
            outcome: outcome, now: clock.now())
        counters[id] = reduced.consecutiveRateLimits
        // A tile reading "offline" hides why. A failure the app caused itself — a token
        // it refreshed but couldn't store — has to be visible, because it is what turns
        // into an unexplained sign-out a few days later.
        if case .failed(let why) = outcome {
            appState.report("\(account.label): \(why)")
        }
        appState.upsert(reduced.account)
        do { try snapshotStore.save(appState.accounts) }
        catch { appState.report("Couldn't save accounts: \(error)") }
    }

    public func nextDelay(for id: UUID, now: Date) -> TimeInterval {
        guard let a = appState.accounts.first(where: { $0.id == id }) else { return 300 }
        return SyncScheduler.nextInterval(
            base: a.effectiveInterval, status: a.status,
            consecutiveRateLimits: counters[id] ?? 0, now: now,
            // An account sitting at 4 % answers the same question for the next half hour;
            // one at 92 % changes minute to minute. The interval follows the number.
            utilization: a.lastSnapshot?.maxUtilization,
            energyMultiplier: EnergyPolicy.syncMultiplier(conditions))
    }

    /// Applies new machine conditions. Only a change that crosses the paused boundary
    /// touches the loop — everything else is picked up by the next `nextDelay`.
    public func updateConditions(_ new: EnergyConditions) {
        guard new != conditions else { return }
        let wasPaused = EnergyPolicy.syncPaused(conditions)
        conditions = new
        let isPaused = EnergyPolicy.syncPaused(new)
        guard isPaused != wasPaused else { return }
        // `start()` syncs before it sleeps, so waking is a fetch, not just a rearmed timer.
        isPaused ? stop() : start()
    }

    public func start() {
        stop()
        // Nothing to poll for while the screen is off; the wake will start this again.
        guard !EnergyPolicy.syncPaused(conditions) else { return }
        for (index, account) in appState.accounts.enumerated() {
            let id = account.id
            let stagger = SyncScheduler.staggerOffset(index: index, spacing: 5)
            tasks[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(stagger), tolerance: .seconds(1))
                while !Task.isCancelled {
                    await self?.syncNow(id)
                    let delay = self?.nextDelay(for: id, now: self?.clock.now() ?? Date()) ?? 300
                    // A tolerance lets macOS fire this alongside whatever else is already
                    // waking the CPU instead of on its own. Apple asks for at least 10 %.
                    try? await Task.sleep(for: .seconds(delay),
                                          tolerance: .seconds(max(delay * 0.1, 1)))
                }
            }
        }
    }

    public func stop() {
        tasks.values.forEach { $0.cancel() }; tasks.removeAll()
        // issued/applied always go together — resetting one without the other would leave
        // every future sync looking older than the last applied result, i.e. ignored forever.
        issued.removeAll(); applied.removeAll()
    }

    public func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        counters[id] = nil
        issued[id] = nil; applied[id] = nil
    }

    deinit { tasks.values.forEach { $0.cancel() } }
}
