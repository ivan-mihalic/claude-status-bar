// Sources/ClaudeStatusBarApp/Environment/EnergyMonitor.swift
import AppKit
import IOKit.ps
import ClaudeStatusBarCore

/// Watches the three machine conditions that change how hard this app may work, and reports
/// them as an `EnergyConditions`.
///
/// Every reader is injectable. A check that asks the runtime about itself cannot be tested,
/// and this one decides whether the app syncs at all — so the plumbing lives here and the
/// decisions live in `EnergyPolicy`, where they can be asserted.
@MainActor
public final class EnergyMonitor {
    public private(set) var conditions = EnergyConditions()
    /// Fires only when something actually changed.
    public var onChange: ((EnergyConditions) -> Void)?

    private let isLowPower: () -> Bool
    private let isOnBattery: () -> Bool
    private var observers: [any NSObjectProtocol] = []
    private var powerSource: CFRunLoopSource?
    private var screensAsleep = false

    public init(isLowPower: @escaping () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
                isOnBattery: @escaping () -> Bool = EnergyMonitor.readOnBattery) {
        self.isLowPower = isLowPower
        self.isOnBattery = isOnBattery
    }

    /// Whether the Mac is running off its battery right now.
    ///
    /// `nonisolated` so it can serve as a default argument: IOKit needs no main thread, and
    /// a `@MainActor` default would silently strip its isolation at the call site.
    public nonisolated static func readOnBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(blob)?.takeRetainedValue() as String?
        else { return false }
        return type == kIOPSBatteryPowerValue
    }

    public func start() {
        // Low Power Mode is the user saying "spend less" out loud.
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })

        let workspace = NSWorkspace.shared.notificationCenter
        for (name, asleep) in [(NSWorkspace.screensDidSleepNotification, true),
                               (NSWorkspace.screensDidWakeNotification, false)] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    self?.screensAsleep = asleep
                    self?.refresh()
                }
            })
        }

        // Plugging in or unplugging arrives as an IOKit power-source notification; polling for
        // it would be exactly the kind of timer this whole change is removing.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<EnergyMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }

        refresh()
    }

    /// Must be called by the owner. Deliberately not a `deinit`: this class is `@MainActor`
    /// but `deinit` is not, so tearing the observers down there would mean asserting an
    /// isolation that is not guaranteed — a crash waiting for the one release that happens
    /// off the main thread. The monitor lives as long as the app does, so there is nothing
    /// to reclaim in practice.
    public func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
        }
        powerSource = nil
    }

    /// Re-reads everything and publishes the result if it moved. Public so a test can drive
    /// it without a real notification.
    public func refresh() {
        let next = EnergyConditions(lowPowerMode: isLowPower(),
                                    onBattery: isOnBattery(),
                                    screenAsleep: screensAsleep)
        guard next != conditions else { return }
        conditions = next
        onChange?(next)
    }

    /// Test seam for the one input that has no injectable reader: screen sleep arrives as a
    /// workspace notification, not as a value anyone can ask for.
    public func setScreensAsleepForTesting(_ asleep: Bool) {
        screensAsleep = asleep
        refresh()
    }
}
