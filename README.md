# Claude Status Bar

A native macOS **menu-bar app that tracks Claude subscription usage (Pro/Max) across
multiple accounts at once** — the same numbers the Claude Code CLI `/usage` command shows,
but for every account you connect, always visible in your menu bar.

- **Multi-account.** Connect as many Claude accounts as you like; each is authenticated by
  the app's own browser OAuth login (it never reuses or touches Claude Code's own token).
- **Three usage windows per account:** current 5-hour **session**, current **week (all
  models)**, and current **week (premium model)** — each with a progress bar, percentage,
  and reset countdown.
- **Menu-bar widget** with a color-coded gauge (green / amber / red by how close you are to
  a limit). Optionally show every account's percentages right in the menu bar, with a short
  per-account label.
- **Dashboard** window with large bars, reset day/date/time, and per-account controls.
- **Per-account sync interval** (default 5 min, minimum 1 min) with automatic 429 back-off.
- **Self-updating** via [Sparkle](https://sparkle-project.org) — no Mac App Store.

> **Status:** functional; **signed with a Developer ID Application certificate, Hardened
> Runtime, notarized and stapled** by Apple — see [`SECURITY.md`](SECURITY.md) for how to
> verify that yourself. Data comes from an **undocumented, reverse-engineered** Anthropic
> endpoint (`/api/oauth/usage`) — it works today but Anthropic could change it at any time.
> You monitor **your own** accounts at your own risk.

---

## Requirements

- **macOS 14 (Sonoma) or later.**
- To build from source: **Xcode 16+** and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  (`brew install xcodegen`).

## Install (recommended: download a release)

1. Download the latest **`ClaudeStatusBar-<version>.dmg`** from the
   [**Releases**](https://github.com/ivan-mihalic/claude-status-bar/releases) page.
2. Open the `.dmg` and drag **`ClaudeStatusBar.app`** onto the **Applications** shortcut.
   (A `.zip` is also attached to each release if you prefer.)
3. **First launch.** The app is signed with a **Developer ID Application** certificate and
   **notarized by Apple**, so opening it shows only the standard confirmation dialog macOS
   shows for any notarized, verified-developer app (an **Open**/Cancel choice, not an
   "unidentified developer" block) — click **Open**. No quarantine workaround or Privacy &
   Security detour needed. See [`SECURITY.md`](SECURITY.md) for how to verify the
   signature/notarization yourself (`codesign -dvvv`, `spctl -a -vv`).
4. It runs as a **menu-bar app** (no Dock icon by default) — look for the **gauge icon** in
   the top-right of your menu bar. You can turn on a Dock icon in **Settings → Show icon in Dock**.

See [`INSTALL.md`](INSTALL.md) for the short version, or [`SECURITY.md`](SECURITY.md) for the
full signing/sandbox/network/data-storage rundown.

## Build from source

```bash
git clone https://github.com/ivan-mihalic/claude-status-bar.git
cd claude-status-bar
brew install xcodegen
xcodegen generate
xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar \
  -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Release/ClaudeStatusBar.app
```

(There's also `scripts/package.sh <version>` which builds + zips a distributable `.app`.)

## Usage

### Add an account
1. Click the **gauge icon** → **Add Account…**.
2. Click **Sign in with Claude…** → a browser opens → sign in.
3. Copy the authorization **code** shown on the callback page, paste it into the app, and
   click **Connect**. Approve any Keychain prompt.
4. Within one sync cycle the account appears with its usage bars, and the menu-bar gauge
   reflects your most-constrained limit across all accounts.

### Dashboard & settings
- **Open Dashboard** — large bars, reset day/date/time, and per-account **Name**,
  **Menu label** (prefix), **sync interval**, remove, and re-auth controls.
- **Settings…** — default sync interval, **Launch at login**, **Show icon in Dock** (off by
  default; the app lives in the menu bar), and **Show each account's percentages in the menu
  bar** (uses the per-account "Menu label" prefixes to tell accounts apart, e.g.
  `W 20/19/5  P 30/40`).

### Updates
The app checks for updates via **Sparkle** and has a **Check for Updates…** button in the
menu-bar popover. Update archives are **EdDSA-signed** (separate from Apple's notarization —
see [`SECURITY.md`](SECURITY.md#update-integrity-sparkle--eddsa)); Sparkle verifies that
signature before installing anything.

> If you're upgrading from a version of the app that predated App Sandboxing, you'll need to
> **re-add your accounts once** — see [`SECURITY.md`](SECURITY.md#upgrading-from-a-pre-sandbox-install).

## Privacy & security

- The app runs under the **full App Sandbox**, with only three entitlements declared
  (network client + Sparkle's own scoped XPC access) and **no file-access entitlement of any
  kind** — it cannot read arbitrary files on your Mac or other apps' data.
- **Your tokens live only in the macOS Keychain** — never written to disk in plaintext,
  never logged, never shown in the UI.
- Each account uses the **app's own independent OAuth grant**; it never touches Claude Code's
  local session or token (so it can't log you out of the `claude` CLI).
- The app talks only to `claude.ai` (login), the OAuth token host,
  `api.anthropic.com/api/oauth/usage` (read-only usage polling), and its own Sparkle update
  host (`ivan-mihalic.github.io`, GitHub Pages appcast/download).

See [`SECURITY.md`](SECURITY.md) for the full breakdown — signing/notarization verification
commands, the exact entitlements and why each exists, every network endpoint contacted, and
where data is stored.

## Development

```bash
# Core + app logic tests (swift-testing) — run with the project's Swift 6 toolchain:
swift test

# Build the .app (needs Xcode):
xcodegen generate && xcodebuild -project ClaudeStatusBar.xcodeproj \
  -scheme ClaudeStatusBar -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

The codebase is split into a headless, unit-tested Swift package
(`Sources/ClaudeStatusBarCore` + `Sources/ClaudeStatusBarApp`) and a thin SwiftUI app target
(`App/`, generated into an Xcode project by `project.yml`). Design docs and implementation
plans live under `docs/`.

## License

[PolyForm Noncommercial License 1.0.0](LICENSE.md) — **source-available, not open source.**
You may view the source and use it for **noncommercial** purposes (personal use, study,
hobby, research); **commercial use is not permitted**. Provided "as is", without any warranty.
© 2026 Ivan Mihalič.
