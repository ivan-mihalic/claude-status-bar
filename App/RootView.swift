// App/RootView.swift
import SwiftUI
import AppKit
import ClaudeStatusBarApp
import Sparkle

/// The app's single window: a sidebar of destinations on the left, the selected
/// screen on the right. Because it's a `Window` (not a `WindowGroup`) there is only
/// ever one instance; the sidebar makes every action reachable from any screen, so
/// the menu-bar popover is a convenience, not the only entry point.
struct RootView: View {
    @Bindable var env: AppEnvironment
    let updater: SPUUpdater
    @Environment(AppRouter.self) private var router
    @AppStorage("didShowWelcome") private var didShowWelcome = false

    var body: some View {
        @Bindable var router = router
        let selection = Binding<AppRouter.Section?>(
            get: { router.selection },
            // Picking a section from the sidebar is always a plain navigation, so it
            // also clears any pending "sign in again" target.
            set: { if let s = $0 { router.show(s) } })

        NavigationSplitView {
            List(selection: selection) {
                ForEach(AppRouter.Section.allCases) { section in
                    Label(section.title, systemImage: section.systemImage).tag(section)
                }
            }
            .navigationTitle("Claude Status Bar")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) {
                Button(role: .destructive) { NSApplication.shared.terminate(nil) } label: {
                    Label("Quit", systemImage: "power").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .padding(10)
            }
        } detail: {
            detail(for: router.selection)
                .frame(minWidth: 640, minHeight: 460)
        }
        .sheet(isPresented: Binding(
            get: { !didShowWelcome },
            set: { if !$0 { didShowWelcome = true } })
        ) {
            WelcomeView()
        }
    }

    @ViewBuilder
    private func detail(for section: AppRouter.Section) -> some View {
        switch section {
        case .dashboard: DashboardView(env: env)
        case .addAccount: centered { AddAccountView(env: env) }
        case .notch:      centered { NotchSettingsView(env: env) }
        case .settings:   centered { SettingsView(env: env) }
        case .about:      centered { AboutView(updater: updater) }
        }
    }

    // The Dashboard fills the pane; the compact forms are fixed-width, so center
    // them instead of stranding them in the top-left of a wide detail area.
    @ViewBuilder
    private func centered<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        VStack { Spacer(minLength: 0); content(); Spacer(minLength: 0) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
