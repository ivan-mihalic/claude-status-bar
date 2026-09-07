# Security & Transparency

Claude Status Bar handles OAuth tokens for your Claude account, so this document explains
exactly what the app is allowed to do, what it talks to over the network, and where your data
lives — grounded in the actual entitlements and source, not a policy promise.

## Signing & notarization

Release builds (the `.dmg`/`.zip` on the [Releases](https://github.com/ivan-mihalic/claude-status-bar/releases)
page) are:

- Signed with a **Developer ID Application** certificate (Apple-issued, tied to a real
  identity — see it yourself with the command below).
- Built with the **Hardened Runtime** enabled (`-o runtime`), which restricts code injection,
  DYLD environment-variable abuse, and unsigned-memory execution even beyond what the sandbox
  already blocks.
- **Notarized by Apple** and **stapled** — both the `.app` and the `.dmg` carry Apple's
  notarization ticket, so Gatekeeper can verify them offline, with no network round-trip to
  Apple at launch time.

**Verify it yourself** after installing:

```bash
codesign -dvvv /Applications/ClaudeStatusBar.app
```

Look for `Authority=Developer ID Application: …` and `flags=0x10000(runtime)` (Hardened
Runtime on).

```bash
spctl -a -vv /Applications/ClaudeStatusBar.app
```

Should print `accepted` and `source=Notarized Developer ID`.

## App Sandbox — full isolation, four entitlements only

The app runs under the **full App Sandbox** (`com.apple.security.app-sandbox = true`), the same
isolation model the Mac App Store requires. `App/ClaudeStatusBar.entitlements` declares exactly
four entitlements — nothing else is requested:

1. **`com.apple.security.app-sandbox`** — turns on the sandbox itself. Without any file-access
   entitlements alongside it (see below), the process cannot read or write outside its own
   sandbox container, cannot browse or open arbitrary files on your Mac, and cannot read another
   app's data. Keychain access is also isolated: the app declares **no**
   `keychain-access-groups` entitlement, so it falls back to the App Sandbox's **default**
   per-app keychain access group (derived from its app ID), confining it to its own Keychain
   items and preventing it from reading another app's items (including Claude Code's own
   token).
