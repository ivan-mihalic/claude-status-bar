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
    @State private var pending: PendingLogin?
    @State private var deviceLogin: DeviceCodeLogin?
    @State private var loginTask: Task<Void, Never>?
    @State private var code = ""
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
                Text("Sign in again").font(.title3.bold())
                Text("Reconnecting “\(acct.label)”. Its name, menu label, interval and "
                     + "position stay as they are — only the expired credentials are replaced.")
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
                Button("Sign in with \(provider.title)…") { start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!provider.isSupported || connecting)
            } else if usesPastedCode {
                Text("A browser opened. After signing in, copy the code shown on the callback page and paste it here.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Paste authorization code", text: $code)
                Button(connecting ? "Connecting…" : "Connect") { Task { await connect() } }
                    .disabled(code.isEmpty || connecting).buttonStyle(.borderedProminent)
                Button("Start over") { pending = nil; code = ""; error = nil }
            } else {
                // Codex redirects to a local address instead of showing a code, so there is
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
        .onDisappear { loginTask?.cancel() }
    }

    /// Anthropic shows the code on a web page; Codex redirects to a loopback address the app
    /// listens on. The difference is visible here and nowhere else.
    private var usesPastedCode: Bool {
        (pending?.provider ?? provider) == .claude
    }

    private func start() {
        error = nil
        let target = reauthAccount?.effectiveProvider ?? provider
        if target == .codex, codexLoginMethod == .deviceCode {
            connecting = true
            loginTask = Task { await connectDeviceCode(provider: target) }
            return
        }
        guard let started = env.accountManager.beginLogin(provider: target) else {
            error = target.unsupportedReason ?? "\(target.title) sign-in isn't available."
            return
        }
        pending = started
        // Read the provider off the pending login rather than the @State picker: for a
        // re-sign-in the picker isn't even shown, and it would still say "Claude".
        if started.provider != .claude {
            loginTask = Task { await connect() }
        }
    }

    @MainActor
    private func connectDeviceCode(provider: Provider) async {
        defer { connecting = false; loginTask = nil }
        do {
            let login = try await env.accountManager.beginDeviceCode(provider: provider)
            try Task.checkCancellation()
            deviceLogin = login
            let name = label.isEmpty ? "\(provider.title) account" : label
            if let acct = reauthAccount {
                try await env.accountManager.reauth(acct.id, deviceLogin: login, provider: provider)
            } else {
                _ = try await env.accountManager.finishAdd(login, provider: provider,
                                                           label: name, interval: defaultInterval)
            }
            finishSuccessfully()
        } catch is CancellationError {
            // The Cancel button already returned the form to its initial state.
        } catch {
            deviceLogin = nil
            self.error = Redaction.redact(error.localizedDescription)
        }
    }

    private func connect() async {
        guard let pending else { return }
        connecting = true; defer { connecting = false }
        do {
            let name = label.isEmpty ? "\(pending.provider.title) account" : label
            if let acct = reauthAccount {
                if usesPastedCode {
                    try await env.accountManager.reauth(acct.id, pending, code: code)
                } else {
                    try await env.accountManager.reauth(acct.id, pending)
                }
            } else if usesPastedCode {
                _ = try await env.accountManager.finishAdd(pending, code: code,
                        label: name, interval: defaultInterval)
            } else {
                _ = try await env.accountManager.finishAdd(pending, label: name,
                                                           interval: defaultInterval)
            }
            finishSuccessfully()
        } catch { self.error = Redaction.redact(error.localizedDescription) }
    }

    @MainActor
    private func finishSuccessfully() {
        env.syncCoordinator.start()
        loginTask = nil; pending = nil; deviceLogin = nil
        code = ""; label = ""; error = nil
        router.show(.dashboard)
    }

    private func resetLogin() {
        loginTask?.cancel(); loginTask = nil
        pending = nil; deviceLogin = nil; code = ""; error = nil; connecting = false
    }
}
