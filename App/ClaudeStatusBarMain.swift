// App/ClaudeStatusBarMain.swift
import SwiftUI
import ClaudeStatusBarApp
import Sparkle

@main
struct ClaudeStatusBarMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var env = AppEnvironment()
    @State private var router = AppRouter()
    @AppStorage("menuBarShowAccountPercents") private var showAccountPercents = false
    @AppStorage("showNotchPanel") private var showNotchPanel = false
    @AppStorage("notchPlacement") private var notchPlacement = NotchPlacement.topCenter.rawValue
    @AppStorage("notchEdgeOffsetPercent") private var notchEdgeOffset = 50.0
    @AppStorage("notchExpandOnHover") private var notchExpandOnHover = true
    @AppStorage("notchShowPopover") private var notchShowPopover = true
    @Environment(\.openWindow) private var openWindow
    @State private var notch: NotchWindowController?
    private let updaterUIDelegate = UpdaterUIDelegate()
    private let updaterController: SPUStandardUpdaterController

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(env: env)
                .environment(router)
        } label: {
            let level = MenuBarIndicator.level(maxUtilization: env.appState.maxUtilization)
            Image(systemName: level == .critical ? "gauge.high" : level == .warn ? "gauge.medium" : "gauge.low")
            Text(MenuBarLabel.text(accounts: env.appState.accounts, showAccountPercents: showAccountPercents))
        }
        .menuBarExtraStyle(.window)
        // The notch panel is a second *view* of the same AppState, never a second source of
        // truth, and it is off unless the user asks for it.
        .onChange(of: showNotchPanel, initial: true) { _, on in
            let controller = notch ?? {
                let made = NotchWindowController(env: env)
                notch = made
                return made
            }()
            controller.onOpenDashboard = {
                router.show(.dashboard)
                DockController.shared.prepareToShowWindow()
                openWindow(id: "main")
            }
            controller.setPlacement(NotchPlacement(rawValue: notchPlacement) ?? .topCenter,
                                    edgeOffsetPercent: notchEdgeOffset)
            controller.setBehaviour(expandOnHover: notchExpandOnHover,
                                    showPopover: notchShowPopover)
            controller.setEnabled(on)
        }
        .onChange(of: notchExpandOnHover) { _, _ in
            notch?.setBehaviour(expandOnHover: notchExpandOnHover, showPopover: notchShowPopover)
        }
        .onChange(of: notchShowPopover) { _, _ in
            notch?.setBehaviour(expandOnHover: notchExpandOnHover, showPopover: notchShowPopover)
        }
        // An edge panel is sized from the account count, so the window itself changes when
        // accounts come and go.
        .onChange(of: env.appState.accounts.count) { _, _ in notch?.accountsChanged() }
        .onChange(of: notchPlacement) { _, _ in
            notch?.setPlacement(NotchPlacement(rawValue: notchPlacement) ?? .topCenter,
                                edgeOffsetPercent: notchEdgeOffset)
        }
        .onChange(of: notchEdgeOffset) { _, _ in
            notch?.setPlacement(NotchPlacement(rawValue: notchPlacement) ?? .topCenter,
                                edgeOffsetPercent: notchEdgeOffset)
        }

        // A single window (not a WindowGroup) → at most one app window ever. Its
        // sidebar switches between Dashboard / Add Account / Settings / About, so every
        // action is reachable from any screen, not just the menu-bar popover. Placed
        // after the MenuBarExtra (the primary scene) so this accessory/menu-bar app
        // doesn't auto-present it at launch — it appears only when an action opens it.
        Window("Claude Status Bar", id: "main") {
            RootView(env: env, updater: updaterController.updater)
                .environment(router)
        }
    }

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: updaterUIDelegate)
        env.bootstrap()
    }
}