2. **`com.apple.security.network.client`** — allows outgoing network *client* connections.
   This is what lets the app reach the Anthropic usage API, the Codex usage API, the OAuth
   token hosts, and Sparkle's appcast/update download — see
   [Network endpoints](#network-endpoints-contacted) below.
3. **`com.apple.security.network.server`** — added in 0.6.0 for **one** purpose: signing in to
   a **Codex** account through the browser. That OAuth client's redirect URI is fixed at
   `http://localhost:1455/auth/callback` and cannot be changed by this app, so the browser can
   only hand the authorization code back through a local address. The listener
   (`LoopbackCallbackServer`) is bound to the **loopback interface** (`requiredInterfaceType =
   .loopback`), is started only when a Codex sign-in begins, answers a single request, and is
   torn down as soon as the code arrives, the attempt is cancelled, or it times out (5 minutes).
   It is never running at rest, and it is not used by the Anthropic sign-in, which shows the
   code on a web page instead. If you only use Claude accounts, nothing in the app ever opens
   a socket to listen on.
4. **`com.apple.security.temporary-exception.mach-lookup.global-name`**, scoped to exactly two
   names — `cz.mihalic.claude-status-bar-spks` and `cz.mihalic.claude-status-bar-spki`. This is
   Sparkle's own, documented sandbox requirement: it lets the app talk to its bundled Sparkle
   **Installer XPC service** (which performs the actual privileged-free update install) over Mach
   IPC. It is scoped to Sparkle's own service names only — it does not grant lookup of arbitrary
   system or third-party Mach services.

There is **no** file-access entitlement of any kind (no user-selected file/folder access, no
Downloads-folder access, no removable-media access). The app cannot open a file picker to read
your files, cannot see other apps' containers, and cannot read Claude Code's local session data.

## Network endpoints contacted

The app only contacts the selected provider's authentication and usage hosts, plus its own
Sparkle update host, over HTTPS:

- **`claude.ai`** (`https://claude.ai/oauth/authorize`) — where your **default browser** (not an
  embedded webview) opens for the OAuth sign-in itself, when you click **Sign in with Claude…**.
- **The OAuth token host** — the app exchanges the authorization code for tokens against
  `https://platform.claude.com/v1/oauth/token`, falling back to
  `https://console.anthropic.com/v1/oauth/token` if the first host is unreachable (see
  `Sources/ClaudeStatusBarCore/OAuth/OAuthEndpoints.swift`).
- **`api.anthropic.com/api/oauth/usage`** — polled periodically with a **read-only `GET`**
  request, authenticated with your account's OAuth bearer token, to fetch your current
  session/week/premium-week usage numbers (see
  `Sources/ClaudeStatusBarCore/Usage/UsageAPIClient.swift`). No data is ever sent to this or any
  other endpoint besides the standard OAuth bearer header — no telemetry, no analytics, no
  crash reporting.

  In honest detail, the request also sends a `User-Agent: claude-code/1.0.0` header (spoofed —
  this app is not Claude Code) and an `anthropic-beta: oauth-2025-04-20` header, both required
  by this specific (undocumented) endpoint to accept OAuth-authenticated usage requests at all.
  Neither header carries any user data or telemetry — they're endpoint-compatibility values,
  not tracking.

  **How often it is polled** is not a fixed rate. The per-account sync interval you set (5
  minutes by default) is a **floor**: an account at 80 % or more of a limit is polled that
  often, one between 20 % and 80 % three times less, one below 20 % six times less, capped at
  one hour. On battery those gaps double, in Low Power Mode they triple, and **while the screen
  is asleep the app stops polling entirely** — it fetches once on wake instead. In practice this
  means fewer requests against your account than a fixed 5-minute timer would make (see
  `Sources/ClaudeStatusBarCore/Sync/SyncScheduler.swift` and `.../Sync/EnergyPolicy.swift`).

Sparkle (the self-update framework) additionally fetches its appcast and update archive from the
project's own GitHub Pages host at first-launch/periodic update-check time; that traffic is
covered by the same `network.client` entitlement.

**Codex accounts** (optional, only if you add one) additionally contact:

- `https://auth.openai.com/oauth/authorize` and `/oauth/token` — the sign-in and token
  exchange/refresh, using the Codex CLI's OAuth client and PKCE, exactly as the CLI does.
- `https://auth.openai.com/api/accounts/deviceauth/usercode`, `/deviceauth/token`, and
  `https://auth.openai.com/codex/device` — the optional device-code sign-in flow.
- `https://chatgpt.com/backend-api/wham/usage` — the usage endpoint Codex CLI reads its own
  `/status` limits from. The app sends the bearer token and the `ChatGPT-Account-Id` routing
  value contained in that signed token; the response carries the account's rate-limit windows.

No Codex traffic happens unless you choose Codex while adding or reconnecting an account.

## Where your data lives

- **OAuth tokens live only in the macOS Keychain** — saved via `KeychainTokenStore`
  (`Sources/ClaudeStatusBarCore/Storage/KeychainTokenStore.swift`) as a generic-password item
  per account, accessible only after you've unlocked your Mac. Tokens are never written to disk
  in plaintext, never logged, and never displayed anywhere in the UI.
- **Account metadata** — a label (typically the account email), account status, the
  last-fetched usage snapshot, and UI preferences — **never any token** — is persisted as
  `accounts.json` inside the app's own sandbox container
  (`~/Library/Containers/cz.mihalic.claude-status-bar/Data/Library/Application Support/cz.mihalic.claude-status-bar/accounts.json`),
  written by `Sources/ClaudeStatusBarCore/Storage/SnapshotStore.swift`. This file contains no
  secrets, and it's not reachable by other sandboxed apps.

## Upgrading from a pre-sandbox install

If you installed a version of this app **before** it moved to the App Sandbox, this update
changes the Keychain access group your tokens were saved under — the new sandboxed build can't
see the old Keychain items. **Re-add your accounts once** after updating; the app will re-run the
OAuth login and everything works normally from then on. This is a one-time step, not a recurring
issue.

**Specifically for the 0.2.0 update:** download the fresh `.dmg` from
[Releases](https://github.com/ivan-mihalic/claude-status-bar/releases) rather than relying on
Sparkle's auto-update, because this release changes **both** the code-signing identity (ad-hoc →
Developer ID Application) **and** the sandbox status at once — re-adding accounts once
afterward is still required either way. Future 0.2.x → 0.2.y updates go back to normal Sparkle
auto-updates.

## Update integrity (Sparkle / EdDSA)

Automatic updates are delivered via [Sparkle](https://sparkle-project.org). Every update archive
is signed with the project's own **EdDSA** key — a signature layer completely separate from
Apple's code-signing/notarization. Sparkle verifies this EdDSA signature against the public key
embedded in the app (`SUPublicEDKey` in `project.yml`) before installing anything; an update
that doesn't match is rejected. This protects you even in a scenario where the download host
(GitHub Pages) were compromised independently of the code-signing chain.

## Source availability

The full source is available in this repository under the
[PolyForm Noncommercial License 1.0.0](LICENSE.md) — you're free to read every line that runs on
your Mac, or build it yourself (see [`README.md`](README.md#build-from-source)).

## Reporting a concern

If you find a security issue, please open a GitHub issue on this repository (or, for anything
sensitive, contact the maintainer directly rather than filing it publicly).
