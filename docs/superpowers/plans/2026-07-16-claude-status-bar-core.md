# claude-status-bar — Plan 1: Core Engine + CLI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a testable Swift Package (`ClaudeStatusBarCore`) that performs the full Claude usage data path — OAuth PKCE + token refresh, the `/api/oauth/usage` fetch + normalization, Keychain token storage, per-account sync engine with 429 backoff, and Claude Code account import — plus a `usage-cli` executable that imports the locally logged-in Claude Code account and prints the three usage bars. This proves the reverse-engineered endpoints work end-to-end before any UI is built.

**Architecture:** Pure Foundation/CryptoKit/Security library, no SwiftUI/AppKit, so it runs headless under `swift test`. All I/O (HTTP, Keychain, filesystem, clock) is behind protocols and injected, so every unit is tested with mocks. The CLI is a thin executable target that wires the real implementations together.

**Tech Stack:** Swift 5.9+, Swift Package Manager, Foundation, CryptoKit (SHA256), Security (Keychain + SecRandom), XCTest. macOS 14+.

## Global Constraints

- Platform floor: macOS 14 (`.macOS(.v14)` in Package.swift). Swift tools 5.9+.
- Core library MUST NOT import SwiftUI or AppKit (keep it headless-testable).
- Secrets (access/refresh tokens) live only in Keychain or in-memory; NEVER written to the snapshot JSON, NEVER logged in plaintext. All logging goes through `Redaction`.
- Public OAuth client_id (not a secret): `9d1c250a-e61b-44d9-88ed-5944d1962f5e`.
- Usage endpoint: `GET https://api.anthropic.com/api/oauth/usage` with headers `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-code/1.0.0`.
- Token hosts (try in order, domain caveat): `https://platform.claude.com/v1/oauth/token`, then `https://console.anthropic.com/v1/oauth/token`.
- Sync interval: default 300s, hard floor 60s. Backoff steps on 429: 30→60→120→240→300s (cap).
- Bundle id / keychain service base: `cz.mihalic.claude-status-bar`.
- TDD: every unit gets a failing test first. Reproduce bugs with a failing test before fixing (repo rule).

### TESTING ADDENDUM (environment reality — binding for every task)

This machine has **no Xcode.app** (only CommandLineTools), so **XCTest is unavailable**. A swift.org toolchain (Swift 6.3.3) is installed and wrapped on PATH. Therefore:

- **Run tests with the toolchain wrapper.** At the start of every shell that builds/tests:
  ```bash
  export PATH="$HOME/.swiftly/bin:$PATH"   # routes `swift` to swift-6.3.3-RELEASE (has swift-testing + macOS SDK: CryptoKit/Security/Observation all work)
  swift --version                          # must print: Apple Swift version 6.3.3 (swift-6.3.3-RELEASE)
  swift test --filter <Name>
  ```
- **Use swift-testing, NOT XCTest.** The test code shown inside each task is written in XCTest **as a behavioral spec** — the assertions and behaviors it asserts are binding; the XCTest *syntax* is not. Implement the same assertions in swift-testing. Conversion is deterministic:

  | XCTest (spec) | swift-testing (write this) |
  |---|---|
  | `import XCTest` | `import Testing` |
  | `final class FooTests: XCTestCase { func test_x() {...} }` | top-level `@Test func x() {...}` (a `struct FooTests { @Test ... }` suite is fine too) |
  | `func test_x() async throws` | `@Test func x() async throws` (async/throws native) |
  | `XCTAssertEqual(a, b)` | `#expect(a == b)` |
  | `XCTAssertTrue(c)` / `XCTAssertFalse(c)` | `#expect(c)` / `#expect(!c)` |
  | `XCTAssertNil(o)` / `XCTAssertNotNil(o)` | `#expect(o == nil)` / `#expect(o != nil)` |
  | `let v = try XCTUnwrap(o)` | `let v = try #require(o)` |
  | `XCTAssertThrowsError(try f()) { XCTAssertEqual($0 as? E, .x) }` | `#expect(throws: E.x) { try f() }` (or `#expect { try f() } throws: { ($0 as? E) == .x }`) |
  | async throwing assertion | `await #expect(throws: E.self) { try await f() }` — drop the custom `XCTAssertThrowsErrorAsync` helper; it is not needed |
  | `try XCTSkipUnless(cond)` | gate the test: `@Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_KEYCHAIN_TESTS"] == "1")) func ...` |
  | `XCTFail("msg")` | `Issue.record("msg")` |
  | `Bundle.module.url(forResource:…, subdirectory: "Fixtures")` | unchanged — `Bundle.module` works the same for the test target |

- **Fixtures resource:** any test target declaring `resources: [.copy("Fixtures")]` MUST have the `Tests/ClaudeStatusBarCoreTests/Fixtures/` directory exist in git. Until a task adds real fixture files there, commit a tracked `Tests/ClaudeStatusBarCoreTests/Fixtures/.gitkeep` so a fresh clone builds.
- RED/GREEN evidence uses `swift test` output from the toolchain wrapper (swift-testing prints `✔ Test … passed` / `✘ … failed`).

---

## File Structure

```
Package.swift
Sources/
  ClaudeStatusBarCore/
    Util/Base64URL.swift            base64url encode
    Util/Redaction.swift            secret masking for logs
    Crypto/PKCE.swift               code verifier/challenge (S256)
    HTTP/HTTPClient.swift           protocol + HTTPResponse + URLSession impl
    OAuth/OAuthConfig.swift         client_id, scopes, redirect
    OAuth/OAuthEndpoints.swift      authorize URL + token host list
    OAuth/OAuthRequests.swift       exchange/refresh URLRequest builders
    OAuth/TokenBundle.swift         tokens + expiry math
    OAuth/OAuthClient.swift         exchange/refresh via HTTPClient (+ host fallback)
    Usage/UsageDTO.swift            Decodable response (dynamic per-model keys)
    Usage/UsageSnapshot.swift       normalized domain model
    Usage/UsageAdapter.swift        DTO -> UsageSnapshot
    Usage/UsageAPIClient.swift      GET /api/oauth/usage -> UsageSnapshot
    Storage/TokenStore.swift        protocol
    Storage/KeychainTokenStore.swift Security-backed impl
    Storage/InMemoryTokenStore.swift mock (shipped for app + tests)
    Storage/SnapshotStore.swift     account metadata + last snapshot (no secrets)
    Sync/Clock.swift                Clock protocol + System/Manual
    Sync/Backoff.swift              429 backoff steps
    Sync/AccountSyncEngine.swift    syncOnce(accountID) -> SyncOutcome
    Sync/SyncScheduler.swift        next-fire interval calculation
    Model/Account.swift             Account + AccountStatus
    Model/AppState.swift            @Observable aggregate + maxUtilization
    Import/ClaudeCodeImporter.swift import from Claude Code keychain + ~/.claude.json
  usage-cli/
    main.swift                      import CC account -> fetch -> print bars
Tests/
  ClaudeStatusBarCoreTests/
    Fixtures/usage_full.json, usage_null_permodel.json, usage_unknown_model.json,
             usage_malformed.json, cc_credentials.json, claude_config.json
    Mocks/MockHTTPClient.swift, Mocks/ManualClock.swift
    Base64URLTests.swift, RedactionTests.swift, PKCETests.swift,
    OAuthRequestsTests.swift, OAuthClientTests.swift, TokenBundleTests.swift,
    UsageDecodingTests.swift, UsageAdapterTests.swift, UsageAPIClientTests.swift,
    TokenStoreTests.swift, SnapshotStoreTests.swift, BackoffTests.swift,
    AccountSyncEngineTests.swift, SyncSchedulerTests.swift,
    AppStateTests.swift, ClaudeCodeImporterTests.swift
```

---

## Task 0: Package skeleton

**Files:**
- Create: `Package.swift`
- Create: `Sources/ClaudeStatusBarCore/Util/Base64URL.swift`
- Test: `Tests/ClaudeStatusBarCoreTests/Base64URLTests.swift`

