// App/WelcomeView.swift
import SwiftUI
import AppKit

/// First-run welcome sheet: what the app does + a transparency list, shown once
/// (gated by `didShowWelcome` in RootView) before the user adds their first account.
struct WelcomeView: View {
    @AppStorage("didShowWelcome") private var didShowWelcome = false

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
                .accessibilityLabel("Claude Status Bar app icon")

            Text("Welcome to Claude Status Bar").font(.title2.weight(.semibold))

            Text("Claude Status Bar lives in your menu bar and tracks Claude and Codex subscription usage across one or more accounts, so you can see how close you are to a rate limit at a glance.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                bullet("Runs as a menu-bar app only — no Dock icon by default.")
                bullet("Adding an account signs you in with Claude or ChatGPT and prompts you for Keychain access.")
                bullet("Network access is limited to the selected provider's sign-in and usage hosts, plus the app's own Sparkle update host (ivan-mihalic.github.io).")
                bullet("Your account tokens are stored in the macOS Keychain, never on disk in plain text.")
                bullet("If you used a previous version, this update changed the Keychain group — please re-add your accounts once.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Link("Learn more in SECURITY.md",
                 destination: URL(string: "https://github.com/ivan-mihalic/claude-status-bar/blob/main/SECURITY.md")!)
                .font(.callout)

            Button("Get Started") { didShowWelcome = true }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 380)
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
        .font(.callout).foregroundStyle(.secondary)
    }
}
