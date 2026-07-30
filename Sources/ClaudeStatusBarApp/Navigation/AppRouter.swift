// Sources/ClaudeStatusBarApp/Navigation/AppRouter.swift
import Foundation
import Observation

/// Drives the single app window's sidebar navigation. Shared between the window's
/// `RootView` and the menu-bar popover so every action (from the widget or from any
/// screen's sidebar) just changes `selection` — the app only ever shows one window.
@MainActor
@Observable
public final class AppRouter {
    public enum Section: String, Hashable, CaseIterable, Identifiable {
        case dashboard, addAccount, settings, about
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .addAccount: "Add Account"
            case .settings: "Settings"
            case .about: "About"
            }
        }
        public var systemImage: String {
            switch self {
            case .dashboard: "gauge.medium"
            case .addAccount: "plus.circle"
            case .settings: "gearshape"
            case .about: "info.circle"
            }
        }
    }

    public var selection: Section = .dashboard

    /// While non-nil (and `selection == .addAccount`), the Add Account screen re-signs
    /// in to this existing account instead of creating a new one. Any plain navigation
    /// clears it, so "Add Account…" always means *add*.
    public private(set) var reauthTarget: UUID?

    /// Navigate to a section as a fresh, non-reauth destination.
    public func show(_ section: Section) {
        reauthTarget = nil
        selection = section
    }

    /// Open the sign-in screen bound to an account that already exists.
    public func showReauth(_ id: UUID) {
        reauthTarget = id
        selection = .addAccount
    }

    public init() {}
}
