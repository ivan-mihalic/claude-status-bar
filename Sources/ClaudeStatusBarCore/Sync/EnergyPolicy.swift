// Sources/ClaudeStatusBarCore/Sync/EnergyPolicy.swift
import Foundation

/// The machine conditions that change how hard this app is allowed to work.
///
/// Passed in rather than read from `ProcessInfo` inside, for the usual reason: a check that
/// asks the runtime about itself cannot be tested, and this one decides whether the app
/// syncs at all.
public struct EnergyConditions: Equatable, Sendable {
    public var lowPowerMode: Bool
    public var onBattery: Bool
    /// The display is asleep or locked — the panel and the menu bar are not being read.
    public var screenAsleep: Bool

    public init(lowPowerMode: Bool = false, onBattery: Bool = false,
                screenAsleep: Bool = false) {
        self.lowPowerMode = lowPowerMode
        self.onBattery = onBattery
        self.screenAsleep = screenAsleep
    }
}

/// What those conditions mean for the two things this app does on its own: fetching numbers
/// and watching the pointer.
public enum EnergyPolicy {
    /// Stretches the sync interval. Low Power Mode is the user saying it out loud, so it
    /// wins outright rather than multiplying with the battery factor — stacking them would
    /// push a quiet account past the point where its numbers are worth anything.
    public static func syncMultiplier(_ c: EnergyConditions) -> Double {
        if c.lowPowerMode { return 3 }
        if c.onBattery { return 2 }
        return 1
    }

    /// Nobody can read a number on a sleeping screen. The loop stops entirely and syncs
    /// once on wake, which is both cheaper and fresher than polling through the night.
    public static func syncPaused(_ c: EnergyConditions) -> Bool { c.screenAsleep }

    /// Hover only means something while someone is looking at the panel.
    public static func hoverTracking(_ c: EnergyConditions) -> Bool { !c.screenAsleep }
}
