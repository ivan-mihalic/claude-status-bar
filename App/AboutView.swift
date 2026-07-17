import SwiftUI
import Sparkle

/// The "About" window: app name + version, a Check-for-Updates button, and a link to the repo.
struct AboutView: View {
    let updater: SPUUpdater

    private var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "gauge.medium")
                .font(.system(size: 44)).foregroundStyle(.tint)
            Text("Claude Status Bar").font(.title2.weight(.semibold))
            Text(versionText).font(.callout).foregroundStyle(.secondary)

            Divider().frame(width: 200)

            CheckForUpdatesView(updater: updater)
            Link("View on GitHub",
                 destination: URL(string: "https://github.com/ivan-mihalic/claude-status-bar")!)
                .font(.callout)

            Text("Track Claude Pro/Max usage across multiple accounts.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 320)
    }
}
