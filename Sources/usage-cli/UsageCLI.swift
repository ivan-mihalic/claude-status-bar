// Sources/usage-cli/UsageCLI.swift
import Foundation
import ClaudeStatusBarCore

func bar(_ pct: Double, width: Int = 24) -> String {
    let filled = Int((pct / 100.0 * Double(width)).rounded())
    return String(repeating: "█", count: max(0, min(width, filled)))
         + String(repeating: "░", count: max(0, width - filled))
}

func line(_ w: UsageWindow) -> String {
    let reset = ISO8601DateFormatter().string(from: w.resetsAt)
    return String(format: "  %-14@ %@ %5.1f%%  reset %@",
                  w.label as NSString, bar(w.utilization), w.utilization, reset)
}

func printSnapshot(_ label: String, _ s: UsageSnapshot) {
    print("Account: \(label)")
    print(line(s.session))
    print(line(s.weekAll))
    for p in s.weekPremium { print(line(p)) }
    print("")
}

@main
struct UsageCLI {
    static func main() async {
        let http = URLSessionHTTPClient()
        let clock = SystemClock()

        // 1) Read the bearer token from the environment.
        guard let token = ProcessInfo.processInfo.environment["CLAUDE_OAUTH_TOKEN"], !token.isEmpty else {
            FileHandle.standardError.write(Data("Set CLAUDE_OAUTH_TOKEN to an OAuth access token.\n".utf8))
            exit(2)
        }

        // 2) Store token in-memory and run one sync.
        let store = InMemoryTokenStore()
        let id = UUID()
        let bundle = TokenBundle(accessToken: token, refreshToken: "", expiresAt: Date.distantFuture, scopes: [])
        try? store.save(bundle, for: id)
        let engine = AccountSyncEngine(
            tokenStore: store,
            oauth: OAuthClient(http: http, endpoints: .production,
                               config: .claudeCode, clock: clock),
            usage: UsageAPIClient(http: http),
            clock: clock)

        let label = "Claude"
        switch await engine.syncOnce(accountID: id) {
        case .success(let snap): printSnapshot(label, snap)
        case .needsReauth:  print("\(label): needs re-auth (token invalid/expired).")
        case .rateLimited(let retryAfter):
            let when = retryAfter.map { " Try again in \(Int($0))s." } ?? " Try again in a few minutes."
            print("\(label): rate-limited.\(when)")
        case .offline:      print("\(label): offline / server error.")
        case .failed(let m):
            print("\(label): failed — \(Redaction.redact(m))")
        }
    }
}
