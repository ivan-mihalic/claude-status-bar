# claude-status-bar — Plan 2: SwiftUI menu-bar app

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the native SwiftUI menu-bar app on top of Plan 1's `ClaudeStatusBarCore`: a `MenuBarExtra` widget (icon + most-constrained-% indicator) whose popover lists every connected account with mini usage bars, a dashboard window with large per-account bars + reset countdowns, an add-account flow (the app's own browser OAuth, paste-the-code; import-from-Claude-Code detects the account then runs that same OAuth), per-account sync intervals, and a settings screen. Self-update/packaging is Plan 3.

**Architecture:** All non-view logic lives in a new `ClaudeStatusBarApp` SPM **library** (view models, OAuth login orchestration, the sync coordinator/reducer, the menu-bar indicator, formatting) so it runs headless under `swift test`. The SwiftUI views also live in that library. A thin Xcode **app target** (`ClaudeStatusBar`, generated from a committed XcodeGen `project.yml`) provides only `@main`, the `Info.plist` (LSUIElement), and launch-at-login; it depends on the local SPM package. Tokens stay in Keychain (Plan 1's `KeychainTokenStore`); account metadata + last snapshot persist via Plan 1's `SnapshotStore`.

**Tech Stack:** Swift 6.x, SwiftUI (`MenuBarExtra`, `WindowGroup`, `Settings`, Swift Charts-free bars), Observation (`@Observable`), ServiceManagement (`SMAppService`), AppKit `NSWorkspace` (open browser) — all via Xcode 16 + macOS 14 SDK. XcodeGen for the project file. swift-testing for tests.

## Global Constraints

- Platform floor macOS 14; app is `LSUIElement` (menu-bar only, no Dock icon).
- **Xcode 16+ required** (build the `.app`, MenuBarExtra, ServiceManagement). Confirm `xcodebuild -version` before Milestone C. Core library tests still run via the swift.org toolchain wrapper: `export PATH="$HOME/.swiftly/bin:$PATH"` then `swift test` (see Plan 1 testing addendum). App-target build uses `xcodebuild` with the active Xcode.
- Tests use **swift-testing** (`import Testing`, `@Test`, `#expect`), NOT XCTest. Test code shown in tasks may be illustrative — implement the same assertions in swift-testing.
- **Every account is authenticated by the app's OWN browser OAuth grant** (independent token lineage). "Import from Claude Code" only *detects* the account (email via `ClaudeCodeImporter`) and then runs the same app OAuth — the app NEVER reuses or refreshes Claude Code's token. (Avoids logging the user out of Claude Code; see spec §12.)
- OAuth code capture = **paste-the-code**: open the authorize URL in the browser, user copies the code from Anthropic's callback page, pastes it into the app; the app exchanges it. (redirect_uri stays the registered `console.anthropic.com/oauth/code/callback`.)
- Secrets: tokens only in Keychain; never logged/printed/persisted to the snapshot JSON. All error text through `Redaction`.
- Sync: default interval 300s, floor 60s; 429 → `AccountStatus.rateLimited(retryAt: now + Backoff.usage.delay(consecutiveRateLimits))`; poll staggered across accounts.
- Menu-bar indicator = max utilization across all accounts/windows, color green <70 / amber <90 / red ≥90.
- Bundle id `cz.mihalic.claude-status-bar`; keychain service `cz.mihalic.claude-status-bar.tokens`.
- Reuse Plan 1 types verbatim: `OAuthClient`, `OAuthEndpoints.production`, `OAuthConfig.claudeCode`, `PKCE`, `UsageAPIClient`, `AccountSyncEngine`, `SyncScheduler`, `Backoff`, `Account`, `AccountStatus`, `AppState`, `KeychainTokenStore`, `SnapshotStore`, `ClaudeCodeImporter`, `SystemClock`, `URLSessionHTTPClient`, `Redaction`.

---

## File Structure

```
Package.swift                               (MODIFY: add ClaudeStatusBarApp lib + tests)
Sources/
  ClaudeStatusBarCore/                       (Plan 1 — mostly unchanged)
    OAuth/TokenBundle.swift                  (MODIFY task 1: optional refresh_token/expires_in)
    Usage/UsageAdapter.swift                 (MODIFY task 1: multi-word label title-case)
  ClaudeStatusBarApp/                         (NEW library — logic + views, no @main)
    Format.swift                             pure: bar string, reset countdown, percent
    MenuBarIndicator.swift                   pure: maxUtil -> symbol/color/tint/label
    Sync/SyncReducer.swift                   pure: (Account,SyncOutcome,now) -> Account + counters
    Sync/SyncCoordinator.swift               drives AccountSyncEngine per account, updates AppState
    Accounts/BrowserOpener.swift             protocol + NSWorkspace impl
    Accounts/OAuthLoginService.swift         PKCE+authorize URL, exchange pasted code -> stored account
    Accounts/AccountManager.swift            add (browser OAuth) / import-detect / remove / persist
    Environment/AppEnvironment.swift         composition root wiring real impls (@MainActor)
    Views/UsageBarView.swift
    Views/AccountRowView.swift
    Views/MenuBarContentView.swift
    Views/DashboardView.swift
    Views/AddAccountView.swift
    Views/SettingsView.swift
Sources/
  ClaudeStatusBar/                            (Xcode app target — thin)
    ClaudeStatusBarMain.swift                @main App: MenuBarExtra + Window + Settings scenes
    LaunchAtLogin.swift                      SMAppService wrapper
project.yml                                   (NEW — XcodeGen)
App/Info.plist                                (NEW — LSUIElement, bundle id, versions)
Tests/
  ClaudeStatusBarAppTests/
    FormatTests.swift, MenuBarIndicatorTests.swift, SyncReducerTests.swift,
    OAuthLoginServiceTests.swift, AccountManagerTests.swift, SyncCoordinatorTests.swift
    Mocks/  (reuse Core mocks + BrowserOpener spy)
```

---

## Task 1: Core robustness patches (Plan-1 carry-forward)

**Files:**
- Modify: `Sources/ClaudeStatusBarCore/OAuth/TokenBundle.swift`
- Modify: `Sources/ClaudeStatusBarCore/Usage/UsageAdapter.swift`
- Modify: `Tests/ClaudeStatusBarCoreTests/TokenBundleTests.swift`
- Modify: `Tests/ClaudeStatusBarCoreTests/UsageAdapterTests.swift`

**Interfaces:**
- Changes: `TokenResponse.refresh_token: String?`, `expires_in: Double?` (default lifetime when absent); `bundle(now:previousRefreshToken:)` keeps the old refresh token when the response omits one. `UsageAdapter.label` title-cases each underscore-separated word.
- Consumes: existing `TokenBundle`.

- [ ] **Step 1: Write failing tests (swift-testing)**

```swift
// add to TokenBundleTests.swift
@Test func tokenResponse_missingRefreshToken_keepsPrevious() throws {
    let json = #"{"access_token":"AT","expires_in":28800,"scope":"user:profile"}"#
    let resp = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
    let b = resp.bundle(now: Date(timeIntervalSince1970: 0), previousRefreshToken: "OLD_RT")
    #expect(b.refreshToken == "OLD_RT")
    #expect(b.accessToken == "AT")
}
@Test func tokenResponse_missingExpiresIn_usesDefaultLifetime() throws {
    let json = #"{"access_token":"AT","refresh_token":"RT"}"#
    let resp = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
    let b = resp.bundle(now: Date(timeIntervalSince1970: 0), previousRefreshToken: "X")
    #expect(b.expiresAt == Date(timeIntervalSince1970: 3600)) // 1h default
}

// add to UsageAdapterTests.swift
@Test func label_titleCasesMultiWordModel() {
    #expect(UsageAdapter.label(forKey: "seven_day_claude_opus_4") == "Week (Claude Opus 4)")
}
```

- [ ] **Step 2: Run to verify fail**

Run: `export PATH="$HOME/.swiftly/bin:$PATH" && swift test --filter TokenBundle` and `--filter UsageAdapter`
Expected: FAIL (new cases).

- [ ] **Step 3: Implement — TokenResponse**

Replace `TokenResponse` in `TokenBundle.swift` with:
```swift
public struct TokenResponse: Decodable, Sendable {
    public let access_token: String
    public let refresh_token: String?
    public let expires_in: Double?
    public let scope: String?

    /// RFC 6749 §5.1: `refresh_token` may be omitted (keep the old one);
    /// `expires_in` is optional (default to a conservative 1h).
    public func bundle(now: Date, previousRefreshToken: String) -> TokenBundle {
        TokenBundle(
            accessToken: access_token,
            refreshToken: refresh_token ?? previousRefreshToken,
            expiresAt: now.addingTimeInterval(expires_in ?? 3600),
            scopes: (scope ?? "").split(separator: " ").map(String.init)
        )
    }
}
```

- [ ] **Step 4: Update `OAuthClient` call site**

In `Sources/ClaudeStatusBarCore/OAuth/OAuthClient.swift`, the exchange has no previous token (pass `""`); refresh passes the current one. Change the `perform` closure to receive the fallback refresh token. Concretely, update `exchange`/`refresh` to thread it:
```swift
    public func exchange(code: String, verifier: String, state: String) async throws -> TokenBundle {
        try await perform(previousRefreshToken: "") { host in
            OAuthRequests.exchange(tokenURL: host, config: config, code: code, verifier: verifier, state: state)
        }
    }
    public func refresh(_ bundle: TokenBundle) async throws -> TokenBundle {
        try await perform(previousRefreshToken: bundle.refreshToken) { host in
            OAuthRequests.refresh(tokenURL: host, config: config, refreshToken: bundle.refreshToken)
        }
    }
    private func perform(previousRefreshToken: String, _ build: (URL) -> URLRequest) async throws -> TokenBundle {
        // ... unchanged, except the 200 branch:
        // return tr.bundle(now: clock.now(), previousRefreshToken: previousRefreshToken)
    }
```
(The rest of `perform` — host loop, 400→invalidGrant, error accumulation — is unchanged.)

- [ ] **Step 5: Implement — UsageAdapter.label**

In `UsageAdapter.label(forKey:)`, replace the `seven_day_` branch:
```swift
        default:
            if key.hasPrefix("seven_day_") {
                let model = String(key.dropFirst("seven_day_".count))
                let titled = model.split(separator: "_")
                    .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                    .joined(separator: " ")
                return "Week (\(titled))"
            }
            return key
```

- [ ] **Step 6: Run full suite to verify pass + no regression**

Run: `export PATH="$HOME/.swiftly/bin:$PATH" && swift test`
Expected: all pass (the existing OAuthClient tests still green because refresh responses in those fixtures include `refresh_token`).

- [ ] **Step 7: Commit**

```bash
git add Sources/ClaudeStatusBarCore Tests/ClaudeStatusBarCoreTests/TokenBundleTests.swift Tests/ClaudeStatusBarCoreTests/UsageAdapterTests.swift
git commit -m "feat(core): tolerate missing refresh_token/expires_in; title-case multi-word model labels"
```

---

## Task 2: New `ClaudeStatusBarApp` library + Format helpers

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ClaudeStatusBarApp/Format.swift`
- Create: `Tests/ClaudeStatusBarAppTests/FormatTests.swift`

**Interfaces:**
- Produces: library target `ClaudeStatusBarApp` (depends on `ClaudeStatusBarCore`); `enum Format { static func percent(_ u: Double) -> String; static func bar(_ u: Double, width: Int) -> String; static func resetCountdown(to date: Date, now: Date) -> String }`.

- [ ] **Step 1: Modify Package.swift**

Add to `products`: `.library(name: "ClaudeStatusBarApp", targets: ["ClaudeStatusBarApp"])`. Add targets:
```swift
        .target(name: "ClaudeStatusBarApp", dependencies: ["ClaudeStatusBarCore"]),
        .testTarget(name: "ClaudeStatusBarAppTests", dependencies: ["ClaudeStatusBarApp"]),
```

- [ ] **Step 2: Failing test**

```swift
// Tests/ClaudeStatusBarAppTests/FormatTests.swift
import Testing
import Foundation
@testable import ClaudeStatusBarApp

@Test func percent_roundsToWhole() { #expect(Format.percent(33.4) == "33%") ; #expect(Format.percent(0) == "0%") }
@Test func bar_fillsProportionally() {
    #expect(Format.bar(50, width: 8) == "████░░░░")
    #expect(Format.bar(0, width: 4) == "░░░░")
    #expect(Format.bar(100, width: 4) == "████")
}
@Test func resetCountdown_formatsHoursMinutes() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(Format.resetCountdown(to: now.addingTimeInterval(2*3600 + 14*60), now: now) == "resets in 2h 14m")
    #expect(Format.resetCountdown(to: now.addingTimeInterval(45*60), now: now) == "resets in 45m")
    #expect(Format.resetCountdown(to: now.addingTimeInterval(-10), now: now) == "resetting…")
}
```

- [ ] **Step 3: Run to verify fail** — `swift test --filter Format` → FAIL.

- [ ] **Step 4: Implement**

```swift
// Sources/ClaudeStatusBarApp/Format.swift
import Foundation

public enum Format {
    public static func percent(_ u: Double) -> String { "\(Int(u.rounded()))%" }

    public static func bar(_ u: Double, width: Int = 24) -> String {
        let filled = max(0, min(width, Int((u / 100.0 * Double(width)).rounded())))
        return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
    }

    public static func resetCountdown(to date: Date, now: Date) -> String {
        let secs = Int(date.timeIntervalSince(now))
        if secs <= 0 { return "resetting…" }
        let h = secs / 3600, m = (secs % 3600) / 60
        if h > 0 { return "resets in \(h)h \(m)m" }
        return "resets in \(m)m"
    }
}
```

- [ ] **Step 5: Run to verify pass** — `swift test --filter Format` → PASS.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/ClaudeStatusBarApp/Format.swift Tests/ClaudeStatusBarAppTests/FormatTests.swift
git commit -m "feat(app): ClaudeStatusBarApp library + Format helpers"
```

---

## Task 3: MenuBarIndicator (pure)

**Files:**
- Create: `Sources/ClaudeStatusBarApp/MenuBarIndicator.swift`
- Create: `Tests/ClaudeStatusBarAppTests/MenuBarIndicatorTests.swift`

**Interfaces:**
- Produces: `enum IndicatorLevel { case ok, warn, critical, unknown }`; `enum MenuBarIndicator { static func level(maxUtilization: Double?) -> IndicatorLevel; static func label(maxUtilization: Double?) -> String }`. Level thresholds: unknown when nil; ok <70; warn 70..<90; critical ≥90. `label` = `"—"` when nil else `Format.percent`.

- [ ] **Step 1: Failing test**

```swift
// Tests/ClaudeStatusBarAppTests/MenuBarIndicatorTests.swift
import Testing
@testable import ClaudeStatusBarApp

@Test func level_thresholds() {
    #expect(MenuBarIndicator.level(maxUtilization: nil) == .unknown)
    #expect(MenuBarIndicator.level(maxUtilization: 0) == .ok)
    #expect(MenuBarIndicator.level(maxUtilization: 69.9) == .ok)
    #expect(MenuBarIndicator.level(maxUtilization: 70) == .warn)
    #expect(MenuBarIndicator.level(maxUtilization: 89.9) == .warn)
    #expect(MenuBarIndicator.level(maxUtilization: 90) == .critical)
    #expect(MenuBarIndicator.level(maxUtilization: 100) == .critical)
}
@Test func label_showsDashWhenUnknown() {
    #expect(MenuBarIndicator.label(maxUtilization: nil) == "—")
    #expect(MenuBarIndicator.label(maxUtilization: 42.6) == "43%")
}
```

- [ ] **Step 2: Run to verify fail** — `swift test --filter MenuBarIndicator` → FAIL.

- [ ] **Step 3: Implement**

```swift
// Sources/ClaudeStatusBarApp/MenuBarIndicator.swift
import Foundation

public enum IndicatorLevel: Equatable, Sendable { case ok, warn, critical, unknown }

public enum MenuBarIndicator {
    public static func level(maxUtilization: Double?) -> IndicatorLevel {
        guard let u = maxUtilization else { return .unknown }
        if u >= 90 { return .critical }
        if u >= 70 { return .warn }
        return .ok
    }
    public static func label(maxUtilization: Double?) -> String {
        guard let u = maxUtilization else { return "—" }
        return Format.percent(u)
    }
}
```

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatusBarApp/MenuBarIndicator.swift Tests/ClaudeStatusBarAppTests/MenuBarIndicatorTests.swift
git commit -m "feat(app): menu-bar indicator level + label mapping"
```

---

## Task 4: SyncReducer (pure)

**Files:**
- Create: `Sources/ClaudeStatusBarApp/Sync/SyncReducer.swift`
- Create: `Tests/ClaudeStatusBarAppTests/SyncReducerTests.swift`

**Interfaces:**
- Consumes: `Account`, `AccountStatus`, `SyncOutcome`, `Backoff`, `UsageSnapshot`.
- Produces:
  - `struct SyncState: Equatable { var account: Account; var consecutiveRateLimits: Int }`
  - `enum SyncReducer { static func reduce(_ state: SyncState, outcome: SyncOutcome, now: Date, backoff: Backoff) -> SyncState }`
  - Rules: `.success(snap)` → status `.ok`, `lastSnapshot = snap`, `lastSyncedAt = now`, reset counter. `.rateLimited` → counter+1, status `.rateLimited(retryAt: now + backoff.delay(counter+1))`, keep lastSnapshot. `.needsReauth` → status `.needsReauth`, counter 0. `.offline` → status `.offline`, counter 0, keep lastSnapshot. `.failed` → status `.offline`, keep lastSnapshot.

- [ ] **Step 1: Failing test**

```swift
// Tests/ClaudeStatusBarAppTests/SyncReducerTests.swift
import Testing
import Foundation
@testable import ClaudeStatusBarApp
@testable import ClaudeStatusBarCore

private func acct() -> Account {
    Account(id: UUID(), label: "a@x", accountUuid: nil, syncInterval: 300,
            status: .never, lastSnapshot: nil, lastSyncedAt: nil)
}
private func snap(_ s: Double) -> UsageSnapshot {
    let w = UsageWindow(key: "five_hour", label: "Session", utilization: s, resetsAt: Date(timeIntervalSince1970: 0))
    return UsageSnapshot(session: w, weekAll: w, weekPremium: [], fetchedAt: Date(timeIntervalSince1970: 0))
}

@Test func reduce_success_setsOkAndSnapshot() {
    let now = Date(timeIntervalSince1970: 1000)
    let out = SyncReducer.reduce(SyncState(account: acct(), consecutiveRateLimits: 3),
                                 outcome: .success(snap(42)), now: now, backoff: .usage)
    #expect(out.account.status == .ok)
    #expect(out.account.lastSnapshot?.session.utilization == 42)
    #expect(out.account.lastSyncedAt == now)
    #expect(out.consecutiveRateLimits == 0)
}
@Test func reduce_rateLimited_incrementsAndSetsRetryAt() {
    let now = Date(timeIntervalSince1970: 1000)
    let out = SyncReducer.reduce(SyncState(account: acct(), consecutiveRateLimits: 0),
                                 outcome: .rateLimited, now: now, backoff: .usage)
    #expect(out.consecutiveRateLimits == 1)
    #expect(out.account.status == .rateLimited(retryAt: now.addingTimeInterval(30)))
}
@Test func reduce_needsReauth_resetsCounter() {
    let out = SyncReducer.reduce(SyncState(account: acct(), consecutiveRateLimits: 4),
                                 outcome: .needsReauth, now: Date(timeIntervalSince1970: 0), backoff: .usage)
    #expect(out.account.status == .needsReauth)
    #expect(out.consecutiveRateLimits == 0)
}
```

- [ ] **Step 2: Run to verify fail** — FAIL.

- [ ] **Step 3: Implement**

```swift
// Sources/ClaudeStatusBarApp/Sync/SyncReducer.swift
import Foundation
import ClaudeStatusBarCore

public struct SyncState: Equatable, Sendable {
    public var account: Account
    public var consecutiveRateLimits: Int
    public init(account: Account, consecutiveRateLimits: Int) {
        self.account = account; self.consecutiveRateLimits = consecutiveRateLimits
    }
}

public enum SyncReducer {
    public static func reduce(_ state: SyncState, outcome: SyncOutcome,
                              now: Date, backoff: Backoff = .usage) -> SyncState {
        var s = state
        switch outcome {
        case .success(let snap):
            s.account.status = .ok
            s.account.lastSnapshot = snap
            s.account.lastSyncedAt = now
            s.consecutiveRateLimits = 0
        case .rateLimited:
            s.consecutiveRateLimits += 1
            let delay = backoff.delay(forFailureCount: s.consecutiveRateLimits)
            s.account.status = .rateLimited(retryAt: now.addingTimeInterval(delay))
        case .needsReauth:
            s.account.status = .needsReauth
            s.consecutiveRateLimits = 0
        case .offline, .failed:
            s.account.status = .offline
            s.consecutiveRateLimits = 0
        }
        return s
    }
}
```

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatusBarApp/Sync/SyncReducer.swift Tests/ClaudeStatusBarAppTests/SyncReducerTests.swift
git commit -m "feat(app): SyncReducer maps outcome to account status + backoff retryAt"
```

---

## Task 5: BrowserOpener + OAuthLoginService

**Files:**
- Create: `Sources/ClaudeStatusBarApp/Accounts/BrowserOpener.swift`
- Create: `Sources/ClaudeStatusBarApp/Accounts/OAuthLoginService.swift`
- Create: `Tests/ClaudeStatusBarAppTests/OAuthLoginServiceTests.swift`

**Interfaces:**
- Produces:
  - `protocol BrowserOpener: Sendable { func open(_ url: URL) }` + `struct SystemBrowserOpener: BrowserOpener` (NSWorkspace).
  - `struct OAuthLoginService { init(oauth: OAuthClient, endpoints: OAuthEndpoints, config: OAuthConfig, tokenStore: TokenStore, opener: BrowserOpener); func begin() -> PendingLogin; func complete(_ pending: PendingLogin, code: String, accountID: UUID) async throws -> TokenBundle }`
  - `struct PendingLogin { let pkce: PKCE; let state: String; let authorizeURL: URL }`
  - `begin()` generates PKCE + state, builds the authorize URL, and opens the browser. `complete` strips any `#...`/`&state=` the user may paste, calls `oauth.exchange`, and saves the bundle to the token store under `accountID`.

- [ ] **Step 1: Failing test**

```swift
// Tests/ClaudeStatusBarAppTests/OAuthLoginServiceTests.swift
import Testing
import Foundation
@testable import ClaudeStatusBarApp
@testable import ClaudeStatusBarCore

final class SpyBrowser: BrowserOpener, @unchecked Sendable {
    var opened: [URL] = []
    func open(_ url: URL) { opened.append(url) }
}

private func service(_ http: MockHTTPClient, _ store: TokenStore, _ browser: SpyBrowser) -> OAuthLoginService {
    OAuthLoginService(
        oauth: OAuthClient(http: http, endpoints: .production, config: .claudeCode,
                           clock: ManualClock(Date(timeIntervalSince1970: 0))),
        endpoints: .production, config: .claudeCode, tokenStore: store, opener: browser)
}

@Test func begin_opensAuthorizeURLWithChallenge() {
    let browser = SpyBrowser()
    let svc = service(MockHTTPClient(), InMemoryTokenStore(), browser)
    let pending = svc.begin()
    #expect(browser.opened.count == 1)
    let q = URLComponents(url: browser.opened[0], resolvingAgainstBaseURL: false)!.queryItems!
    #expect(q.contains { $0.name == "code_challenge" && $0.value == pending.pkce.challenge })
    #expect(q.contains { $0.name == "state" && $0.value == pending.state })
}
@Test func complete_exchangesCode_storesToken() async throws {
    let store = InMemoryTokenStore()
    let http = MockHTTPClient { _ in
        HTTPResponse(status: 200, headers: [:],
            body: Data(#"{"access_token":"AT","refresh_token":"RT","expires_in":28800,"scope":"user:profile"}"#.utf8))
    }
    let svc = service(http, store, SpyBrowser())
    let pending = svc.begin()
    let id = UUID()
    let bundle = try await svc.complete(pending, code: "CODE#state=x", accountID: id)
    #expect(bundle.accessToken == "AT")
    #expect(try store.load(id)?.accessToken == "AT")   // persisted under accountID
}
```

- [ ] **Step 2: Run to verify fail** — FAIL.

- [ ] **Step 3: Implement BrowserOpener**

```swift
// Sources/ClaudeStatusBarApp/Accounts/BrowserOpener.swift
import Foundation
#if canImport(AppKit)
import AppKit
#endif

public protocol BrowserOpener: Sendable { func open(_ url: URL) }

public struct SystemBrowserOpener: BrowserOpener {
    public init() {}
    public func open(_ url: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }
}
```

- [ ] **Step 4: Implement OAuthLoginService**

```swift
// Sources/ClaudeStatusBarApp/Accounts/OAuthLoginService.swift
import Foundation
import ClaudeStatusBarCore

public struct PendingLogin: Sendable {
    public let pkce: PKCE
    public let state: String
    public let authorizeURL: URL
}

public struct OAuthLoginService {
    private let oauth: OAuthClient
    private let endpoints: OAuthEndpoints
    private let config: OAuthConfig
    private let tokenStore: TokenStore
    private let opener: BrowserOpener

    public init(oauth: OAuthClient, endpoints: OAuthEndpoints, config: OAuthConfig,
                tokenStore: TokenStore, opener: BrowserOpener) {
        self.oauth = oauth; self.endpoints = endpoints; self.config = config
        self.tokenStore = tokenStore; self.opener = opener
    }

    public func begin() -> PendingLogin {
        let pkce = PKCE.generate()
        let state = PKCE.generate().verifier          // reuse CSPRNG for an opaque state
        let url = endpoints.authorizeURL(config: config, pkce: pkce, state: state)
        opener.open(url)
        return PendingLogin(pkce: pkce, state: state, authorizeURL: url)
    }

    public func complete(_ pending: PendingLogin, code rawCode: String,
                         accountID: UUID) async throws -> TokenBundle {
        // Anthropic's callback page shows "<code>#<state>" or "<code>&state=<state>";
        // accept a pasted value that may include either separator.
        let code = rawCode
            .split(whereSeparator: { $0 == "#" || $0 == "&" }).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? rawCode
        let bundle = try await oauth.exchange(code: code, verifier: pending.pkce.verifier,
                                              state: pending.state)
        try tokenStore.save(bundle, for: accountID)
        return bundle
    }
}
```

- [ ] **Step 5: Run to verify pass** — `swift test --filter OAuthLoginService` → PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeStatusBarApp/Accounts/BrowserOpener.swift Sources/ClaudeStatusBarApp/Accounts/OAuthLoginService.swift Tests/ClaudeStatusBarAppTests/OAuthLoginServiceTests.swift
git commit -m "feat(app): OAuth login service (PKCE authorize + paste-code exchange)"
```

---

## Task 6: AccountManager (add / import-detect / remove / persist)

**Files:**
- Create: `Sources/ClaudeStatusBarApp/Accounts/AccountManager.swift`
- Create: `Tests/ClaudeStatusBarAppTests/AccountManagerTests.swift`

**Interfaces:**
- Consumes: `AppState`, `OAuthLoginService`, `SnapshotStore`, `TokenStore`, `ClaudeCodeImporter`, `Account`, `PendingLogin`.
- Produces (`@MainActor final class AccountManager`):
  - `func beginAdd(label: String?) -> PendingLogin` — starts an OAuth login; caller shows the paste UI.
  - `func finishAdd(_ pending: PendingLogin, code: String, label: String) async throws -> Account` — exchanges the code (new `accountID`), creates the `Account` (default interval 300), appends to `AppState`, persists metadata.
  - `func detectClaudeCodeEmail() -> String?` — best-effort email via `ClaudeCodeImporter` (no token used).
  - `func remove(_ id: UUID)` — deletes token (Keychain), removes from `AppState`, persists, and stops nothing here (coordinator observes AppState).
  - `func setInterval(_ id: UUID, seconds: Int)` — updates + persists.

- [ ] **Step 1: Failing test**

```swift
// Tests/ClaudeStatusBarAppTests/AccountManagerTests.swift
import Testing
import Foundation
@testable import ClaudeStatusBarApp
@testable import ClaudeStatusBarCore

@MainActor
private func makeManager(_ http: MockHTTPClient, store: TokenStore, snapURL: URL)
-> (AccountManager, AppState) {
    let state = AppState()
    let login = OAuthLoginService(
        oauth: OAuthClient(http: http, endpoints: .production, config: .claudeCode,
                           clock: ManualClock(Date(timeIntervalSince1970: 0))),
        endpoints: .production, config: .claudeCode, tokenStore: store, opener: SpyBrowser())
    let mgr = AccountManager(appState: state, login: login, tokenStore: store,
                             snapshotStore: SnapshotStore(fileURL: snapURL),
                             importer: nil)
    return (mgr, state)
}

@Test @MainActor func finishAdd_createsPersistsAndAppendsAccount() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = InMemoryTokenStore()
    let http = MockHTTPClient { _ in HTTPResponse(status: 200, headers: [:],
        body: Data(#"{"access_token":"AT","refresh_token":"RT","expires_in":28800,"scope":""}"#.utf8)) }
    let (mgr, state) = makeManager(http, store: store, snapURL: tmp)
    let pending = mgr.beginAdd(label: nil)
    let acct = try await mgr.finishAdd(pending, code: "CODE", label: "work@x")
    #expect(state.accounts.count == 1)
    #expect(acct.label == "work@x")
    #expect(acct.syncInterval == 300)
    #expect(try store.load(acct.id) != nil)                         // token stored
    #expect(SnapshotStore(fileURL: tmp).load().first?.id == acct.id) // metadata persisted
}

@Test @MainActor func remove_deletesTokenAndPersists() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = InMemoryTokenStore()
    let http = MockHTTPClient { _ in HTTPResponse(status: 200, headers: [:],
        body: Data(#"{"access_token":"AT","refresh_token":"RT","expires_in":28800,"scope":""}"#.utf8)) }
    let (mgr, state) = makeManager(http, store: store, snapURL: tmp)
    let acct = try await mgr.finishAdd(mgr.beginAdd(label: nil), code: "C", label: "x")
    mgr.remove(acct.id)
    #expect(state.accounts.isEmpty)
    #expect(try store.load(acct.id) == nil)
    #expect(SnapshotStore(fileURL: tmp).load().isEmpty)
}
```

- [ ] **Step 2: Run to verify fail** — FAIL.

- [ ] **Step 3: Implement**

```swift
// Sources/ClaudeStatusBarApp/Accounts/AccountManager.swift
import Foundation
import ClaudeStatusBarCore

@MainActor
public final class AccountManager {
    private let appState: AppState
    private let login: OAuthLoginService
    private let tokenStore: TokenStore
    private let snapshotStore: SnapshotStore
    private let importer: ClaudeCodeImporter?

    public init(appState: AppState, login: OAuthLoginService, tokenStore: TokenStore,
                snapshotStore: SnapshotStore, importer: ClaudeCodeImporter?) {
        self.appState = appState; self.login = login; self.tokenStore = tokenStore
        self.snapshotStore = snapshotStore; self.importer = importer
    }

    public func beginAdd(label: String?) -> PendingLogin { login.begin() }

    public func finishAdd(_ pending: PendingLogin, code: String, label: String) async throws -> Account {
        let id = UUID()
        _ = try await login.complete(pending, code: code, accountID: id)
        let account = Account(id: id, label: label, accountUuid: nil,
                              syncInterval: Account.intervalDefault, status: .never,
                              lastSnapshot: nil, lastSyncedAt: nil)
        appState.upsert(account)
        persist()
        return account
    }

    /// Best-effort: detect the email of the account currently logged into Claude Code,
    /// to pre-fill the label. The token itself is NOT used — the app runs its own OAuth.
    public func detectClaudeCodeEmail() -> String? {
        (try? importer?.import())?.email
    }

    public func remove(_ id: UUID) {
        try? tokenStore.delete(id)
        appState.remove(id)
        persist()
    }

    public func setInterval(_ id: UUID, seconds: Int) {
        guard var a = appState.accounts.first(where: { $0.id == id }) else { return }
        a.syncInterval = seconds
        appState.upsert(a)
        persist()
    }

    private func persist() { try? snapshotStore.save(appState.accounts) }
}
```

- [ ] **Step 4: Run to verify pass** — `swift test --filter AccountManager` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatusBarApp/Accounts/AccountManager.swift Tests/ClaudeStatusBarAppTests/AccountManagerTests.swift
git commit -m "feat(app): AccountManager add/import-detect/remove/persist"
```

---

## Task 7: SyncCoordinator (drive per-account sync)

**Files:**
- Create: `Sources/ClaudeStatusBarApp/Sync/SyncCoordinator.swift`
- Create: `Tests/ClaudeStatusBarAppTests/SyncCoordinatorTests.swift`

**Interfaces:**
- Consumes: `AppState`, `AccountSyncEngine`, `SyncReducer`, `SyncScheduler`, `Clock`, `SnapshotStore`.
- Produces (`@MainActor final class SyncCoordinator`):
  - `func syncNow(_ id: UUID) async` — runs `engine.syncOnce`, applies `SyncReducer`, updates `AppState`, persists. Tracks `consecutiveRateLimits` per account id.
  - `func nextDelay(for id: UUID, now: Date) -> TimeInterval` — via `SyncScheduler.nextInterval(base: account.effectiveInterval, status:, consecutiveRateLimits:, now:)`.
  - `func start()` / `func stop()` — launch/cancel one detached polling loop per account (each: sync → sleep `nextDelay` → repeat), started with a per-account stagger. (The loop itself is thin; the tested surface is `syncNow` + `nextDelay`.)

- [ ] **Step 1: Failing test** (tests the reducing/persisting/scheduling surface, not real timers)

```swift
// Tests/ClaudeStatusBarAppTests/SyncCoordinatorTests.swift
import Testing
import Foundation
@testable import ClaudeStatusBarApp
@testable import ClaudeStatusBarCore

@MainActor
private func coord(_ http: MockHTTPClient, _ state: AppState, _ store: TokenStore,
                   _ clock: ManualClock, _ snapURL: URL) -> SyncCoordinator {
    SyncCoordinator(
        appState: state,
        engine: AccountSyncEngine(
            tokenStore: store,
            oauth: OAuthClient(http: http, endpoints: .production, config: .claudeCode, clock: clock),
            usage: UsageAPIClient(http: http), clock: clock),
        clock: clock,
        snapshotStore: SnapshotStore(fileURL: snapURL))
}

@Test @MainActor func syncNow_success_updatesAccountAndPersists() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let clock = ManualClock(Date(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(TokenBundle(accessToken: "AT", refreshToken: "RT",
        expiresAt: Date(timeIntervalSince1970: 100_000), scopes: []), for: id)
    let state = AppState()
    state.upsert(Account(id: id, label: "a", accountUuid: nil, syncInterval: 300,
                         status: .never, lastSnapshot: nil, lastSyncedAt: nil))
    let usage = try! Data(contentsOf: Bundle.module.url(forResource: "usage_full",
        withExtension: "json", subdirectory: "Fixtures")!)   // see step note
    let http = MockHTTPClient { _ in HTTPResponse(status: 200, headers: [:], body: usage) }
    let c = coord(http, state, store, clock, tmp)
    await c.syncNow(id)
    #expect(state.accounts.first?.status == .ok)
    #expect(state.accounts.first?.lastSnapshot?.session.utilization == 33.0)
}

@Test @MainActor func nextDelay_rateLimited_usesRetryAt() async {
    let clock = ManualClock(Date(timeIntervalSince1970: 1000))
    let state = AppState()
    let id = UUID()
    state.upsert(Account(id: id, label: "a", accountUuid: nil, syncInterval: 300,
        status: .rateLimited(retryAt: Date(timeIntervalSince1970: 1000 + 200)),
        lastSnapshot: nil, lastSyncedAt: nil))
    let c = coord(MockHTTPClient(), state, InMemoryTokenStore(), clock, URL(fileURLWithPath: "/dev/null"))
    #expect(c.nextDelay(for: id, now: clock.now()) == 200)
}
```

> Fixture note: `ClaudeStatusBarAppTests` needs the `usage_full.json` fixture. Add `resources: [.copy("Fixtures")]` to the `ClaudeStatusBarAppTests` target in `Package.swift` and copy `usage_full.json` into `Tests/ClaudeStatusBarAppTests/Fixtures/` (a 3-line JSON identical to the Core one). Do this in Step 3.

- [ ] **Step 2: Run to verify fail** — FAIL.

- [ ] **Step 3: Add fixture + implement**

Add the `Fixtures` resource to `ClaudeStatusBarAppTests` in `Package.swift` and copy `usage_full.json`. Then:

```swift
// Sources/ClaudeStatusBarApp/Sync/SyncCoordinator.swift
import Foundation
import ClaudeStatusBarCore

@MainActor
public final class SyncCoordinator {
    private let appState: AppState
    private let engine: AccountSyncEngine
    private let clock: Clock
    private let snapshotStore: SnapshotStore
    private var counters: [UUID: Int] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init(appState: AppState, engine: AccountSyncEngine, clock: Clock, snapshotStore: SnapshotStore) {
        self.appState = appState; self.engine = engine; self.clock = clock; self.snapshotStore = snapshotStore
    }

    public func syncNow(_ id: UUID) async {
        guard let account = appState.accounts.first(where: { $0.id == id }) else { return }
        let outcome = await engine.syncOnce(accountID: id)
        let reduced = SyncReducer.reduce(
            SyncState(account: account, consecutiveRateLimits: counters[id] ?? 0),
            outcome: outcome, now: clock.now())
        counters[id] = reduced.consecutiveRateLimits
        appState.upsert(reduced.account)
        try? snapshotStore.save(appState.accounts)
    }

    public func nextDelay(for id: UUID, now: Date) -> TimeInterval {
        guard let a = appState.accounts.first(where: { $0.id == id }) else { return 300 }
        return SyncScheduler.nextInterval(base: a.effectiveInterval, status: a.status,
                                          consecutiveRateLimits: counters[id] ?? 0, now: now)
    }

    public func start() {
        stop()
        for (index, account) in appState.accounts.enumerated() {
            let id = account.id
            let stagger = SyncScheduler.staggerOffset(index: index, spacing: 5)
            tasks[id] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(stagger * 1_000_000_000))
                while !Task.isCancelled {
                    await self?.syncNow(id)
                    let delay = self?.nextDelay(for: id, now: self?.clock.now() ?? Date()) ?? 300
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
    }

    public func stop() { tasks.values.forEach { $0.cancel() }; tasks.removeAll() }
}
```

- [ ] **Step 4: Run to verify pass** — `swift test --filter SyncCoordinator` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/ClaudeStatusBarApp/Sync/SyncCoordinator.swift Tests/ClaudeStatusBarAppTests
git commit -m "feat(app): SyncCoordinator drives per-account sync + scheduling"
```

---

## Task 8: AppEnvironment composition root

**Files:**
- Create: `Sources/ClaudeStatusBarApp/Environment/AppEnvironment.swift`

**Interfaces:**
- Produces (`@MainActor @Observable final class AppEnvironment`): the single wiring point the app target instantiates. Holds `appState: AppState`, `accountManager: AccountManager`, `syncCoordinator: SyncCoordinator`, and `defaultInterval`. `func bootstrap()` loads persisted accounts into `appState` and calls `syncCoordinator.start()`. Wires the REAL impls: `URLSessionHTTPClient`, `KeychainTokenStore(service: "cz.mihalic.claude-status-bar.tokens")`, `SnapshotStore.defaultURL()`, `SystemClock`, `SystemBrowserOpener`, `ClaudeCodeImporter` with real readers.

- [ ] **Step 1: Implement (no unit test — composition root; verified by app build + launch in Task 14)**

```swift
// Sources/ClaudeStatusBarApp/Environment/AppEnvironment.swift
import Foundation
import Observation
import ClaudeStatusBarCore

@MainActor
@Observable
public final class AppEnvironment {
    public let appState = AppState()
    public let accountManager: AccountManager
    public let syncCoordinator: SyncCoordinator

    private let snapshotStore: SnapshotStore

    public init() {
        let http = URLSessionHTTPClient()
        let clock = SystemClock()
        let tokenStore = KeychainTokenStore(service: "cz.mihalic.claude-status-bar.tokens")
        let snapStore = SnapshotStore(fileURL: SnapshotStore.defaultURL())
        self.snapshotStore = snapStore

        let oauth = OAuthClient(http: http, endpoints: .production, config: .claudeCode, clock: clock)
        let login = OAuthLoginService(oauth: oauth, endpoints: .production, config: .claudeCode,
                                      tokenStore: tokenStore, opener: SystemBrowserOpener())
        let importer = ClaudeCodeImporter(
            secretReader: KeychainSecretReader(),
            fileReader: DiskFileReader(),
            configURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json"))

        self.accountManager = AccountManager(appState: appState, login: login, tokenStore: tokenStore,
                                             snapshotStore: snapStore, importer: importer)
        self.syncCoordinator = SyncCoordinator(
            appState: appState,
            engine: AccountSyncEngine(tokenStore: tokenStore, oauth: oauth,
                                      usage: UsageAPIClient(http: http), clock: clock),
            clock: clock, snapshotStore: snapStore)
    }

    public func bootstrap() {
        if let saved = try? snapshotStore.load() { saved.forEach { appState.upsert($0) } }
        syncCoordinator.start()
    }
}
```

- [ ] **Step 2: Build to verify compiles** — `swift build` → OK.

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeStatusBarApp/Environment/AppEnvironment.swift
git commit -m "feat(app): AppEnvironment composition root wiring real impls"
```

---

## Task 9: Reusable views — UsageBarView, AccountRowView

**Files:**
- Create: `Sources/ClaudeStatusBarApp/Views/UsageBarView.swift`
- Create: `Sources/ClaudeStatusBarApp/Views/AccountRowView.swift`

**Interfaces:**
- Produces SwiftUI views. `UsageBarView(window: UsageWindow, now: Date)` renders a labeled progress bar (`ProgressView(value:)` or a `GeometryReader` capsule) with `Format.percent` + `Format.resetCountdown`, tinted by `MenuBarIndicator.level(maxUtilization: window.utilization)`. `AccountRowView(account: Account, now: Date)` renders the account label + a `statusBadge` + the 3 bars (session, weekAll, first premium) using `UsageBarView`.

- [ ] **Step 1: Implement (views: verified by build + Task 14 smoke, no unit test)**

```swift
// Sources/ClaudeStatusBarApp/Views/UsageBarView.swift
import SwiftUI
import ClaudeStatusBarCore

public struct UsageBarView: View {
    let window: UsageWindow
    let now: Date
    public init(window: UsageWindow, now: Date) { self.window = window; self.now = now }

    private var tint: Color {
        switch MenuBarIndicator.level(maxUtilization: window.utilization) {
        case .critical: return .red
        case .warn: return .orange
        default: return .green
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(window.label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Format.percent(window.utilization)).font(.caption.monospacedDigit())
            }
            ProgressView(value: min(window.utilization, 100), total: 100).tint(tint)
            Text(Format.resetCountdown(to: window.resetsAt, now: now))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
```

```swift
// Sources/ClaudeStatusBarApp/Views/AccountRowView.swift
import SwiftUI
import ClaudeStatusBarCore

public struct AccountRowView: View {
    let account: Account
    let now: Date
    public init(account: Account, now: Date) { self.account = account; self.now = now }

    @ViewBuilder private var statusBadge: some View {
        switch account.status {
        case .ok:            EmptyView()
        case .rateLimited:   Label("rate-limited", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange)
        case .needsReauth:   Label("sign in", systemImage: "person.badge.key").foregroundStyle(.red)
        case .offline:       Label("offline", systemImage: "wifi.slash").foregroundStyle(.secondary)
        case .never:         Label("syncing…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(account.label).font(.headline); Spacer(); statusBadge.font(.caption) }
            if let snap = account.lastSnapshot {
                UsageBarView(window: snap.session, now: now)
                UsageBarView(window: snap.weekAll, now: now)
                if let premium = snap.weekPremium.first { UsageBarView(window: premium, now: now) }
            } else {
                Text("No data yet").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Build** — `swift build` → OK.
- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeStatusBarApp/Views/UsageBarView.swift Sources/ClaudeStatusBarApp/Views/AccountRowView.swift
git commit -m "feat(app): reusable UsageBarView + AccountRowView"
```

---

## Task 10: MenuBarContentView + DashboardView

**Files:**
- Create: `Sources/ClaudeStatusBarApp/Views/MenuBarContentView.swift`
- Create: `Sources/ClaudeStatusBarApp/Views/DashboardView.swift`

**Interfaces:**
- `MenuBarContentView(env: AppEnvironment)` — a `TimelineView(.periodic)` (1s tick, for live countdowns) listing `AccountRowView` per account, `Divider`, footer buttons: "Add Account" (opens the add sheet / window), "Open Dashboard" (`openWindow(id: "dashboard")`), "Settings…" (`SettingsLink`), "Quit". `DashboardView(env:)` — a scrollable grid of larger account cards + per-account controls (interval `Stepper`, "Remove", "Sign in again" when `needsReauth`).

- [ ] **Step 1: Implement**

```swift
// Sources/ClaudeStatusBarApp/Views/MenuBarContentView.swift
import SwiftUI

public struct MenuBarContentView: View {
    @Bindable var env: AppEnvironment
    @Environment(\.openWindow) private var openWindow
    public init(env: AppEnvironment) { self.env = env }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 8) {
                if env.appState.accounts.isEmpty {
                    Text("No accounts connected").foregroundStyle(.secondary).padding(.vertical, 6)
                } else {
                    ForEach(env.appState.accounts) { acct in
                        AccountRowView(account: acct, now: ctx.date)
                        Divider()
                    }
                }
                Button("Add Account…") { openWindow(id: "add-account") }
                Button("Open Dashboard") { openWindow(id: "dashboard") }
                SettingsLink { Text("Settings…") }
                Divider()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .padding(12)
            .frame(width: 320)
        }
    }
}
```

```swift
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
```

- [ ] **Step 2: Build** — `swift build` → OK.
- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeStatusBarApp/Views/MenuBarContentView.swift Sources/ClaudeStatusBarApp/Views/DashboardView.swift
git commit -m "feat(app): menu-bar popover + dashboard views"
```

---

## Task 11: AddAccountView + SettingsView

**Files:**
- Create: `Sources/ClaudeStatusBarApp/Views/AddAccountView.swift`
- Create: `Sources/ClaudeStatusBarApp/Views/SettingsView.swift`

**Interfaces:**
- `AddAccountView(env:)` — flow: optional "Use my Claude Code account" button (calls `detectClaudeCodeEmail`, pre-fills label) → "Sign in with Claude" (`beginAdd`, opens browser) → a paste field for the code + a label field → "Connect" (`finishAdd`), with error text via `Redaction`. `SettingsView(env:)` — default interval `Stepper` + launch-at-login `Toggle` (via `LaunchAtLogin`, Task 13).

- [ ] **Step 1: Implement**

```swift
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
```

```swift
// Sources/ClaudeStatusBarApp/Views/SettingsView.swift
import SwiftUI

public struct SettingsView: View {
    @AppStorage("defaultIntervalSeconds") private var defaultInterval = 300
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    public init() {}

    public var body: some View {
        Form {
            Stepper("Default sync interval: \(defaultInterval)s", value: $defaultInterval, in: 60...3600, step: 60)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in LaunchAtLogin.setEnabled(on) }
        }
        .padding(20).frame(width: 360)
    }
}
```

- [ ] **Step 2: Build** — `swift build` (LaunchAtLogin stub may be needed to compile; if Task 13 not yet done, add a temporary `enum LaunchAtLogin { static var isEnabled = false; static func setEnabled(_:Bool){} }` and replace in Task 13). → OK.
- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeStatusBarApp/Views/AddAccountView.swift Sources/ClaudeStatusBarApp/Views/SettingsView.swift
git commit -m "feat(app): add-account (paste-code OAuth) + settings views"
```

---

## Task 12: XcodeGen project + app target skeleton

**Files:**
- Create: `project.yml`
- Create: `App/Info.plist`
- Create: `Sources/ClaudeStatusBar/ClaudeStatusBarMain.swift`

**Interfaces:**
- Produces a buildable `.app`. `project.yml` defines app target `ClaudeStatusBar` (macOS 14, LSUIElement), local-package dependency on `ClaudeStatusBarApp`, bundle id `cz.mihalic.claude-status-bar`. `ClaudeStatusBarMain.swift` = `@main` with `MenuBarExtra` (label = indicator), a `Window("Dashboard", id: "dashboard")`, a `Window("Add Account", id: "add-account")`, and `Settings`.

> Requires Xcode. Confirm `xcodebuild -version` (Xcode 16.x) before this task. Install XcodeGen: `brew install xcodegen` (or `mint install yonaskolb/XcodeGen`).

- [ ] **Step 1: Write `project.yml`**

```yaml
name: ClaudeStatusBar
options:
  bundleIdPrefix: cz.mihalic
  deploymentTarget:
    macOS: "14.0"
packages:
  ClaudeStatusBar:
    path: .
targets:
  ClaudeStatusBar:
    type: application
    platform: macOS
    sources: [Sources/ClaudeStatusBar]
    info:
      path: App/Info.plist
      properties:
        LSUIElement: true
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: cz.mihalic.claude-status-bar
        MARKETING_VERSION: "0.1.0"
        CODE_SIGN_IDENTITY: "-"          # ad-hoc (unsigned) for local runs
        CODE_SIGNING_REQUIRED: "NO"
        CODE_SIGNING_ALLOWED: "NO"
    dependencies:
      - package: ClaudeStatusBar
        product: ClaudeStatusBarApp
```

- [ ] **Step 2: Write `App/Info.plist`** (minimal — XcodeGen merges the `properties` above)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Claude Status Bar</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
```

- [ ] **Step 3: Write `@main`**

```swift
// Sources/ClaudeStatusBar/ClaudeStatusBarMain.swift
import SwiftUI
import ClaudeStatusBarApp

@main
struct ClaudeStatusBarMain: App {
    @State private var env = AppEnvironment()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(env: env)
        } label: {
            let level = MenuBarIndicator.level(maxUtilization: env.appState.maxUtilization)
            Image(systemName: level == .critical ? "gauge.high" : level == .warn ? "gauge.medium" : "gauge.low")
            Text(MenuBarIndicator.label(maxUtilization: env.appState.maxUtilization))
        }
        .menuBarExtraStyle(.window)

        Window("Claude Usage", id: "dashboard") { DashboardView(env: env) }
        Window("Add Account", id: "add-account") { AddAccountView(env: env) }
        Settings { SettingsView() }
    }

    init() { env.bootstrap() }
}
```

- [ ] **Step 4: Generate + build**

Run:
```bash
xcodegen generate
xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar -configuration Debug build CODE_SIGNING_ALLOWED=NO
```
Expected: `** BUILD SUCCEEDED **`. Also add `ClaudeStatusBar.xcodeproj/` to `.gitignore` (generated) — commit `project.yml`, not the generated project. Add a note in README that `xcodegen generate` is required after checkout.

- [ ] **Step 5: Commit**

```bash
echo "ClaudeStatusBar.xcodeproj/" >> .gitignore
git add project.yml App/Info.plist Sources/ClaudeStatusBar/ClaudeStatusBarMain.swift .gitignore
git commit -m "feat(app): XcodeGen project + @main MenuBarExtra app skeleton"
```

---

## Task 13: Launch-at-login (SMAppService)

**Files:**
- Create: `Sources/ClaudeStatusBarApp/Environment/LaunchAtLogin.swift`
- Modify: `Sources/ClaudeStatusBarApp/Views/SettingsView.swift` (remove the temporary stub if present)

**Interfaces:**
- Produces: `enum LaunchAtLogin { static var isEnabled: Bool { get }; static func setEnabled(_ on: Bool) }` using `SMAppService.mainApp`.

- [ ] **Step 1: Implement**

```swift
// Sources/ClaudeStatusBarApp/Environment/LaunchAtLogin.swift
import Foundation
import ServiceManagement

public enum LaunchAtLogin {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    public static func setEnabled(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { /* surfaced via the toggle reverting on next read */ }
    }
}
```

- [ ] **Step 2: Build the package + app** — `swift build` and `xcodebuild ... build` → OK.
- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeStatusBarApp/Environment/LaunchAtLogin.swift Sources/ClaudeStatusBarApp/Views/SettingsView.swift
git commit -m "feat(app): launch-at-login via SMAppService"
```

---

## Task 14: End-to-end run (manual, user-assisted)

**Files:** none (verification task).

- [ ] **Step 1: Build + launch the app**

Run:
```bash
xcodegen generate
xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar -configuration Debug \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Debug/ClaudeStatusBar.app
```
Expected: a gauge icon + "—" appears in the menu bar (no accounts yet).

- [ ] **Step 2: Add a real account (user clicks through)**

Click the menu-bar icon → "Add Account…" → "Use my Claude Code account" (label pre-fills) → "Sign in with Claude…" (browser opens) → sign in → copy the code from the callback page → paste → "Connect". Approve any Keychain prompt.
Expected: the account appears with 3 usage bars within one sync cycle; the menu-bar indicator shows the max %.

- [ ] **Step 3: Verify dashboard + persistence**

Open Dashboard → large bars + reset countdowns + interval stepper. Quit and relaunch → the account + last snapshot reappear immediately (from `SnapshotStore`), then refresh.

- [ ] **Step 4: Record result**

Note in the report what appeared (bars vs. status), and any Keychain re-prompt behavior. No secret is displayed by the UI.

---

## Task 15: CI — build the app on macos-15

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Adds an app-build job (XcodeGen + xcodebuild, unsigned) alongside the existing `swift test` job, so a broken app target fails CI.

- [ ] **Step 1: Add a job**

```yaml
  app-build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Generate project
        run: xcodegen generate
      - name: Build app (unsigned)
        run: |
          xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar \
            -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

- [ ] **Step 2: Run the full package suite locally once** — `export PATH="$HOME/.swiftly/bin:$PATH" && swift test` → all pass.
- [ ] **Step 3: Commit + push, verify CI green**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: also build the macOS app target (xcodegen + xcodebuild, unsigned)"
git push
```
Then `gh run watch` → both jobs green.

---

## Self-Review (author checklist)

**Spec coverage:**
- Menu-bar widget + indicator → Tasks 3, 10, 12. ✔
- Popover with all accounts + mini bars → Tasks 9, 10. ✔
- Dashboard with large bars + reset time → Tasks 9, 10. ✔
- Add account via app's own browser OAuth (paste-code) + import-detect → Tasks 5, 6, 11. ✔ (never reuses CC token — spec §12 decision)
- Per-account sync interval (default 300 / floor 60) + 429 backoff → Tasks 4, 7. ✔
- Persistence / restore on launch (no secrets) → Tasks 6, 7, 8. ✔
- Settings (default interval, launch-at-login) → Tasks 11, 13. ✔
- Core carry-forward fixes → Task 1. ✔
- **Deferred to Plan 3:** Sparkle self-update + "Check for Updates" menu item; unsigned ZIP release + appcast + INSTALL.md; icon asset. (Distribution.)

**Placeholder scan:** no TBD/TODO; every code step has complete code. Task 11's temporary `LaunchAtLogin` stub is explicitly replaced in Task 13.

**Type consistency:** `PendingLogin`, `SyncState`, `AppEnvironment`, `AccountManager`, `SyncCoordinator`, `IndicatorLevel` names/signatures match across tasks. `Account`/`AccountStatus`/`AppState`/`UsageWindow`/`UsageSnapshot`/`SyncOutcome`/`OAuthClient`/`SyncScheduler`/`Backoff` reused from Plan 1 with their real signatures.

## Dependency ordering

`1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → (Xcode required) 12 → 13 → 14 → 15`. Tasks 1–11 are pure SPM (`swift test`, run anytime). Tasks 12–15 require Xcode (`xcodebuild`). If executing before Xcode is ready, complete 1–11 and pause at 12.
