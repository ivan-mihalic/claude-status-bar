# App Store-grade signing, sandboxing & notarization — Design

**Goal:** Ship `ClaudeStatusBar` at **App Store quality** — App-Sandboxed, Hardened Runtime,
signed with a Developer ID Application certificate, and **notarized + stapled** — while still
distributing directly from GitHub (DMG + Sparkle self-update). Remove the Claude Code "direct
import" feature, which is fundamentally incompatible with the sandbox.

**Distribution note:** This is *not* an actual App Store submission (Sparkle self-update +
direct distribution preclude that). It applies every App-Store-grade security/transparency
practice — full App Sandbox, minimal declared entitlements, hardened runtime, notarization,
privacy manifest, no private APIs — to a directly-distributed app.

---

## Key decisions (agreed)

1. **Full App Sandbox** (chosen over Developer-ID-only) — the highest security/transparency bar.
2. **Remove the Claude Code import** — it read `~/.claude.json` and Claude Code's Keychain item to
   pre-fill an email; the sandbox forbids reading other apps' files/Keychain. It only ever
   pre-filled a label (never reused a token), so the replacement is: the user types the email.
3. **Individual Developer ID** — the signer's legal name is embedded in the signature
   (`codesign -dvvv`) and is publicly visible. Accepted.
4. **Sparkle stays**, configured for sandbox via its **Installer XPC service**; the **Downloader
   XPC is removed** (the app has `network.client`, so Sparkle's own downloader is unnecessary and
   it drags in a deprecated WebView — dropping it is smaller and cleaner).
5. **CI signing** via an **App Store Connect API key** for `notarytool` (no Apple ID password / 2FA).

## Consequence for existing installs (must communicate)