**Interfaces:**
- Produces: `enum Base64URL { static func encode(_ data: Data) -> String }`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeStatusBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClaudeStatusBarCore", targets: ["ClaudeStatusBarCore"]),
        .executable(name: "usage-cli", targets: ["usage-cli"]),
    ],
    targets: [
        .target(name: "ClaudeStatusBarCore"),
        .executableTarget(
            name: "usage-cli",
            dependencies: ["ClaudeStatusBarCore"]
        ),
        .testTarget(
            name: "ClaudeStatusBarCoreTests",
            dependencies: ["ClaudeStatusBarCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 2: Write the failing test**

```swift
// Tests/ClaudeStatusBarCoreTests/Base64URLTests.swift
import XCTest
@testable import ClaudeStatusBarCore

final class Base64URLTests: XCTestCase {
    func test_encode_isURLSafe_andUnpadded() {
        // 0xFB 0xFF -> standard base64 "+/8=" ; url-safe unpadded -> "-_8"
        let out = Base64URL.encode(Data([0xFB, 0xFF]))
        XCTAssertEqual(out, "-_8")
        XCTAssertFalse(out.contains("="))
        XCTAssertFalse(out.contains("+"))
        XCTAssertFalse(out.contains("/"))
    }
}
```

- [ ] **Step 3: Run to verify fail**

Run: `swift test --filter Base64URLTests`
Expected: FAIL (`Base64URL` not found / no such module symbol).

- [ ] **Step 4: Implement**

```swift
// Sources/ClaudeStatusBarCore/Util/Base64URL.swift
import Foundation

public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `swift test --filter Base64URLTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/ClaudeStatusBarCore/Util/Base64URL.swift Tests/ClaudeStatusBarCoreTests/Base64URLTests.swift
git commit -m "feat(core): package skeleton + base64url encoder"
```

---

## Task 1: Secret redaction

**Files:**
- Create: `Sources/ClaudeStatusBarCore/Util/Redaction.swift`
- Test: `Tests/ClaudeStatusBarCoreTests/RedactionTests.swift`

**Interfaces:**
- Produces: `enum Redaction { static func redact(_ text: String) -> String }`

- [ ] **Step 1: Failing test**

```swift
// Tests/ClaudeStatusBarCoreTests/RedactionTests.swift
import XCTest
@testable import ClaudeStatusBarCore

final class RedactionTests: XCTestCase {
    func test_masksAnthropicTokens() {
        let s = "auth=sk-ant-oat01-ABCdef123-_ end refresh=sk-ant-ort01-ZZZ999 done"
        let r = Redaction.redact(s)
        XCTAssertFalse(r.contains("ABCdef123"))
        XCTAssertFalse(r.contains("ZZZ999"))
        XCTAssertTrue(r.contains("sk-ant-oat01-***"))
        XCTAssertTrue(r.contains("sk-ant-ort01-***"))
        XCTAssertTrue(r.contains("done"))
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter RedactionTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
// Sources/ClaudeStatusBarCore/Util/Redaction.swift
import Foundation

public enum Redaction {
    // Matches sk-ant-<kind>01- followed by the secret body; keeps the prefix, masks the body.
    private static let pattern = try! NSRegularExpression(
        pattern: "(sk-ant-[a-z]+[0-9]*-)[A-Za-z0-9._-]+"
    )

    public static func redact(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.stringByReplacingMatches(
            in: text, range: range, withTemplate: "$1***"
        )
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter RedactionTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatusBarCore/Util/Redaction.swift Tests/ClaudeStatusBarCoreTests/RedactionTests.swift
git commit -m "feat(core): secret redaction for logs"
```

---

## Task 2: PKCE (code verifier + S256 challenge)

**Files:**
- Create: `Sources/ClaudeStatusBarCore/Crypto/PKCE.swift`
- Test: `Tests/ClaudeStatusBarCoreTests/PKCETests.swift`

**Interfaces:**
- Consumes: `Base64URL.encode`
- Produces: `struct PKCE { let verifier: String; let challenge: String; static func generate() -> PKCE; static func challenge(for verifier: String) -> String }`

- [ ] **Step 1: Failing test**

```swift
// Tests/ClaudeStatusBarCoreTests/PKCETests.swift
import XCTest
import CryptoKit
@testable import ClaudeStatusBarCore

final class PKCETests: XCTestCase {
    func test_challenge_isBase64URLSha256OfVerifier() {
        // RFC 7636 Appendix B known vector.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        XCTAssertEqual(PKCE.challenge(for: verifier), expected)
    }

    func test_generate_producesValidPair() {
        let p = PKCE.generate()
        XCTAssertTrue((43...128).contains(p.verifier.count))
        XCTAssertEqual(PKCE.challenge(for: p.verifier), p.challenge)
        // URL-safe charset only
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertNil(p.verifier.unicodeScalars.first { !allowed.contains($0) })
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter PKCETests`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
// Sources/ClaudeStatusBarCore/Crypto/PKCE.swift
import Foundation
import CryptoKit
import Security

public struct PKCE: Equatable {
    public let verifier: String
    public let challenge: String

    public static func generate() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        // Fail loudly rather than silently returning a predictable (zeroed) verifier.
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        let verifier = Base64URL.encode(Data(bytes)) // 43 chars, url-safe
        return PKCE(verifier: verifier, challenge: challenge(for: verifier))
    }

    public static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Base64URL.encode(Data(digest))
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter PKCETests`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatusBarCore/Crypto/PKCE.swift Tests/ClaudeStatusBarCoreTests/PKCETests.swift
git commit -m "feat(core): PKCE S256 verifier/challenge"
```

---

## Task 3: HTTP client abstraction + mock

**Files:**
- Create: `Sources/ClaudeStatusBarCore/HTTP/HTTPClient.swift`
- Create: `Tests/ClaudeStatusBarCoreTests/Mocks/MockHTTPClient.swift`

**Interfaces:**
- Produces:
  - `struct HTTPResponse { let status: Int; let headers: [String: String]; let body: Data }`
  - `protocol HTTPClient { func send(_ request: URLRequest) async throws -> HTTPResponse }`
  - `struct URLSessionHTTPClient: HTTPClient` (wraps `URLSession`)
  - Test mock `final class MockHTTPClient: HTTPClient` with a scriptable handler and a `lastRequest` capture.

- [ ] **Step 1: Implement the protocol + real client (no test yet — it's infrastructure consumed by later tested units)**

```swift
// Sources/ClaudeStatusBarCore/HTTP/HTTPClient.swift
import Foundation

public struct HTTPResponse: Equatable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status; self.headers = headers; self.body = body
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        var headers: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            if let ks = k as? String, let vs = v as? String { headers[ks] = vs }
        }
        return HTTPResponse(status: http.statusCode, headers: headers, body: data)
    }
}
```

- [ ] **Step 2: Implement the mock**

```swift
// Tests/ClaudeStatusBarCoreTests/Mocks/MockHTTPClient.swift
import Foundation
@testable import ClaudeStatusBarCore

final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    var handler: (URLRequest) throws -> HTTPResponse
    private(set) var requests: [URLRequest] = []
    var lastRequest: URLRequest? { requests.last }

    init(handler: @escaping (URLRequest) throws -> HTTPResponse = { _ in
        HTTPResponse(status: 200, headers: [:], body: Data())
    }) { self.handler = handler }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        return try handler(request)
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeStatusBarCore/HTTP/HTTPClient.swift Tests/ClaudeStatusBarCoreTests/Mocks/MockHTTPClient.swift
git commit -m "feat(core): HTTPClient protocol + URLSession impl + test mock"
```

---

## Task 4: OAuth config, endpoints, authorize URL

**Files:**
- Create: `Sources/ClaudeStatusBarCore/OAuth/OAuthConfig.swift`
- Create: `Sources/ClaudeStatusBarCore/OAuth/OAuthEndpoints.swift`
- Test: `Tests/ClaudeStatusBarCoreTests/OAuthRequestsTests.swift` (authorize part)

**Interfaces:**
- Produces:
  - `struct OAuthConfig { let clientID: String; let scopes: [String]; let redirectURI: String; static let claudeCode: OAuthConfig }`
  - `struct OAuthEndpoints { let authorizeBase: URL; let tokenHosts: [URL]; static let production: OAuthEndpoints; func authorizeURL(config: OAuthConfig, pkce: PKCE, state: String) -> URL }`

- [ ] **Step 1: Failing test**

```swift
// Tests/ClaudeStatusBarCoreTests/OAuthRequestsTests.swift
import XCTest
@testable import ClaudeStatusBarCore

final class OAuthRequestsTests: XCTestCase {
    func test_authorizeURL_hasRequiredParams() {
        let pkce = PKCE(verifier: "v", challenge: "chal")
        let url = OAuthEndpoints.production.authorizeURL(
            config: .claudeCode, pkce: pkce, state: "st8"
        )
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let q = Dictionary(uniqueKeysWithValues:
            comps.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(comps.host, "claude.ai")
        XCTAssertEqual(comps.path, "/oauth/authorize")
        XCTAssertEqual(q["response_type"], "code")
        XCTAssertEqual(q["client_id"], "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
        XCTAssertEqual(q["code_challenge"], "chal")
        XCTAssertEqual(q["code_challenge_method"], "S256")
        XCTAssertEqual(q["state"], "st8")
        XCTAssertEqual(q["redirect_uri"],
            "https://console.anthropic.com/oauth/code/callback")
        XCTAssertTrue(q["scope"]!.contains("user:profile"))
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter OAuthRequestsTests/test_authorizeURL_hasRequiredParams`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
// Sources/ClaudeStatusBarCore/OAuth/OAuthConfig.swift
import Foundation

public struct OAuthConfig: Equatable, Sendable {
    public let clientID: String
    public let scopes: [String]
    public let redirectURI: String

    public init(clientID: String, scopes: [String], redirectURI: String) {
        self.clientID = clientID; self.scopes = scopes; self.redirectURI = redirectURI
    }

    // Full browser login: user:profile is required for /api/oauth/usage.
    public static let claudeCode = OAuthConfig(
        clientID: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        scopes: ["org:create_api_key", "user:profile", "user:inference"],
        redirectURI: "https://console.anthropic.com/oauth/code/callback"
    )
}
```

```swift
// Sources/ClaudeStatusBarCore/OAuth/OAuthEndpoints.swift
import Foundation

public struct OAuthEndpoints: Sendable {
    public let authorizeBase: URL
    public let tokenHosts: [URL]   // tried in order (domain caveat)

    public init(authorizeBase: URL, tokenHosts: [URL]) {
        self.authorizeBase = authorizeBase; self.tokenHosts = tokenHosts
    }

    public static let production = OAuthEndpoints(
        authorizeBase: URL(string: "https://claude.ai/oauth/authorize")!,
        tokenHosts: [
            URL(string: "https://platform.claude.com/v1/oauth/token")!,
            URL(string: "https://console.anthropic.com/v1/oauth/token")!,
        ]
    )

    public func authorizeURL(config: OAuthConfig, pkce: PKCE, state: String) -> URL {
        var comps = URLComponents(url: authorizeBase, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: config.clientID),
            .init(name: "redirect_uri", value: config.redirectURI),
            .init(name: "scope", value: config.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        return comps.url!
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter OAuthRequestsTests/test_authorizeURL_hasRequiredParams`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatusBarCore/OAuth/OAuthConfig.swift Sources/ClaudeStatusBarCore/OAuth/OAuthEndpoints.swift Tests/ClaudeStatusBarCoreTests/OAuthRequestsTests.swift
git commit -m "feat(core): OAuth config + authorize URL builder"
```

---

## Task 5: TokenBundle + expiry math

**Files:**
- Create: `Sources/ClaudeStatusBarCore/OAuth/TokenBundle.swift`
- Test: `Tests/ClaudeStatusBarCoreTests/TokenBundleTests.swift`

**Interfaces:**
- Produces:
  - `struct TokenBundle: Codable, Equatable { var accessToken: String; var refreshToken: String; var expiresAt: Date; var scopes: [String]; func isExpiring(within: TimeInterval, now: Date) -> Bool }`
  - `struct TokenResponse: Decodable` (access_token, refresh_token, expires_in, scope) + `func bundle(now: Date) -> TokenBundle`

- [ ] **Step 1: Failing test**

```swift
// Tests/ClaudeStatusBarCoreTests/TokenBundleTests.swift
import XCTest
@testable import ClaudeStatusBarCore

final class TokenBundleTests: XCTestCase {
    func test_isExpiring_true_whenWithinWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let b = TokenBundle(accessToken: "a", refreshToken: "r",
                            expiresAt: now.addingTimeInterval(200), scopes: [])
        XCTAssertTrue(b.isExpiring(within: 300, now: now))
        XCTAssertFalse(b.isExpiring(within: 100, now: now))
    }

    func test_tokenResponse_computesExpiresAt() throws {
        let json = #"{"access_token":"AT","refresh_token":"RT","expires_in":28800,"scope":"user:profile"}"#
        let resp = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
        let now = Date(timeIntervalSince1970: 0)
        let b = resp.bundle(now: now)
        XCTAssertEqual(b.accessToken, "AT")
        XCTAssertEqual(b.refreshToken, "RT")
        XCTAssertEqual(b.expiresAt, Date(timeIntervalSince1970: 28800))
        XCTAssertEqual(b.scopes, ["user:profile"])
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter TokenBundleTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
// Sources/ClaudeStatusBarCore/OAuth/TokenBundle.swift
import Foundation

public struct TokenBundle: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var scopes: [String]

    public init(accessToken: String, refreshToken: String,
                expiresAt: Date, scopes: [String]) {
        self.accessToken = accessToken; self.refreshToken = refreshToken
        self.expiresAt = expiresAt; self.scopes = scopes
    }

    public func isExpiring(within seconds: TimeInterval, now: Date) -> Bool {
        expiresAt.timeIntervalSince(now) <= seconds
    }
}

public struct TokenResponse: Decodable, Sendable {
    public let access_token: String
    public let refresh_token: String
    public let expires_in: Double
    public let scope: String?

    public func bundle(now: Date) -> TokenBundle {
        TokenBundle(
            accessToken: access_token,
            refreshToken: refresh_token,
            expiresAt: now.addingTimeInterval(expires_in),
            scopes: (scope ?? "").split(separator: " ").map(String.init)
        )
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter TokenBundleTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatusBarCore/OAuth/TokenBundle.swift Tests/ClaudeStatusBarCoreTests/TokenBundleTests.swift
git commit -m "feat(core): TokenBundle + token response expiry math"
```

---

## Task 6: OAuth request builders (exchange + refresh)

**Files:**
- Create: `Sources/ClaudeStatusBarCore/OAuth/OAuthRequests.swift`
- Modify: `Tests/ClaudeStatusBarCoreTests/OAuthRequestsTests.swift` (add cases)

**Interfaces:**
- Produces:
  - `enum OAuthRequests { static func exchange(tokenURL: URL, config: OAuthConfig, code: String, verifier: String, state: String) -> URLRequest; static func refresh(tokenURL: URL, config: OAuthConfig, refreshToken: String) -> URLRequest }`
- Consumes: `OAuthConfig`

- [ ] **Step 1: Failing test (append to OAuthRequestsTests)**

```swift
extension OAuthRequestsTests {
    func test_exchangeRequest_isFormURLEncodedPOST() {
        let req = OAuthRequests.exchange(
            tokenURL: URL(string: "https://platform.claude.com/v1/oauth/token")!,
            config: .claudeCode, code: "CODE", verifier: "VER", state: "ST")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"),
                       "application/x-www-form-urlencoded")
        let body = String(data: req.httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("code=CODE"))
        XCTAssertTrue(body.contains("code_verifier=VER"))
        XCTAssertTrue(body.contains("state=ST"))
        XCTAssertTrue(body.contains("client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e"))
    }

    func test_refreshRequest_hasGrantTypeRefresh() {
        let req = OAuthRequests.refresh(
            tokenURL: URL(string: "https://platform.claude.com/v1/oauth/token")!,
            config: .claudeCode, refreshToken: "RT")
        let body = String(data: req.httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("grant_type=refresh_token"))
        XCTAssertTrue(body.contains("refresh_token=RT"))
        XCTAssertTrue(body.contains("client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e"))
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter OAuthRequestsTests`
Expected: FAIL on the two new tests.

- [ ] **Step 3: Implement**

```swift
// Sources/ClaudeStatusBarCore/OAuth/OAuthRequests.swift
import Foundation

public enum OAuthRequests {
    private static func form(_ pairs: [(String, String)]) -> Data {
        var comps = URLComponents()
        comps.queryItems = pairs.map { URLQueryItem(name: $0.0, value: $0.1) }
        // percentEncodedQuery uses form encoding; ensure "+" in values is escaped.
        let s = (comps.percentEncodedQuery ?? "")
            .replacingOccurrences(of: "+", with: "%2B")
        return Data(s.utf8)
    }

    private static func post(_ url: URL, _ pairs: [(String, String)]) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded",
                     forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = form(pairs)
        return req
    }

    public static func exchange(tokenURL: URL, config: OAuthConfig,
                                code: String, verifier: String,
                                state: String) -> URLRequest {
        post(tokenURL, [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", config.redirectURI),
            ("client_id", config.clientID),
            ("code_verifier", verifier),
            ("state", state),
        ])
    }

    public static func refresh(tokenURL: URL, config: OAuthConfig,
                               refreshToken: String) -> URLRequest {
        post(tokenURL, [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", config.clientID),
        ])
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter OAuthRequestsTests`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatusBarCore/OAuth/OAuthRequests.swift Tests/ClaudeStatusBarCoreTests/OAuthRequestsTests.swift
git commit -m "feat(core): OAuth exchange + refresh request builders"
```

---

## Task 7: OAuthClient (exchange/refresh with host fallback)

**Files:**
- Create: `Sources/ClaudeStatusBarCore/OAuth/OAuthClient.swift`
- Test: `Tests/ClaudeStatusBarCoreTests/OAuthClientTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`, `OAuthEndpoints`, `OAuthConfig`, `OAuthRequests`, `TokenResponse`, `TokenBundle`, `Clock`
- Produces:
  - `enum OAuthError: Error, Equatable { case invalidGrant; case http(Int); case allHostsFailed; case decoding }`
  - `struct OAuthClient { init(http: HTTPClient, endpoints: OAuthEndpoints, config: OAuthConfig, clock: Clock); func exchange(code: String, verifier: String, state: String) async throws -> TokenBundle; func refresh(_ bundle: TokenBundle) async throws -> TokenBundle }`

> Note: `Clock` is defined in Task 12. Implement Task 12 before this task, OR define `Clock` first. Recommended order: do Task 12 (Clock+Backoff) before Task 7. The plan lists Clock's full definition in Task 12.

- [ ] **Step 1: Failing test**

```swift
// Tests/ClaudeStatusBarCoreTests/OAuthClientTests.swift
import XCTest
@testable import ClaudeStatusBarCore

final class OAuthClientTests: XCTestCase {
    private func ok(_ json: String) -> HTTPResponse {
        HTTPResponse(status: 200, headers: [:], body: Data(json.utf8))
    }

    func test_exchange_decodesBundle() async throws {
        let http = MockHTTPClient { _ in
            self.ok(#"{"access_token":"AT","refresh_token":"RT","expires_in":28800,"scope":"user:profile"}"#)
        }
        let client = OAuthClient(http: http, endpoints: .production,
                                 config: .claudeCode,
                                 clock: ManualClock(Date(timeIntervalSince1970: 0)))
        let b = try await client.exchange(code: "C", verifier: "V", state: "S")
        XCTAssertEqual(b.accessToken, "AT")
        XCTAssertEqual(b.expiresAt, Date(timeIntervalSince1970: 28800))
    }

    func test_refresh_fallsBackToSecondHost_onFirstHostFailure() async throws {
        let http = MockHTTPClient { req in
            if req.url!.host == "platform.claude.com" {
                return HTTPResponse(status: 500, headers: [:], body: Data())
            }
            return self.ok(#"{"access_token":"AT2","refresh_token":"RT2","expires_in":100,"scope":""}"#)
        }
        let client = OAuthClient(http: http, endpoints: .production,
                                 config: .claudeCode,
                                 clock: ManualClock(Date(timeIntervalSince1970: 0)))
        let b = try await client.refresh(
            TokenBundle(accessToken: "x", refreshToken: "RT",
                        expiresAt: .init(timeIntervalSince1970: 0), scopes: []))
        XCTAssertEqual(b.accessToken, "AT2")
    }

    func test_exchange_throwsInvalidGrant_on400() async {
        let http = MockHTTPClient { _ in
            HTTPResponse(status: 400, headers: [:],
                         body: Data(#"{"error":"invalid_grant"}"#.utf8))
        }
        let client = OAuthClient(http: http, endpoints: .production,
                                 config: .claudeCode,
                                 clock: ManualClock(.init(timeIntervalSince1970: 0)))
        do { _ = try await client.exchange(code: "C", verifier: "V", state: "S")
             XCTFail("expected throw")
        } catch { XCTAssertEqual(error as? OAuthError, .invalidGrant) }
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter OAuthClientTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
// Sources/ClaudeStatusBarCore/OAuth/OAuthClient.swift
import Foundation

public enum OAuthError: Error, Equatable {
    case invalidGrant
    case http(Int)
    case allHostsFailed
    case decoding
}

public struct OAuthClient: Sendable {
    private let http: HTTPClient
    private let endpoints: OAuthEndpoints
    private let config: OAuthConfig
    private let clock: Clock

    public init(http: HTTPClient, endpoints: OAuthEndpoints,
                config: OAuthConfig, clock: Clock) {
        self.http = http; self.endpoints = endpoints
        self.config = config; self.clock = clock
    }

    public func exchange(code: String, verifier: String,
                         state: String) async throws -> TokenBundle {
        try await perform { host in
            OAuthRequests.exchange(tokenURL: host, config: config,
                                   code: code, verifier: verifier, state: state)
        }
    }

    public func refresh(_ bundle: TokenBundle) async throws -> TokenBundle {
        try await perform { host in
            OAuthRequests.refresh(tokenURL: host, config: config,
                                  refreshToken: bundle.refreshToken)
        }
    }

    private func perform(_ build: (URL) -> URLRequest) async throws -> TokenBundle {
        var lastError: OAuthError = .allHostsFailed
        for host in endpoints.tokenHosts {
            let resp: HTTPResponse
            do { resp = try await http.send(build(host)) }
            catch { lastError = .allHostsFailed; continue }

            switch resp.status {
            case 200:
                do {
                    let tr = try JSONDecoder().decode(TokenResponse.self, from: resp.body)
                    return tr.bundle(now: clock.now())
                } catch { throw OAuthError.decoding }
            case 400:
                throw OAuthError.invalidGrant   // don't retry other host on bad grant
            default:
                lastError = .http(resp.status)   // try next host
            }
        }
        throw lastError
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter OAuthClientTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatusBarCore/OAuth/OAuthClient.swift Tests/ClaudeStatusBarCoreTests/OAuthClientTests.swift
git commit -m "feat(core): OAuthClient exchange/refresh with host fallback"
```

---

## Task 8: Usage DTO decoding (dynamic per-model keys)

**Files:**
- Create: `Sources/ClaudeStatusBarCore/Usage/UsageDTO.swift`
- Create fixtures: `Tests/ClaudeStatusBarCoreTests/Fixtures/usage_full.json`, `usage_null_permodel.json`, `usage_unknown_model.json`, `usage_malformed.json`
- Test: `Tests/ClaudeStatusBarCoreTests/UsageDecodingTests.swift`

**Interfaces:**
- Produces:
  - `struct UsageWindowDTO: Decodable, Equatable { let utilization: Double; let resetsAt: Date }`
  - `struct UsageResponseDTO: Decodable { let windows: [String: UsageWindowDTO] }` (dynamic keys; non-window keys like `extra_usage` and any `null` values are skipped)
  - `enum UsageJSON { static func decoder() -> JSONDecoder }` (ISO-8601 w/ fractional seconds)

- [ ] **Step 1: Create fixtures**

`Tests/ClaudeStatusBarCoreTests/Fixtures/usage_full.json`:
```json
{
  "five_hour": { "utilization": 33.0, "resets_at": "2026-04-11T07:00:00.528743+00:00" },
  "seven_day": { "utilization": 13.0, "resets_at": "2026-04-17T00:59:59.951713+00:00" },
  "seven_day_opus": null,
  "seven_day_sonnet": { "utilization": 1.0, "resets_at": "2026-04-16T03:00:00.951719+00:00" },
  "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
}
```

`Tests/ClaudeStatusBarCoreTests/Fixtures/usage_null_permodel.json`:
```json
{
  "five_hour": { "utilization": 5.0, "resets_at": "2026-04-11T07:00:00+00:00" },
  "seven_day": { "utilization": 2.0, "resets_at": "2026-04-17T00:59:59+00:00" },
  "seven_day_opus": null,
  "seven_day_sonnet": null,
  "extra_usage": { "is_enabled": false }
}
```

`Tests/ClaudeStatusBarCoreTests/Fixtures/usage_unknown_model.json`:
```json
{
  "five_hour": { "utilization": 50.0, "resets_at": "2026-07-16T12:00:00+00:00" },
  "seven_day": { "utilization": 40.0, "resets_at": "2026-07-20T00:00:00+00:00" },
  "seven_day_fable": { "utilization": 12.0, "resets_at": "2026-07-20T00:00:00+00:00" },
  "extra_usage": { "is_enabled": true, "utilization": 3.0 }
}
```

`Tests/ClaudeStatusBarCoreTests/Fixtures/usage_malformed.json`:
```json
{ "five_hour": "not-an-object", "seven_day": 123 }
```

- [ ] **Step 2: Failing test**

```swift
// Tests/ClaudeStatusBarCoreTests/UsageDecodingTests.swift
import XCTest
@testable import ClaudeStatusBarCore

final class UsageDecodingTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json",
                                    subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func test_full_decodesWindows_skipsNullAndExtraUsage() throws {
        let dto = try UsageJSON.decoder()
            .decode(UsageResponseDTO.self, from: fixture("usage_full"))
        XCTAssertEqual(dto.windows["five_hour"]?.utilization, 33.0)
        XCTAssertEqual(dto.windows["seven_day"]?.utilization, 13.0)
        XCTAssertNotNil(dto.windows["seven_day_sonnet"])
        XCTAssertNil(dto.windows["seven_day_opus"])     // null -> dropped
        XCTAssertNil(dto.windows["extra_usage"])        // wrong shape -> dropped
    }

    func test_unknownModelKey_isCaptured() throws {
        let dto = try UsageJSON.decoder()
            .decode(UsageResponseDTO.self, from: fixture("usage_unknown_model"))
        XCTAssertEqual(dto.windows["seven_day_fable"]?.utilization, 12.0)
    }

    func test_malformed_windowsAreDropped_notThrown() throws {
        let dto = try UsageJSON.decoder()
            .decode(UsageResponseDTO.self, from: fixture("usage_malformed"))
        XCTAssertTrue(dto.windows.isEmpty)
    }
}
```

- [ ] **Step 3: Run to verify fail**

Run: `swift test --filter UsageDecodingTests`
Expected: FAIL.

- [ ] **Step 4: Implement**

```swift
// Sources/ClaudeStatusBarCore/Usage/UsageDTO.swift
import Foundation

public struct UsageWindowDTO: Decodable, Equatable, Sendable {
    public let utilization: Double
    public let resetsAt: Date
    enum CodingKeys: String, CodingKey { case utilization; case resetsAt = "resets_at" }
}

public struct UsageResponseDTO: Decodable, Sendable {
    public let windows: [String: UsageWindowDTO]

    private struct DynamicKey: CodingKey {
        var stringValue: String; var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil == nil ? self.stringValue = "" : (); return nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var result: [String: UsageWindowDTO] = [:]
        for key in container.allKeys {
            // Try to decode each value as a window; skip nulls and other shapes.
            if let w = try? container.decode(UsageWindowDTO.self, forKey: key) {
                result[key.stringValue] = w
            }
        }
        self.windows = result
    }
}

public enum UsageJSON {
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fmtNoFrac = ISO8601DateFormatter()
        fmtNoFrac.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = fmt.date(from: s) ?? fmtNoFrac.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }
}
```

> Note: the `DynamicKey.init(intValue:)` above must simply return nil. Use this exact minimal form instead:
> ```swift
> init?(intValue: Int) { return nil }
> init?(stringValue: String) { self.stringValue = stringValue }
> var intValue: Int? { nil }
> ```

- [ ] **Step 5: Fix DynamicKey to the clean form, then run to verify pass**

Replace the `DynamicKey` struct body with:
```swift
private struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
```
Run: `swift test --filter UsageDecodingTests`
Expected: PASS (all three).

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeStatusBarCore/Usage/UsageDTO.swift Tests/ClaudeStatusBarCoreTests/Fixtures Tests/ClaudeStatusBarCoreTests/UsageDecodingTests.swift
git commit -m "feat(core): usage response DTO with dynamic per-model keys"
```

---

## Task 9: UsageSnapshot + UsageAdapter

**Files:**
- Create: `Sources/ClaudeStatusBarCore/Usage/UsageSnapshot.swift`
- Create: `Sources/ClaudeStatusBarCore/Usage/UsageAdapter.swift`
- Test: `Tests/ClaudeStatusBarCoreTests/UsageAdapterTests.swift`

**Interfaces:**
- Consumes: `UsageResponseDTO`
- Produces:
  - `struct UsageWindow: Codable, Equatable { let key: String; let label: String; let utilization: Double; let resetsAt: Date }`
  - `struct UsageSnapshot: Codable, Equatable { let session: UsageWindow; let weekAll: UsageWindow; let weekPremium: [UsageWindow]; let fetchedAt: Date }`
  - `enum UsageAdapterError: Error { case missingCoreWindows }`
  - `enum UsageAdapter { static func normalize(_ dto: UsageResponseDTO, fetchedAt: Date) throws -> UsageSnapshot; static func label(forKey: String) -> String }`

- [ ] **Step 1: Failing test**

```swift
// Tests/ClaudeStatusBarCoreTests/UsageAdapterTests.swift
import XCTest
@testable import ClaudeStatusBarCore

final class UsageAdapterTests: XCTestCase {
    private func dto(_ name: String) throws -> UsageResponseDTO {
        let url = Bundle.module.url(forResource: name, withExtension: "json",
                                    subdirectory: "Fixtures")!
        return try UsageJSON.decoder().decode(UsageResponseDTO.self,
                                              from: Data(contentsOf: url))
    }

    func test_normalize_full_mapsWindowsAndLabels() throws {
        let snap = try UsageAdapter.normalize(dto("usage_full"),
                                              fetchedAt: .init(timeIntervalSince1970: 0))
        XCTAssertEqual(snap.session.label, "Session")
        XCTAssertEqual(snap.session.utilization, 33.0)
        XCTAssertEqual(snap.weekAll.label, "Week (all)")
        XCTAssertEqual(snap.weekPremium.map(\.key), ["seven_day_sonnet"])
        XCTAssertEqual(snap.weekPremium.first?.label, "Week (Sonnet)")
    }

    func test_normalize_unknownModel_labelsFromKey() throws {
        let snap = try UsageAdapter.normalize(dto("usage_unknown_model"),
                                              fetchedAt: .init(timeIntervalSince1970: 0))
        XCTAssertEqual(snap.weekPremium.map(\.key), ["seven_day_fable"])
        XCTAssertEqual(snap.weekPremium.first?.label, "Week (Fable)")
    }

    func test_normalize_missingCoreWindows_throws() throws {
        // usage_malformed has no valid five_hour/seven_day windows
        XCTAssertThrowsError(
            try UsageAdapter.normalize(dto("usage_malformed"),
                                       fetchedAt: .init(timeIntervalSince1970: 0)))
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter UsageAdapterTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
// Sources/ClaudeStatusBarCore/Usage/UsageSnapshot.swift
import Foundation

public struct UsageWindow: Codable, Equatable, Sendable {
    public let key: String
    public let label: String
    public let utilization: Double   // 0...100
    public let resetsAt: Date
    public init(key: String, label: String, utilization: Double, resetsAt: Date) {
        self.key = key; self.label = label
        self.utilization = utilization; self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let session: UsageWindow
    public let weekAll: UsageWindow
    public let weekPremium: [UsageWindow]
    public let fetchedAt: Date
    public init(session: UsageWindow, weekAll: UsageWindow,
                weekPremium: [UsageWindow], fetchedAt: Date) {
        self.session = session; self.weekAll = weekAll
        self.weekPremium = weekPremium; self.fetchedAt = fetchedAt
    }
}
```

```swift
// Sources/ClaudeStatusBarCore/Usage/UsageAdapter.swift
import Foundation

public enum UsageAdapterError: Error, Equatable { case missingCoreWindows }

public enum UsageAdapter {
    public static func label(forKey key: String) -> String {
        switch key {
        case "five_hour": return "Session"
        case "seven_day": return "Week (all)"
        default:
            if key.hasPrefix("seven_day_") {
                let model = String(key.dropFirst("seven_day_".count))
                return "Week (\(model.prefix(1).uppercased() + model.dropFirst()))"
            }
            return key
        }
    }

    public static func normalize(_ dto: UsageResponseDTO,
                                 fetchedAt: Date) throws -> UsageSnapshot {
        func window(_ key: String) -> UsageWindow? {
            guard let w = dto.windows[key] else { return nil }
            return UsageWindow(key: key, label: label(forKey: key),
                               utilization: w.utilization, resetsAt: w.resetsAt)
        }
        guard let session = window("five_hour"),
              let weekAll = window("seven_day") else {
            throw UsageAdapterError.missingCoreWindows
        }
        let premium = dto.windows.keys
            .filter { $0.hasPrefix("seven_day_") }
            .sorted()
            .compactMap { window($0) }
        return UsageSnapshot(session: session, weekAll: weekAll,
                             weekPremium: premium, fetchedAt: fetchedAt)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter UsageAdapterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatusBarCore/Usage/UsageSnapshot.swift Sources/ClaudeStatusBarCore/Usage/UsageAdapter.swift Tests/ClaudeStatusBarCoreTests/UsageAdapterTests.swift
git commit -m "feat(core): UsageSnapshot + adapter normalization"
```

---

## Task 10: UsageAPIClient

**Files:**
- Create: `Sources/ClaudeStatusBarCore/Usage/UsageAPIClient.swift`
- Test: `Tests/ClaudeStatusBarCoreTests/UsageAPIClientTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`, `UsageJSON`, `UsageResponseDTO`, `UsageAdapter`, `UsageSnapshot`
- Produces:
  - `enum UsageAPIError: Error, Equatable { case unauthorized; case rateLimited; case server(Int); case decoding }`
  - `struct UsageAPIClient { init(http: HTTPClient, userAgent: String); func fetch(accessToken: String, now: Date) async throws -> UsageSnapshot }`

- [ ] **Step 1: Failing test**

```swift
// Tests/ClaudeStatusBarCoreTests/UsageAPIClientTests.swift
import XCTest
@testable import ClaudeStatusBarCore

final class UsageAPIClientTests: XCTestCase {
    private func body(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json",
                                    subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func test_fetch_setsAuthAndBetaHeaders_andReturnsSnapshot() async throws {
        let http = MockHTTPClient()
        http.handler = { _ in HTTPResponse(status: 200, headers: [:],
            body: try! self.body("usage_full")) }
        let client = UsageAPIClient(http: http, userAgent: "claude-code/1.0.0")
        let snap = try await client.fetch(accessToken: "AT",
                                          now: .init(timeIntervalSince1970: 0))
        XCTAssertEqual(snap.session.utilization, 33.0)
        let req = http.lastRequest!
        XCTAssertEqual(req.url?.absoluteString,
                       "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer AT")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-beta"),
                       "oauth-2025-04-20")
        XCTAssertEqual(req.value(forHTTPHeaderField: "User-Agent"),
                       "claude-code/1.0.0")
    }

    func test_fetch_maps401ToUnauthorized() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 401, headers: [:], body: Data()) }
        let client = UsageAPIClient(http: http, userAgent: "ua")
        await XCTAssertThrowsErrorAsync(try await client.fetch(accessToken: "x", now: Date())) {
            XCTAssertEqual($0 as? UsageAPIError, .unauthorized)
        }
    }

    func test_fetch_maps429ToRateLimited() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 429, headers: [:], body: Data()) }
        let client = UsageAPIClient(http: http, userAgent: "ua")
        await XCTAssertThrowsErrorAsync(try await client.fetch(accessToken: "x", now: Date())) {
            XCTAssertEqual($0 as? UsageAPIError, .rateLimited)
        }
    }
}

// Small async throw helper (add once, in this file).
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void
) async {
    do { _ = try await expression(); XCTFail("expected error") }
    catch { handler(error) }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter UsageAPIClientTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
// Sources/ClaudeStatusBarCore/Usage/UsageAPIClient.swift
import Foundation

public enum UsageAPIError: Error, Equatable {
    case unauthorized, rateLimited, server(Int), decoding
}

public struct UsageAPIClient: Sendable {
    public static let endpoint =
        URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let http: HTTPClient
    private let userAgent: String

    public init(http: HTTPClient, userAgent: String = "claude-code/1.0.0") {
        self.http = http; self.userAgent = userAgent
    }

    public func fetch(accessToken: String, now: Date) async throws -> UsageSnapshot {
        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let resp = try await http.send(req)
        switch resp.status {
        case 200:
            do {
                let dto = try UsageJSON.decoder()
                    .decode(UsageResponseDTO.self, from: resp.body)
                return try UsageAdapter.normalize(dto, fetchedAt: now)
            } catch { throw UsageAPIError.decoding }
        case 401, 403: throw UsageAPIError.unauthorized
        case 429:      throw UsageAPIError.rateLimited
        default:       throw UsageAPIError.server(resp.status)
        }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter UsageAPIClientTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatusBarCore/Usage/UsageAPIClient.swift Tests/ClaudeStatusBarCoreTests/UsageAPIClientTests.swift
git commit -m "feat(core): UsageAPIClient with header + status mapping"
```

---

## Task 11: Token storage (protocol + Keychain + in-memory)

**Files:**
- Create: `Sources/ClaudeStatusBarCore/Storage/TokenStore.swift`
- Create: `Sources/ClaudeStatusBarCore/Storage/InMemoryTokenStore.swift`
- Create: `Sources/ClaudeStatusBarCore/Storage/KeychainTokenStore.swift`
- Test: `Tests/ClaudeStatusBarCoreTests/TokenStoreTests.swift`

**Interfaces:**
- Consumes: `TokenBundle`
- Produces:
  - `protocol TokenStore { func save(_ bundle: TokenBundle, for id: UUID) throws; func load(_ id: UUID) throws -> TokenBundle?; func delete(_ id: UUID) throws }`
  - `final class InMemoryTokenStore: TokenStore`
  - `struct KeychainTokenStore: TokenStore { init(service: String) }`

- [ ] **Step 1: Failing test (in-memory round-trip; Keychain covered by an integration test guarded by env)**

```swift
// Tests/ClaudeStatusBarCoreTests/TokenStoreTests.swift
import XCTest
@testable import ClaudeStatusBarCore

final class TokenStoreTests: XCTestCase {
    private func sample() -> TokenBundle {
        TokenBundle(accessToken: "AT", refreshToken: "RT",
                    expiresAt: .init(timeIntervalSince1970: 123), scopes: ["user:profile"])
    }

    func test_inMemory_saveLoadDelete() throws {
        let store = InMemoryTokenStore()
        let id = UUID()
        XCTAssertNil(try store.load(id))
        try store.save(sample(), for: id)
        XCTAssertEqual(try store.load(id), sample())
        try store.delete(id)
        XCTAssertNil(try store.load(id))
    }

    // Runs only when RUN_KEYCHAIN_TESTS=1 (writes to the login keychain).
    func test_keychain_roundtrip() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_KEYCHAIN_TESTS"] == "1")
        let store = KeychainTokenStore(service: "cz.mihalic.claude-status-bar.tests")
        let id = UUID()
        defer { try? store.delete(id) }
        try store.save(sample(), for: id)
        XCTAssertEqual(try store.load(id), sample())
        try store.delete(id)
        XCTAssertNil(try store.load(id))
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter TokenStoreTests`
Expected: FAIL (types not defined).

- [ ] **Step 3: Implement protocol + in-memory**

```swift
// Sources/ClaudeStatusBarCore/Storage/TokenStore.swift
import Foundation

public protocol TokenStore: Sendable {
    func save(_ bundle: TokenBundle, for id: UUID) throws
    func load(_ id: UUID) throws -> TokenBundle?
    func delete(_ id: UUID) throws
}
```

```swift
// Sources/ClaudeStatusBarCore/Storage/InMemoryTokenStore.swift
import Foundation

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var storage: [UUID: TokenBundle] = [:]
    private let lock = NSLock()
    public init() {}
    public func save(_ bundle: TokenBundle, for id: UUID) throws {
        lock.lock(); defer { lock.unlock() }; storage[id] = bundle
    }
    public func load(_ id: UUID) throws -> TokenBundle? {
        lock.lock(); defer { lock.unlock() }; return storage[id]
    }
    public func delete(_ id: UUID) throws {
        lock.lock(); defer { lock.unlock() }; storage[id] = nil
    }
}
```

- [ ] **Step 4: Implement Keychain store**

```swift
// Sources/ClaudeStatusBarCore/Storage/KeychainTokenStore.swift
import Foundation
import Security

public enum KeychainError: Error, Equatable { case status(OSStatus) }

public struct KeychainTokenStore: TokenStore {
    private let service: String
    public init(service: String) { self.service = service }

    private func baseQuery(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    public func save(_ bundle: TokenBundle, for id: UUID) throws {
        let data = try JSONEncoder().encode(bundle)
        try delete(id)
        var q = baseQuery(id)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public func load(_ id: UUID) throws -> TokenBundle? {
        var q = baseQuery(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else {
            throw KeychainError.status(status)
        }
        return try JSONDecoder().decode(TokenBundle.self, from: data)
    }

    public func delete(_ id: UUID) throws {
        let status = SecItemDelete(baseQuery(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `swift test --filter TokenStoreTests`
Expected: PASS (keychain test skipped unless `RUN_KEYCHAIN_TESTS=1`).
Optional real check: `RUN_KEYCHAIN_TESTS=1 swift test --filter TokenStoreTests/test_keychain_roundtrip` (will prompt for keychain access).

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeStatusBarCore/Storage/TokenStore.swift Sources/ClaudeStatusBarCore/Storage/InMemoryTokenStore.swift Sources/ClaudeStatusBarCore/Storage/KeychainTokenStore.swift Tests/ClaudeStatusBarCoreTests/TokenStoreTests.swift
git commit -m "feat(core): token store protocol + Keychain + in-memory impls"
```

---

## Task 12: Clock + Backoff

**Files:**
- Create: `Sources/ClaudeStatusBarCore/Sync/Clock.swift`
- Create: `Sources/ClaudeStatusBarCore/Sync/Backoff.swift`
- Create: `Tests/ClaudeStatusBarCoreTests/Mocks/ManualClock.swift`
- Test: `Tests/ClaudeStatusBarCoreTests/BackoffTests.swift`

**Interfaces:**
- Produces:
  - `protocol Clock: Sendable { func now() -> Date }`
  - `struct SystemClock: Clock`
  - test `final class ManualClock: Clock` with settable time
  - `struct Backoff { let steps: [TimeInterval]; static let usage: Backoff; func delay(forFailureCount n: Int) -> TimeInterval }`

> Do this task BEFORE Task 7 (OAuthClient needs `Clock`) if executing strictly in order. Listed here to keep sync-related code together; reorder freely — the dependency is only that `Clock` exists before Task 7 compiles.

- [ ] **Step 1: Implement Clock + ManualClock (infra)**

```swift
// Sources/ClaudeStatusBarCore/Sync/Clock.swift
import Foundation

public protocol Clock: Sendable { func now() -> Date }

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}
```

```swift
// Tests/ClaudeStatusBarCoreTests/Mocks/ManualClock.swift
import Foundation
@testable import ClaudeStatusBarCore

final class ManualClock: Clock, @unchecked Sendable {
    private var current: Date
    init(_ start: Date) { current = start }
    func now() -> Date { current }
    func advance(_ seconds: TimeInterval) { current.addTimeInterval(seconds) }
}
```

- [ ] **Step 2: Failing test for Backoff**

```swift
// Tests/ClaudeStatusBarCoreTests/BackoffTests.swift
import XCTest
@testable import ClaudeStatusBarCore

final class BackoffTests: XCTestCase {
    func test_delaySequence_capsAt300() {
        let b = Backoff.usage
        XCTAssertEqual(b.delay(forFailureCount: 0), 0)   // no failures
        XCTAssertEqual(b.delay(forFailureCount: 1), 30)
        XCTAssertEqual(b.delay(forFailureCount: 2), 60)
        XCTAssertEqual(b.delay(forFailureCount: 3), 120)
        XCTAssertEqual(b.delay(forFailureCount: 4), 240)
        XCTAssertEqual(b.delay(forFailureCount: 5), 300)
        XCTAssertEqual(b.delay(forFailureCount: 99), 300) // stays capped
    }
}
```

- [ ] **Step 3: Run to verify fail**

Run: `swift test --filter BackoffTests`
Expected: FAIL.

- [ ] **Step 4: Implement Backoff**

```swift
// Sources/ClaudeStatusBarCore/Sync/Backoff.swift
import Foundation

public struct Backoff: Sendable {
    public let steps: [TimeInterval]
    public init(steps: [TimeInterval]) { self.steps = steps }

    public static let usage = Backoff(steps: [30, 60, 120, 240, 300])

    /// n == number of consecutive failures. 0 -> no delay.
    public func delay(forFailureCount n: Int) -> TimeInterval {
        guard n > 0 else { return 0 }
        return steps[min(n, steps.count) - 1]
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `swift test --filter BackoffTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeStatusBarCore/Sync/Clock.swift Sources/ClaudeStatusBarCore/Sync/Backoff.swift Tests/ClaudeStatusBarCoreTests/Mocks/ManualClock.swift Tests/ClaudeStatusBarCoreTests/BackoffTests.swift
git commit -m "feat(core): Clock abstraction + 429 backoff schedule"
```

---

## Task 13: Account model + AppState

**Files:**
- Create: `Sources/ClaudeStatusBarCore/Model/Account.swift`
- Create: `Sources/ClaudeStatusBarCore/Model/AppState.swift`
- Test: `Tests/ClaudeStatusBarCoreTests/AppStateTests.swift`

**Interfaces:**
- Consumes: `UsageSnapshot`
- Produces:
  - `enum AccountStatus: Equatable, Codable { case ok; case rateLimited(retryAt: Date); case needsReauth; case offline; case never }`
  - `struct Account: Identifiable, Codable, Equatable { let id: UUID; var label: String; var accountUuid: String?; var syncInterval: Int; var status: AccountStatus; var lastSnapshot: UsageSnapshot?; var lastSyncedAt: Date? }` with `static let intervalFloor = 60`, `static let intervalDefault = 300`, and `var effectiveInterval: Int`
  - `@Observable final class AppState { var accounts: [Account]; func upsert(_:); func remove(_:); var maxUtilization: Double? }`

- [ ] **Step 1: Failing test**

```swift
// Tests/ClaudeStatusBarCoreTests/AppStateTests.swift
import XCTest
@testable import ClaudeStatusBarCore

final class AppStateTests: XCTestCase {
    private func win(_ u: Double) -> UsageWindow {
        UsageWindow(key: "k", label: "l", utilization: u, resetsAt: .init(timeIntervalSince1970: 0))
    }
    private func snap(_ s: Double, _ w: Double, _ p: Double) -> UsageSnapshot {
        UsageSnapshot(session: win(s), weekAll: win(w),
                      weekPremium: [win(p)], fetchedAt: .init(timeIntervalSince1970: 0))
    }

    func test_effectiveInterval_appliesFloor() {
        var a = Account(id: UUID(), label: "x", accountUuid: nil,
                        syncInterval: 5, status: .never,
                        lastSnapshot: nil, lastSyncedAt: nil)
        XCTAssertEqual(a.effectiveInterval, 60)
        a.syncInterval = 300
        XCTAssertEqual(a.effectiveInterval, 300)
    }

    func test_maxUtilization_acrossAccountsAndWindows() {
        let s = AppState()
        var a = Account(id: UUID(), label: "a", accountUuid: nil,
                        syncInterval: 300, status: .ok, lastSnapshot: snap(10, 20, 5),
                        lastSyncedAt: nil)
        var b = a; b = Account(id: UUID(), label: "b", accountUuid: nil,
                        syncInterval: 300, status: .ok, lastSnapshot: snap(30, 88, 40),
                        lastSyncedAt: nil)
        s.upsert(a); s.upsert(b)
        XCTAssertEqual(s.maxUtilization, 88)
    }

    func test_upsert_replacesById_and_remove() {
        let s = AppState()
        let id = UUID()
        let a = Account(id: id, label: "a", accountUuid: nil, syncInterval: 300,
                        status: .ok, lastSnapshot: nil, lastSyncedAt: nil)
        s.upsert(a)
        var a2 = a; a2.label = "a-renamed"
        s.upsert(a2)
        XCTAssertEqual(s.accounts.count, 1)
        XCTAssertEqual(s.accounts.first?.label, "a-renamed")
        s.remove(id)
        XCTAssertTrue(s.accounts.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter AppStateTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
// Sources/ClaudeStatusBarCore/Model/Account.swift
import Foundation

public enum AccountStatus: Equatable, Codable, Sendable {
    case ok
    case rateLimited(retryAt: Date)
    case needsReauth
    case offline
    case never
}

public struct Account: Identifiable, Codable, Equatable, Sendable {
    public static let intervalFloor = 60
    public static let intervalDefault = 300

    public let id: UUID
    public var label: String
    public var accountUuid: String?
    public var syncInterval: Int
    public var status: AccountStatus
    public var lastSnapshot: UsageSnapshot?
    public var lastSyncedAt: Date?

    public init(id: UUID, label: String, accountUuid: String?,
                syncInterval: Int, status: AccountStatus,
                lastSnapshot: UsageSnapshot?, lastSyncedAt: Date?) {
        self.id = id; self.label = label; self.accountUuid = accountUuid
        self.syncInterval = syncInterval; self.status = status
        self.lastSnapshot = lastSnapshot; self.lastSyncedAt = lastSyncedAt
    }

    public var effectiveInterval: Int { max(syncInterval, Self.intervalFloor) }
}
```

```swift
// Sources/ClaudeStatusBarCore/Model/AppState.swift
import Foundation
import Observation

@Observable public final class AppState {
    public var accounts: [Account] = []
    public init() {}

    public func upsert(_ account: Account) {
        if let idx = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[idx] = account
        } else {
            accounts.append(account)
        }
    }

    public func remove(_ id: UUID) {
        accounts.removeAll { $0.id == id }
    }

    /// Highest utilization across every window of every account (0...100).
    public var maxUtilization: Double? {
        let all = accounts.compactMap(\.lastSnapshot).flatMap { snap -> [Double] in
            [snap.session.utilization, snap.weekAll.utilization]
                + snap.weekPremium.map(\.utilization)
        }
        return all.max()
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter AppStateTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatusBarCore/Model/Account.swift Sources/ClaudeStatusBarCore/Model/AppState.swift Tests/ClaudeStatusBarCoreTests/AppStateTests.swift
git commit -m "feat(core): Account model + observable AppState"
```

---

## Task 14: AccountSyncEngine (syncOnce)

**Files:**
- Create: `Sources/ClaudeStatusBarCore/Sync/AccountSyncEngine.swift`
- Test: `Tests/ClaudeStatusBarCoreTests/AccountSyncEngineTests.swift`

**Interfaces:**
- Consumes: `TokenStore`, `OAuthClient`, `UsageAPIClient`, `Clock`, `TokenBundle`, `UsageSnapshot`, `UsageAPIError`
- Produces:
  - `enum SyncOutcome: Equatable { case success(UsageSnapshot); case needsReauth; case rateLimited; case offline; case failed(String) }`
  - `struct AccountSyncEngine { init(tokenStore: TokenStore, oauth: OAuthClient, usage: UsageAPIClient, clock: Clock, refreshWindow: TimeInterval); func syncOnce(accountID: UUID) async -> SyncOutcome }`
  - Behavior: load token → if `isExpiring(within: refreshWindow)` refresh + persist → `usage.fetch` → map errors. Missing token → `.needsReauth`. `.unauthorized` → try one refresh then re-fetch; still failing → `.needsReauth`.

- [ ] **Step 1: Failing test**

```swift
// Tests/ClaudeStatusBarCoreTests/AccountSyncEngineTests.swift
import XCTest
@testable import ClaudeStatusBarCore

final class AccountSyncEngineTests: XCTestCase {
    private func engine(_ http: MockHTTPClient, clock: ManualClock,
                        store: TokenStore) -> AccountSyncEngine {
        AccountSyncEngine(
            tokenStore: store,
            oauth: OAuthClient(http: http, endpoints: .production,
                               config: .claudeCode, clock: clock),
            usage: UsageAPIClient(http: http, userAgent: "ua"),
            clock: clock, refreshWindow: 300)
    }
    private func usageBody() -> Data {
        try! Data(contentsOf: Bundle.module.url(
            forResource: "usage_full", withExtension: "json", subdirectory: "Fixtures")!)
    }

    func test_missingToken_returnsNeedsReauth() async {
        let clock = ManualClock(.init(timeIntervalSince1970: 0))
        let http = MockHTTPClient()
        let e = engine(http, clock: clock, store: InMemoryTokenStore())
        let out = await e.syncOnce(accountID: UUID())
        XCTAssertEqual(out, .needsReauth)
    }

    func test_validToken_success() async throws {
        let clock = ManualClock(.init(timeIntervalSince1970: 0))
        let store = InMemoryTokenStore()
        let id = UUID()
        try store.save(TokenBundle(accessToken: "AT", refreshToken: "RT",
            expiresAt: .init(timeIntervalSince1970: 100_000), scopes: []), for: id)
        let http = MockHTTPClient { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer AT")
            return HTTPResponse(status: 200, headers: [:], body: self.usageBody())
        }
        let e = engine(http, clock: clock, store: store)
        let out = await e.syncOnce(accountID: id)
        guard case .success(let snap) = out else { return XCTFail("\(out)") }
        XCTAssertEqual(snap.session.utilization, 33.0)
    }

    func test_expiringToken_refreshesThenFetches() async throws {
        let clock = ManualClock(.init(timeIntervalSince1970: 0))
        let store = InMemoryTokenStore()
        let id = UUID()
        // expiresAt within refreshWindow (300s) -> must refresh first
        try store.save(TokenBundle(accessToken: "OLD", refreshToken: "RT",
            expiresAt: .init(timeIntervalSince1970: 100), scopes: []), for: id)
        let http = MockHTTPClient { req in
            if req.url!.path.hasSuffix("/oauth/token") {
                return HTTPResponse(status: 200, headers: [:], body: Data(
                    #"{"access_token":"NEW","refresh_token":"RT2","expires_in":28800,"scope":""}"#.utf8))
            }
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer NEW")
            return HTTPResponse(status: 200, headers: [:], body: self.usageBody())
        }
        let e = engine(http, clock: clock, store: store)
        let out = await e.syncOnce(accountID: id)
        guard case .success = out else { return XCTFail("\(out)") }
        XCTAssertEqual(try store.load(id)?.accessToken, "NEW") // persisted
    }

    func test_429_returnsRateLimited() async throws {
        let clock = ManualClock(.init(timeIntervalSince1970: 0))
        let store = InMemoryTokenStore()
        let id = UUID()
        try store.save(TokenBundle(accessToken: "AT", refreshToken: "RT",
            expiresAt: .init(timeIntervalSince1970: 100_000), scopes: []), for: id)
        let http = MockHTTPClient { _ in
            HTTPResponse(status: 429, headers: [:], body: Data()) }
        let e = engine(http, clock: clock, store: store)
        let out = await e.syncOnce(accountID: id)
        XCTAssertEqual(out, .rateLimited)
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter AccountSyncEngineTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
// Sources/ClaudeStatusBarCore/Sync/AccountSyncEngine.swift
import Foundation

public enum SyncOutcome: Equatable {
    case success(UsageSnapshot)
    case needsReauth
    case rateLimited
    case offline
    case failed(String)
}

public struct AccountSyncEngine {
    private let tokenStore: TokenStore
    private let oauth: OAuthClient
    private let usage: UsageAPIClient
    private let clock: Clock
    private let refreshWindow: TimeInterval

    public init(tokenStore: TokenStore, oauth: OAuthClient,
                usage: UsageAPIClient, clock: Clock,
                refreshWindow: TimeInterval = 300) {
        self.tokenStore = tokenStore; self.oauth = oauth
        self.usage = usage; self.clock = clock; self.refreshWindow = refreshWindow
    }

    public func syncOnce(accountID: UUID) async -> SyncOutcome {
        // `try?` flattens the Optional (load returns TokenBundle?), so this is a
        // single bind, not a double unwrap. nil covers both "missing" and "store threw".
        guard let bundle0 = try? tokenStore.load(accountID) else {
            return .needsReauth
        }
        // Proactive refresh if near expiry.
        var bundle = bundle0
        if bundle.isExpiring(within: refreshWindow, now: clock.now()) {
            switch await refresh(bundle, for: accountID) {
            case .some(let refreshed): bundle = refreshed
            case .none: return .needsReauth
            }
        }
        // Fetch usage; on unauthorized, try exactly one reactive refresh.
        do {
            let snap = try await usage.fetch(accessToken: bundle.accessToken,
                                             now: clock.now())
            return .success(snap)
        } catch let e as UsageAPIError {
            switch e {
            case .rateLimited: return .rateLimited
            case .server:      return .offline
            case .decoding:    return .failed("decoding")
            case .unauthorized:
                guard let refreshed = await refresh(bundle, for: accountID) else {
                    return .needsReauth
                }
                do {
                    let snap = try await usage.fetch(
                        accessToken: refreshed.accessToken, now: clock.now())
                    return .success(snap)
                } catch { return .needsReauth }
            }
        } catch {
            return .offline   // network/URLError
        }
    }

    private func refresh(_ bundle: TokenBundle, for id: UUID) async -> TokenBundle? {
        do {
            let refreshed = try await oauth.refresh(bundle)
            try? tokenStore.save(refreshed, for: id)
            return refreshed
        } catch { return nil }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter AccountSyncEngineTests`
Expected: PASS (all four).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatusBarCore/Sync/AccountSyncEngine.swift Tests/ClaudeStatusBarCoreTests/AccountSyncEngineTests.swift
git commit -m "feat(core): AccountSyncEngine syncOnce with refresh + error mapping"
```

---

## Task 15: SyncScheduler (next-fire interval calculation)

**Files:**
- Create: `Sources/ClaudeStatusBarCore/Sync/SyncScheduler.swift`
- Test: `Tests/ClaudeStatusBarCoreTests/SyncSchedulerTests.swift`

**Interfaces:**
- Consumes: `Account`, `AccountStatus`, `Backoff`
- Produces:
  - `enum SyncScheduler { static func staggerOffset(index: Int, spacing: TimeInterval) -> TimeInterval; static func nextInterval(base: Int, status: AccountStatus, consecutiveRateLimits: Int, now: Date) -> TimeInterval }`
  - Rules: normal → `base` seconds; `.rateLimited(retryAt)` → `max(retryAt - now, backoff.delay(count))`; stagger spreads N accounts by `spacing` each (`index * spacing`).

- [ ] **Step 1: Failing test**

```swift
// Tests/ClaudeStatusBarCoreTests/SyncSchedulerTests.swift
import XCTest
@testable import ClaudeStatusBarCore

final class SyncSchedulerTests: XCTestCase {
    func test_stagger_spreadsAccounts() {
        XCTAssertEqual(SyncScheduler.staggerOffset(index: 0, spacing: 7), 0)
        XCTAssertEqual(SyncScheduler.staggerOffset(index: 3, spacing: 7), 21)
    }

    func test_nextInterval_normal_usesBase() {
        let dt = SyncScheduler.nextInterval(
            base: 300, status: .ok, consecutiveRateLimits: 0,
            now: .init(timeIntervalSince1970: 0))
        XCTAssertEqual(dt, 300)
    }

    func test_nextInterval_rateLimited_honorsRetryAtOrBackoff() {
        let now = Date(timeIntervalSince1970: 1000)
        // retryAt is 500s out -> use it (bigger than backoff for 1 failure=30)
        let dt = SyncScheduler.nextInterval(
            base: 300,
            status: .rateLimited(retryAt: now.addingTimeInterval(500)),
            consecutiveRateLimits: 1, now: now)
        XCTAssertEqual(dt, 500)
    }

    func test_nextInterval_rateLimited_backoffWinsWhenRetryPassed() {
        let now = Date(timeIntervalSince1970: 1000)
        // retryAt already passed -> fall back to backoff for 3 failures = 120
        let dt = SyncScheduler.nextInterval(
            base: 300,
            status: .rateLimited(retryAt: now.addingTimeInterval(-10)),
            consecutiveRateLimits: 3, now: now)
        XCTAssertEqual(dt, 120)
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter SyncSchedulerTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
// Sources/ClaudeStatusBarCore/Sync/SyncScheduler.swift
import Foundation

public enum SyncScheduler {
    public static func staggerOffset(index: Int,
                                     spacing: TimeInterval) -> TimeInterval {
        TimeInterval(index) * spacing
    }

    public static func nextInterval(base: Int, status: AccountStatus,
                                    consecutiveRateLimits: Int,
                                    now: Date,
                                    backoff: Backoff = .usage) -> TimeInterval {
        switch status {
        case .rateLimited(let retryAt):
            let untilRetry = max(0, retryAt.timeIntervalSince(now))
            let backoffDelay = backoff.delay(forFailureCount: consecutiveRateLimits)
            return max(untilRetry, backoffDelay)
        default:
            return TimeInterval(base)
        }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter SyncSchedulerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatusBarCore/Sync/SyncScheduler.swift Tests/ClaudeStatusBarCoreTests/SyncSchedulerTests.swift
git commit -m "feat(core): SyncScheduler next-fire interval calculation"
```

---

## Task 16: SnapshotStore (persist account metadata, no secrets)

**Files:**
- Create: `Sources/ClaudeStatusBarCore/Storage/SnapshotStore.swift`
- Test: `Tests/ClaudeStatusBarCoreTests/SnapshotStoreTests.swift`

**Interfaces:**
- Consumes: `Account`
- Produces:
  - `struct SnapshotStore { init(fileURL: URL); func load() throws -> [Account]; func save(_ accounts: [Account]) throws; static func defaultURL() -> URL }`
  - Guarantee: persisted JSON contains no token fields (Account has none — tokens live only in Keychain).

- [ ] **Step 1: Failing test**

```swift
// Tests/ClaudeStatusBarCoreTests/SnapshotStoreTests.swift
import XCTest
@testable import ClaudeStatusBarCore

final class SnapshotStoreTests: XCTestCase {
    func test_saveLoad_roundtrip_and_noSecretsOnDisk() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("csb-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = SnapshotStore(fileURL: tmp)

        XCTAssertEqual(try store.load(), [])   // missing file -> empty

        let acct = Account(id: UUID(), label: "work@example.com", accountUuid: "u",
                           syncInterval: 300, status: .ok,
                           lastSnapshot: nil, lastSyncedAt: nil)
        try store.save([acct])
        XCTAssertEqual(try store.load(), [acct])

        let raw = try String(contentsOf: tmp, encoding: .utf8)
        XCTAssertFalse(raw.lowercased().contains("accesstoken"))
        XCTAssertFalse(raw.contains("sk-ant-"))
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter SnapshotStoreTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
// Sources/ClaudeStatusBarCore/Storage/SnapshotStore.swift
import Foundation

public struct SnapshotStore {
    private let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("cz.mihalic.claude-status-bar", isDirectory: true)
        try? FileManager.default.createDirectory(at: base,
            withIntermediateDirectories: true)
        return base.appendingPathComponent("accounts.json")
    }

    public func load() throws -> [Account] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try d.decode([Account].self, from: data)
    }

    public func save(_ accounts: [Account]) throws {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try e.encode(accounts)
        try data.write(to: fileURL, options: .atomic)
    }
}
```

> Note: `UsageSnapshot` and `UsageWindow` use default `Date` coding; because `SnapshotStore` sets `.iso8601` on both encoder and decoder, nested snapshot dates round-trip consistently. The `AccountStatus.rateLimited(retryAt:)` associated `Date` also uses this strategy.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter SnapshotStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatusBarCore/Storage/SnapshotStore.swift Tests/ClaudeStatusBarCoreTests/SnapshotStoreTests.swift
git commit -m "feat(core): SnapshotStore for account metadata (no secrets)"
```

---

## Task 17: Claude Code account import

**Files:**
- Create: `Sources/ClaudeStatusBarCore/Import/ClaudeCodeImporter.swift`
- Create fixtures: `Tests/ClaudeStatusBarCoreTests/Fixtures/cc_credentials.json`, `claude_config.json`
- Test: `Tests/ClaudeStatusBarCoreTests/ClaudeCodeImporterTests.swift`

**Interfaces:**
- Consumes: `TokenBundle`
- Produces:
  - `protocol SecretReader { func read() throws -> Data? }` (abstracts the `Claude Code-credentials` keychain item)
  - `protocol TextFileReader { func read(_ url: URL) throws -> Data? }` (abstracts `~/.claude.json`)
  - `struct ImportedAccount: Equatable { let bundle: TokenBundle; let email: String?; let accountUuid: String? }`
  - `struct ClaudeCodeImporter { init(secretReader: SecretReader, fileReader: TextFileReader, configURL: URL); func `import`() throws -> ImportedAccount }`
  - `enum ImportError: Error, Equatable { case noCredentials; case malformed }`
  - `struct KeychainSecretReader: SecretReader { init(service: String, account: String) }` (real, service `Claude Code-credentials`)

- [ ] **Step 1: Create fixtures**

`Tests/ClaudeStatusBarCoreTests/Fixtures/cc_credentials.json`:
```json
{
  "claudeAiOauth": {
    "accessToken": "sk-ant-oat01-FAKEACCESS",
    "refreshToken": "sk-ant-ort01-FAKEREFRESH",
    "expiresAt": 1893456000000,
    "scopes": ["user:inference", "user:profile"],
    "subscriptionType": "max",
    "rateLimitTier": null
  }
}
```

`Tests/ClaudeStatusBarCoreTests/Fixtures/claude_config.json`:
```json
{
  "oauthAccount": {
    "accountUuid": "11111111-2222-3333-4444-555555555555",
    "emailAddress": "work@example.com",
    "organizationUuid": "org-uuid"
  }
}
```

- [ ] **Step 2: Failing test**

```swift
// Tests/ClaudeStatusBarCoreTests/ClaudeCodeImporterTests.swift
import XCTest
@testable import ClaudeStatusBarCore

private struct FakeSecret: SecretReader {
    let data: Data?
    func read() throws -> Data? { data }
}
private struct FakeFile: TextFileReader {
    let data: Data?
    func read(_ url: URL) throws -> Data? { data }
}

final class ClaudeCodeImporterTests: XCTestCase {
    private func fixture(_ name: String) -> Data {
        try! Data(contentsOf: Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures")!)
    }

    func test_import_parsesBundleAndEmail() throws {
        let imp = ClaudeCodeImporter(
            secretReader: FakeSecret(data: fixture("cc_credentials")),
            fileReader: FakeFile(data: fixture("claude_config")),
            configURL: URL(fileURLWithPath: "/dev/null"))
        let acct = try imp.import()
        XCTAssertEqual(acct.bundle.accessToken, "sk-ant-oat01-FAKEACCESS")
        XCTAssertEqual(acct.bundle.refreshToken, "sk-ant-ort01-FAKEREFRESH")
        // expiresAt is ms epoch -> seconds
        XCTAssertEqual(acct.bundle.expiresAt,
                       Date(timeIntervalSince1970: 1_893_456_000))
        XCTAssertEqual(acct.email, "work@example.com")
        XCTAssertEqual(acct.accountUuid, "11111111-2222-3333-4444-555555555555")
    }

    func test_import_noCredentials_throws() {
        let imp = ClaudeCodeImporter(
            secretReader: FakeSecret(data: nil),
            fileReader: FakeFile(data: nil),
            configURL: URL(fileURLWithPath: "/dev/null"))
        XCTAssertThrowsError(try imp.import()) {
            XCTAssertEqual($0 as? ImportError, .noCredentials)
        }
    }

    func test_import_missingConfig_stillReturnsBundleWithoutEmail() throws {
        let imp = ClaudeCodeImporter(
            secretReader: FakeSecret(data: fixture("cc_credentials")),
            fileReader: FakeFile(data: nil),
            configURL: URL(fileURLWithPath: "/dev/null"))
        let acct = try imp.import()
        XCTAssertNil(acct.email)
        XCTAssertEqual(acct.bundle.accessToken, "sk-ant-oat01-FAKEACCESS")
    }
}
```

- [ ] **Step 3: Run to verify fail**

Run: `swift test --filter ClaudeCodeImporterTests`
Expected: FAIL.

- [ ] **Step 4: Implement**

```swift
// Sources/ClaudeStatusBarCore/Import/ClaudeCodeImporter.swift
import Foundation
import Security

public protocol SecretReader: Sendable { func read() throws -> Data? }
public protocol TextFileReader: Sendable { func read(_ url: URL) throws -> Data? }

public struct ImportedAccount: Equatable, Sendable {
    public let bundle: TokenBundle
    public let email: String?
    public let accountUuid: String?
}

public enum ImportError: Error, Equatable { case noCredentials, malformed }

public struct ClaudeCodeImporter {
    private let secretReader: SecretReader
    private let fileReader: TextFileReader
    private let configURL: URL

    public init(secretReader: SecretReader, fileReader: TextFileReader,
                configURL: URL) {
        self.secretReader = secretReader
        self.fileReader = fileReader
        self.configURL = configURL
    }

    private struct Credentials: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let refreshToken: String
            let expiresAt: Double      // ms epoch
            let scopes: [String]?
        }
        let claudeAiOauth: OAuth
    }
    private struct Config: Decodable {
        struct OAuthAccount: Decodable {
            let accountUuid: String?
            let emailAddress: String?
        }
        let oauthAccount: OAuthAccount?
    }

    public func `import`() throws -> ImportedAccount {
        guard let data = try secretReader.read() else { throw ImportError.noCredentials }
        let creds: Credentials
        do { creds = try JSONDecoder().decode(Credentials.self, from: data) }
        catch { throw ImportError.malformed }

        let o = creds.claudeAiOauth
        let bundle = TokenBundle(
            accessToken: o.accessToken,
            refreshToken: o.refreshToken,
            expiresAt: Date(timeIntervalSince1970: o.expiresAt / 1000.0),
            scopes: o.scopes ?? [])

        var email: String?; var uuid: String?
        if let cfg = try? fileReader.read(configURL),
           let parsed = try? JSONDecoder().decode(Config.self, from: cfg) {
            email = parsed.oauthAccount?.emailAddress
            uuid = parsed.oauthAccount?.accountUuid
        }
        return ImportedAccount(bundle: bundle, email: email, accountUuid: uuid)
    }
}

// Real keychain reader for the Claude Code credential item.
public struct KeychainSecretReader: SecretReader {
    private let service: String
    private let account: String
    public init(service: String = "Claude Code-credentials",
                account: String = NSUserName()) {
        self.service = service; self.account = account
    }
    public func read() throws -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        return out as? Data
    }
}

public struct DiskFileReader: TextFileReader {
    public init() {}
    public func read(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `swift test --filter ClaudeCodeImporterTests`
Expected: PASS (all three).

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeStatusBarCore/Import/ClaudeCodeImporter.swift Tests/ClaudeStatusBarCoreTests/Fixtures/cc_credentials.json Tests/ClaudeStatusBarCoreTests/Fixtures/claude_config.json Tests/ClaudeStatusBarCoreTests/ClaudeCodeImporterTests.swift
git commit -m "feat(core): Claude Code account importer (keychain + config)"
```

---

## Task 18: usage-cli executable (end-to-end proof)

**Files:**
- Create: `Sources/usage-cli/main.swift`

**Interfaces:**
- Consumes: `ClaudeCodeImporter`, `KeychainSecretReader`, `DiskFileReader`, `InMemoryTokenStore`, `OAuthClient`, `UsageAPIClient`, `AccountSyncEngine`, `SystemClock`, `URLSessionHTTPClient`, `UsageSnapshot`, `Redaction`
- Produces: a runnable command that imports the local Claude Code account and prints the three usage bars, or a clear error.

- [ ] **Step 1: Implement the CLI**

```swift
// Sources/usage-cli/main.swift
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
        do { imported = try importer.import() }
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
```

> Note: remove any `main.swift` top-level-code conflict — with `@main` the file must not also contain top-level statements. The free `func`s above are fine (declarations, not statements). If the compiler complains about `@main` in a file named `main.swift`, rename the file to `UsageCLI.swift`.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds `usage-cli`.

- [ ] **Step 3: Run against the real logged-in account (manual verification)**

Run: `swift run usage-cli`
Expected: EITHER three printed bars (Session / Week (all) / Week (premium)) with a reset time, OR a clear status line (`rate-limited`, `needs re-auth`, `offline`). This is the end-to-end proof that the OAuth token + `/api/oauth/usage` path works. If it prints bars, the whole Plan-1 data path is validated.

- [ ] **Step 4: Commit**

```bash
git add Sources/usage-cli/
git commit -m "feat(cli): usage-cli prints usage bars for the local Claude Code account"
```

---

## Task 19: Full test run + CI workflow for the package

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: CI that runs `swift build` + `swift test` on macOS for every push/PR (keychain tests stay skipped — `RUN_KEYCHAIN_TESTS` unset).

- [ ] **Step 1: Run the whole suite locally**

Run: `swift test`
Expected: ALL tests pass (keychain round-trip skipped).

- [ ] **Step 2: Write CI workflow**

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push: { branches: [main] }
  pull_request: {}
jobs:
  test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.app || true
      - name: Build
        run: swift build
      - name: Test
        run: swift test
```

- [ ] **Step 3: Commit + push**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: build + test the Swift package on macos-14"
git push origin main
```

- [ ] **Step 4: Verify CI green**

Run: `gh run watch` (or check the Actions tab)
Expected: the `CI` workflow passes.

---

## Self-Review (author checklist — completed at write time)

**Spec coverage vs. this plan:**
- OAuth PKCE + authorize URL → Tasks 2, 4. ✔
- Token exchange/refresh + host fallback + 8h expiry → Tasks 5, 6, 7. ✔
- `/api/oauth/usage` fetch + headers + status mapping → Task 10. ✔
- Dynamic per-model windows (opus/sonnet/fable) + labels → Tasks 8, 9. ✔
- Keychain token storage (1/account) + no-secrets metadata → Tasks 11, 16. ✔
- 429 backoff + interval floor/default + stagger → Tasks 12, 15. ✔
- Per-account sync (refresh-on-expiry, error→status) → Task 14. ✔
- Claude Code import (keychain + `~/.claude.json`) → Task 17. ✔
- Secret redaction / no plaintext logging → Tasks 1, 16 (no-secrets-on-disk test), 18. ✔
- End-to-end proof of reverse-engineered endpoints → Task 18 (`usage-cli`). ✔
- **Deferred to Plan 2/3 (intentional, not gaps):** MenuBarExtra widget, dashboard window, add-account OAuth UI (browser + paste/localhost capture), Sparkle self-update, unsigned packaging + INSTALL.md, live per-account timers wiring `SyncScheduler` to real `Timer`s in the app.

**Placeholder scan:** no TBD/TODO; every code step has complete code. Two callouts where a first code form is immediately corrected (Task 8 `DynamicKey`, Task 18 `@main`) are written with the exact corrected code.

**Type consistency:** `TokenBundle`, `UsageWindow`, `UsageSnapshot`, `SyncOutcome`, `AccountStatus`, `Clock`, `HTTPClient`, `HTTPResponse` names/signatures match across all consuming tasks. `Clock` must exist before Task 7 compiles — Task 12 note flags the ordering.

## Dependency ordering note

Strict compile order: **0 → 1 → 2 → 3 → 12 (Clock/Backoff) → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 13 → 14 → 15 → 16 → 17 → 18 → 19.** Task 12 is pulled earlier than its number because `OAuthClient` (Task 7) depends on `Clock`. If using subagent-driven execution, dispatch in this order.
