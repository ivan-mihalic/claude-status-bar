// Sources/ClaudeStatusBarApp/Views/DashboardView.swift
import SwiftUI

public struct DashboardView: View {
    @Bindable var env: AppEnvironment
    @Environment(\.openWindow) private var openWindow
    public init(env: AppEnvironment) { self.env = env }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                    ForEach(env.appState.accounts) { acct in
                        VStack(alignment: .leading, spacing: 8) {
                            AccountRowView(account: acct, now: ctx.date)
                            HStack {
                                Stepper("Every \(acct.syncInterval)s",
                                        value: Binding(
                                            get: { acct.syncInterval },
                                            set: { env.accountManager.setInterval(acct.id, seconds: max(60, $0)) }),
                                        in: 60...3600, step: 60)
                                    .font(.caption)
                                Spacer()
                                if acct.status == .needsReauth {
                                    Button("Sign in again") { openWindow(id: "add-account") }
                                }
                                Button(role: .destructive) { env.accountManager.remove(acct.id) }
                                    label: { Image(systemName: "trash") }
                            }
                        }
                        .padding().background(.quaternary.opacity(0.3)).cornerRadius(12)
                    }
                }.padding()
            }
            .frame(minWidth: 700, minHeight: 420)
            .navigationTitle("Claude Usage")
        }
    }
}
