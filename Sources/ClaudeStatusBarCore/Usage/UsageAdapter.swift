// Sources/ClaudeStatusBarCore/Usage/UsageAdapter.swift
import Foundation

public enum UsageAdapterError: Error, Equatable { case missingCoreWindows }

public enum UsageAdapter {
    public static func label(forKey key: String) -> String {
        switch key {
        case "five_hour": return "Session"
        case "seven_day": return "Week (all)"
        default:
            if key.hasPrefix("seven_day_") {
                let model = String(key.dropFirst("seven_day_".count))
                let titled = model.split(separator: "_")
                    .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                    .joined(separator: " ")
                return "Week (\(titled))"
            }
            return key
        }
    }

    public static func normalize(_ dto: UsageResponseDTO,
                                 fetchedAt: Date) throws -> UsageSnapshot {
        func window(_ key: String) -> UsageWindow? {
            guard let w = dto.windows[key] else { return nil }
            return UsageWindow(key: key, label: label(forKey: key),
                               utilization: w.utilization, resetsAt: w.resetsAt)
        }
        guard let session = window("five_hour"),
              let weekAll = window("seven_day") else {
            throw UsageAdapterError.missingCoreWindows
        }
        let premium = dto.windows.keys
            .filter { $0.hasPrefix("seven_day_") }
            .sorted()
            .compactMap { window($0) }
        return UsageSnapshot(session: session, weekAll: weekAll,
                             weekPremium: premium, fetchedAt: fetchedAt)
    }
}