Sandboxing changes the app's **Keychain access group** and moves its data into the **app
container** (`~/Library/Containers/cz.mihalic.claude-status-bar/…`). Tokens and `accounts.json`
saved by the current non-sandbox build live outside the container and become unreadable, so
**existing users must re-add (re-authenticate) their accounts once** after updating. The user
base is tiny (essentially the author's 2 accounts), so this is acceptable and will be noted in
the release notes + welcome window.

---

## Architecture changes

### 1. Remove the Claude Code import
- Delete the **"Use my Claude Code account"** button and its handler in `AddAccountView`.
- Drop the importer from `AppEnvironment` and `AccountManager` (remove the `importer` init
  parameter and `detectClaudeCodeEmail()`).
- Relocate `ClaudeCodeImporter` / `KeychainSecretReader` / `DiskFileReader` **out of
  `ClaudeStatusBarCore`** so the shipped app bundle links **no** cross-app file/Keychain code
  (auditability: "nothing hidden"). They move into the `usage-cli` target, which stays a local,
  non-distributed dev tool. If keeping them in the CLI is not worth it, delete them and give the
  CLI a `--token`/env token source instead (decided in the plan).
- Move/trim the affected tests (`ClaudeCodeImporterTests`, `AccountManagerTests`).

### 2. App Sandbox + Hardened Runtime entitlements
`App/ClaudeStatusBar.entitlements` — minimal and each line commented:
- `com.apple.security.app-sandbox` = `true`
- `com.apple.security.network.client` = `true` — Anthropic usage API, OAuth token host, Sparkle
  appcast + update download.
- `com.apple.security.temporary-exception.mach-lookup.global-name` =
  `[$(PRODUCT_BUNDLE_IDENTIFIER)-spks, $(PRODUCT_BUNDLE_IDENTIFIER)-spki]` — Sparkle's XPC comms;
  this is Sparkle's official, documented sandbox requirement, scoped to Sparkle's own Mach service
  names.

Nothing else: no file access, no `user-selected` files, no `network.server`, no JIT, no
`disable-library-validation`. **Hardened Runtime** (`-o runtime`) enabled — required for
notarization. Both flags will be documented in `SECURITY.md`.

### 3. Sparkle sandbox configuration
- `Info.plist`: `SUEnableInstallerLauncherService = YES` (already present) — enables the Installer
  XPC that performs the privileged install outside the sandbox.
- **Keep** `Installer.xpc`; **remove** `Downloader.xpc`, then re-sign the framework.
- Sign each Sparkle component **individually** with `-o runtime` and **never** `--deep`
  (Sparkle explicitly warns against `--deep`): `Installer.xpc`, `Autoupdate`, `Updater.app`,
  `Sparkle.framework`.

### 4. Signing + notarization pipeline (CI)
`scripts/package.sh` (rewrite of the ad-hoc signing):
- Sign **inside-out**, Developer ID, `-o runtime --timestamp`: Sparkle components first, then the
  app bundle with `--entitlements App/ClaudeStatusBar.entitlements`. No `--deep`.
- Build the DMG from the signed app.
- `xcrun notarytool submit <dmg> --wait` authenticated with the App Store Connect API key.
- `xcrun stapler staple <dmg>` and `xcrun stapler staple <app>` (same cdhash, notarized via the DMG
  submission), then `ditto` the stapled app into the Sparkle zip.
- Verify: `codesign --verify --strict`, `spctl -a -t exec -vv` (app) / `spctl -a -t open`
  (dmg), and assert the `runtime` + `sandbox` code-sign flags.

`.github/workflows/release.yml`:
- Import the Developer ID cert (`.p12`, base64) into a temporary keychain, run `package.sh` with
  the signing identity + notarization env, delete the keychain afterwards.
- Keep the existing EdDSA/Sparkle appcast signing and Pages hosting.

**New GitHub secrets** (values never printed or committed):
`DEVELOPER_ID_CERT_P12_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`, `APPLE_TEAM_ID`,
`AC_API_KEY_P8_BASE64`, `AC_API_KEY_ID`, `AC_API_ISSUER_ID` (plus existing
`SPARKLE_ED_PRIVATE_KEY`).

### 5. Transparency artifacts
- **`PrivacyInfo.xcprivacy`** — declares no tracking, no collected data types, and the
  `UserDefaults` required-reason API (`CA92.1`, the app's own settings). Not required off the App
  Store, added for transparency.
- **`SECURITY.md`** — signing identity, the exact entitlements and why each exists, the endpoints
  the app contacts, where data lives (Keychain + app container), the Sparkle EdDSA note, and the
  commands a user runs to verify (`codesign -dvvv`, `spctl -a -vv`).
- **First-run welcome window** — shown once (an `@AppStorage` flag): what the app does, that it
  lives in the menu bar (not the Dock), that Add Account triggers a Keychain prompt, which hosts it
  contacts, and a privacy link. This is the in-app "valid informing" of the user.

### 6. AI signing guide (second deliverable)
**`docs/apple-signing-guide.md`** — a precise, do-this-then-that guide the user follows *while the
account payment processes*: enroll/pay → create a **Developer ID Application** certificate (CSR →
cert → export `.p12` with a password) → create an **App Store Connect API key** (`.p8`, Key ID,
Issuer ID) → find the **Team ID** → base64-encode and `gh secret set` each value (exact commands,
never echoing secrets) → push a tag → verify the notarized result.

---

## First-launch UX (after notarization)
DMG → drag onto Applications → first open → macOS shows the **standard, benign** prompt
("downloaded from the Internet, are you sure you want to open it?") naming the **verified
developer** → Open. The welcome window appears on first run. No "malware/unidentified developer"
scare, ever.

## Testing / verification
- `swift test` — logic is unaffected; import tests are relocated or removed.
- Local: build the sandboxed app, confirm Add Account OAuth (browser open + paste), Keychain
  storage, Launch-at-login, and Sparkle "Check for Updates" all work **under the sandbox**;
  `codesign --verify --strict`; `spctl` assessment.
- CI: a full tag → release round-trip; download the DMG on a clean machine, verify
  `spctl -a -vv` passes with the developer name and Gatekeeper opens it without a prompt.

## Out of scope
- Actual App Store submission.
- Automatic migration of existing accounts (users re-add once).

## Global constraints (carry-forward)
- macOS 14+; **never** `codesign --deep`; retain EdDSA Sparkle update signing; secrets never
  printed or committed; follow Apple + Sparkle documentation exactly.

## Sources
- Apple — [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
  [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
  [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- Sparkle — [Sandboxing / code signing](https://sparkle-project.org/documentation/sandboxing)
