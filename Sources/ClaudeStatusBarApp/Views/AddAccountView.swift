// Sources/ClaudeStatusBarApp/Views/AddAccountView.swift
import SwiftUI
import ClaudeStatusBarCore

private enum CodexLoginMethod: String, CaseIterable, Identifiable {
    case browser
    case deviceCode

    var id: String { rawValue }
    var title: String { self == .browser ? "Browser" : "Device code" }
}

public struct AddAccountView: View {
    @Bindable var env: AppEnvironment
    @Environment(AppRouter.self) private var router
    @AppStorage("defaultIntervalSeconds") private var defaultInterval = 300
    @State private var provider: Provider = .claude
    @State private var codexLoginMethod: CodexLoginMethod = .browser
    @State private var code = ""
    @State private var clientSecret = ""
    @State private var pending: PendingLogin?
    @State private var deviceLogin: DeviceCodeLogin?
    @State private var loginTask: Task<Void, Never>?
    @State private var loginGeneration = UUID()
    @State private var label = ""
    @State private var error: String?
    @State private var connecting = false
    public init(env: AppEnvironment) { self.env = env }

    /// Non-nil when the router sent us here from an account's "Sign in again":
    /// the new token then replaces that account's token instead of adding a tile.
    private var reauthAccount: Account? {
        guard let id = router.reauthTarget else { return nil }
        return env.appState.accounts.first { $0.id == id }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let acct = reauthAccount {
                Text("Reconnect account").font(.title3.bold())
                Text("Reconnecting “\(acct.label)”. Its name, menu label, interval and "
                     + "position stay as they are — only the credentials are replaced.")
                    .font(.caption).foregroundStyle(.secondary)
                if acct.effectiveProvider == .codex {
                    Picker("Sign in using", selection: $codexLoginMethod) {
                        ForEach(CodexLoginMethod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: codexLoginMethod) { _, _ in resetLogin() }
                }
            } else {
                Text("Add an account").font(.title3.bold())
                if Provider.selectableCases.count > 1 {
                    Picker("Service", selection: $provider) {
                        ForEach(Provider.selectableCases) { item in
                            HStack {
                                ProviderMarkView(provider: item, diameter: 16)
                                Text(item.title)
                            }.tag(item)
                        }
                    }
                    .onChange(of: provider) { _, _ in resetLogin() }
                }
                TextField("Label (email)", text: $label)
                if provider == .codex {
                    Picker("Sign in using", selection: $codexLoginMethod) {
                        ForEach(CodexLoginMethod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: codexLoginMethod) { _, _ in resetLogin() }
                    Text(codexLoginMethod == .browser
                         ? "ChatGPT opens in your browser and returns here automatically."
                         : "OpenAI shows a one-time code to enter in your browser. Device-code login must be enabled in your ChatGPT security settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if effectiveProvider == .antigravity, deviceLogin == nil, pending == nil {
                SecureField("Antigravity OAuth client secret", text: $clientSecret)
                Text("Google requires the Antigravity OAuth client secret (GOCSPX-…), which this app does not ship. It is stored only in your Keychain with this account. Then Google opens in your browser and returns here automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if effectiveProvider == .claude {
                Text("Sign in once in your browser. This app keeps its own credentials in macOS Keychain and renews them automatically. Temporary sync errors keep your sign-in.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let deviceLogin {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter this one-time code:").font(.caption).foregroundStyle(.secondary)
                    Text(deviceLogin.userCode)
                        .font(.system(.title2, design: .monospaced).bold())
                        .textSelection(.enabled)
                    Link("Open ChatGPT sign-in page", destination: deviceLogin.verificationURL)
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for authorization…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Cancel") { resetLogin() }
                }
            } else if pending == nil {
                Button("Sign in with \(effectiveProvider.title)…") { start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!effectiveProvider.isSupported || connecting || missingClientSecret)
            } else if pending?.provider == .claude {
                Text("After signing in, copy the authorization code from the callback page and paste it here.")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("Authorization code", text: $code).disabled(connecting)
                Button(connecting ? "Connecting…" : "Connect") {
                    connecting = true
                    error = nil
                    let attempt = loginGeneration
                    loginTask = Task { await connect(attempt: attempt) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connecting)
                Button("Cancel") { resetLogin() }
            } else {
                // Codex and Antigravity redirect to a local address instead of showing a code, so there is
                // nothing to paste — the app is waiting for the browser to come back.
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for the browser to finish signing in…")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Cancel") { resetLogin() }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(20).frame(width: 380)
        .onAppear { resetLogin() }
        .onDisappear { resetLogin() }
    }

    private var effectiveProvider: Provider {
        reauthAccount?.effectiveProvider ?? provider
    }

    private var trimmedClientSecret: String {
        clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var missingClientSecret: Bool {
        effectiveProvider == .antigravity && trimmedClientSecret.isEmpty
    }

    private func start() {
        error = nil
        let target = reauthAccount?.effectiveProvider ?? provider
        if target == .codex, codexLoginMethod == .deviceCode {
            connecting = true
            let attempt = loginGeneration
            loginTask = Task { await connectDeviceCode(provider: target, attempt: attempt) }
            return
        }
        let secret = target == .antigravity ? trimmedClientSecret : nil
        guard let started = env.accountManager.beginLogin(provider: target, clientSecret: secret) else {
            error = target.unsupportedReason ?? "\(target.title) sign-in isn't available."
            return
        }
        pending = started
        // Read the provider off the pending login rather than the @State picker: for a
        // re-sign-in the picker isn't even shown, and it would still say "Claude".
        if started.provider != .claude {
            let attempt = loginGeneration
            loginTask = Task { await connect(attempt: attempt) }
        }
    }

    @MainActor
    private func connectDeviceCode(provider: Provider, attempt: UUID) async {
        guard attempt == loginGeneration else { return }
        let targetID = router.reauthTarget
        let name = label.isEmpty ? "\(provider.title) account" : label
        defer { if attempt == loginGeneration { connecting = false; loginTask = nil } }
        do {
            let login = try await env.accountManager.beginDeviceCode(provider: provider)
            try Task.checkCancellation()
            deviceLogin = login
            if let id = targetID {
                try await env.accountManager.reauth(id, deviceLogin: login, provider: provider)
            } else {
                _ = try await env.accountManager.finishAdd(login, provider: provider,
                                                           label: name, interval: defaultInterval)
            }
            guard attempt == loginGeneration, !Task.isCancelled else { return }
            finishSuccessfully()
        } catch is CancellationError {
            // The Cancel button already returned the form to its initial state.
        } catch {
            guard attempt == loginGeneration else { return }
            deviceLogin = nil
            self.error = Redaction.redact(error.localizedDescription)
        }
    }

    private func connect(attempt: UUID) async {
        guard attempt == loginGeneration, let pending else { return }
        let targetID = router.reauthTarget
        let name = label.isEmpty ? "\(pending.provider.title) account" : label
        let rawCode = code
        connecting = true
        defer { if attempt == loginGeneration { connecting = false } }
        do {
            if let id = targetID {
                if pending.provider == .claude {
                    try await env.accountManager.reauth(id, pending, code: rawCode)
                } else {
                    try await env.accountManager.reauth(id, pending)
                }
            } else if pending.provider == .claude {
                _ = try await env.accountManager.finishAdd(pending, code: rawCode,
                                                            label: name, interval: defaultInterval)
            } else {
                _ = try await env.accountManager.finishAdd(pending, label: name,
                                                           interval: defaultInterval)
            }
            guard attempt == loginGeneration, !Task.isCancelled else { return }
            finishSuccessfully()
        } catch is CancellationError {
        } catch {
            guard attempt == loginGeneration else { return }
            self.error = Redaction.redact(error.localizedDescription)
        }
    }

    @MainActor
    private func finishSuccessfully() {
        env.syncCoordinator.start()
        loginTask = nil; pending = nil; deviceLogin = nil
        code = ""; clientSecret = ""; label = ""; error = nil
        router.show(.dashboard)
    }

    private func resetLogin() {
        loginGeneration = UUID()
        loginTask?.cancel(); loginTask = nil
        pending = nil; deviceLogin = nil; code = ""; error = nil; connecting = false
    }
}
