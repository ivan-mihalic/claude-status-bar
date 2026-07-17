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

> **Status:** functional; unsigned (no Apple Developer account). Data comes from an
> **undocumented, reverse-engineered** Anthropic endpoint (`/api/oauth/usage`) — it works
> today but Anthropic could change it at any time. You monitor **your own** accounts at your
> own risk.

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
3. **First launch — get past Gatekeeper (one time).** The app is ad-hoc signed but **not
   notarized** by Apple (no paid Developer account), so macOS shows a scary *"unidentified
   developer / may be malware"* dialog on first open. It is **not** actually malware — this is
   simply how macOS treats every un-notarized download. Do one of:
   - **Terminal (cleanest):** `xattr -dr com.apple.quarantine /Applications/ClaudeStatusBar.app`, then open normally, **or**
   - **System Settings → Privacy & Security** → scroll to the blocked-app notice → **Open
     Anyway** (macOS 15 Sequoia removed the old right-click → Open shortcut for un-notarized apps).

   You only do this **once**. Sparkle-delivered updates afterwards install without re-prompting.
4. It runs as a **menu-bar app** (no Dock icon by default) — look for the **gauge icon** in
   the top-right of your menu bar. You can turn on a Dock icon in **Settings → Show icon in Dock**.

> **Prefer zero Gatekeeper prompts?** Build it yourself ([below](#build-from-source)) — a
> locally built app carries no quarantine flag and launches with no warning at all.

See [`INSTALL.md`](INSTALL.md) for the short version.

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
2. Optionally click **Use my Claude Code account** to pre-fill the email from your local
   Claude Code login (it only reads the email — the app logs in with its own OAuth grant).
3. Click **Sign in with Claude…** → a browser opens → sign in.
4. Copy the authorization **code** shown on the callback page, paste it into the app, and
   click **Connect**. Approve any Keychain prompt.
5. Within one sync cycle the account appears with its usage bars, and the menu-bar gauge
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
menu-bar popover. Updates are **EdDSA-signed**; after the one-time first-launch step,
Sparkle-delivered updates install without the Gatekeeper prompt.

> Unsigned builds may re-prompt for Keychain access after an update (the binary signature
> changes) — click **Always Allow**.

## Privacy & security

- **Your tokens live only in the macOS Keychain** — never written to disk in plaintext,
  never logged, never shown in the UI.
- Each account uses the **app's own independent OAuth grant**. Importing from Claude Code
  only detects the account's email; it never reuses or refreshes Claude Code's token (so it
  can't log you out of the `claude` CLI).
- The app talks only to `claude.ai` (login), the OAuth token host, and
  `api.anthropic.com/api/oauth/usage` (read-only usage polling).

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
