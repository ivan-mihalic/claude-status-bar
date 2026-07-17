// App/CheckForUpdates.swift
//
// Sparkle links into the app target only (it needs the app bundle for its XPC
// services). This file is the sole place `import Sparkle` may appear —
// `Sources/ClaudeStatusBarApp` must stay Sparkle-free so `swift test` keeps
// working without the dependency.
import SwiftUI
import Sparkle

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var vm: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.vm = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!vm.canCheckForUpdates)
    }
}
