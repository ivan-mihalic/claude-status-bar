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

        // 1) Import the account currently logged into Claude Code.
        let importer = ClaudeCodeImporter(
            secretReader: KeychainSecretReader(),
            fileReader: DiskFileReader(),
            configURL: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude.json"))

        let imported: ImportedAccount
        do { imported = try importer.`import`() }
        catch {
            FileHandle.standardError.write(Data(
                "Could not import Claude Code account: \(error)\n".utf8))
            exit(1)
        }

        // 2) Store token in-memory and run one sync.
        let store = InMemoryTokenStore()
        let id = UUID()
        try? store.save(imported.bundle, for: id)
        let engine = AccountSyncEngine(
            tokenStore: store,
            oauth: OAuthClient(http: http, endpoints: .production,
                               config: .claudeCode, clock: clock),
            usage: UsageAPIClient(http: http),
            clock: clock)

        let label = imported.email ?? "Claude Code"
        switch await engine.syncOnce(accountID: id) {
        case .success(let snap): printSnapshot(label, snap)
        case .needsReauth:  print("\(label): needs re-auth (token invalid/expired).")
        case .rateLimited:  print("\(label): rate-limited (429). Try again in a few minutes.")
        case .offline:      print("\(label): offline / server error.")
        case .failed(let m):
            print("\(label): failed — \(Redaction.redact(m))")
        }
    }
}
