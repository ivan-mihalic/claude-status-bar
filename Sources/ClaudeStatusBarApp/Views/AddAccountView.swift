// Sources/ClaudeStatusBarApp/Views/AddAccountView.swift
import SwiftUI
import ClaudeStatusBarCore

public struct AddAccountView: View {
    @Bindable var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var pending: PendingLogin?
    @State private var code = ""
    @State private var label = ""
    @State private var error: String?
    @State private var connecting = false
    public init(env: AppEnvironment) { self.env = env }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a Claude account").font(.title3.bold())
            Button("Use my Claude Code account") {
                if let email = env.accountManager.detectClaudeCodeEmail() { label = email }
            }
            TextField("Label (email)", text: $label)
            if pending == nil {
                Button("Sign in with Claude…") { pending = env.accountManager.beginAdd(label: label.isEmpty ? nil : label) }
                    .buttonStyle(.borderedProminent)
            } else {
                Text("A browser opened. After signing in, copy the code shown on the callback page and paste it here.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Paste authorization code", text: $code)
                Button(connecting ? "Connecting…" : "Connect") { Task { await connect() } }
                    .disabled(code.isEmpty || connecting).buttonStyle(.borderedProminent)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(20).frame(width: 380)
    }

    private func connect() async {
        guard let pending else { return }
        connecting = true; defer { connecting = false }
        do {
            _ = try await env.accountManager.finishAdd(pending, code: code,
                    label: label.isEmpty ? "Claude account" : label)
            env.syncCoordinator.start()   // (re)start loops incl. the new account
            dismiss()
        } catch { self.error = Redaction.redact("\(error)") }
    }
}
