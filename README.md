# Claude Status Bar

A native macOS **menu-bar app that tracks Claude subscription usage (Pro/Max) across
multiple accounts at once** — the same numbers the Claude Code CLI `/usage` command shows,
but for every account you connect, always visible in your menu bar.

- **Multi-account.** Connect as many Claude accounts as you like; each is authenticated by
  the app's **own independent** browser OAuth login.
- **Three usage windows per account:** current 5-hour **session**, current **week (all
  models)**, and current **week (premium model)** — each with a progress bar, percentage,
  and reset countdown.
- **Menu-bar widget** with a color-coded gauge (green / amber / red by how close you are to
  a limit). Optionally show every account's percentages right in the menu bar, with a short
  per-account label.
- **One app window** with a sidebar — **Dashboard · Add Account · Settings · About** — so every
  action is reachable from any screen, not just the menu-bar popover. The Dashboard shows large
  bars, reset day/date/time, per-account controls, and a *"synced N min ago"* button to refresh
  on demand.
- **Per-account sync interval** (default 5 min, minimum 1 min). Running into a usage limit
  never asks you to sign in again: the app waits for the server's `Retry-After`, or for the
  reset time of whichever window is actually maxed out, and picks itself back up once the
  limit lifts (re-checking at least hourly). Clicking *"synced N min ago"* always wins over
  whatever the background poll is doing, so a manual sync can't be undone by a slow request
  that started before it.
- **Stays signed in.** Refreshing an account's credentials is serialised, so two syncs
  running at once can't spend the same rotated token and lock each other out, and only a
  server response that actually says the grant is gone asks you to sign in again.
- **Self-updating** via [Sparkle](https://sparkle-project.org) — no Mac App Store.

> **Status:** functional; **signed with a Developer ID Application certificate, Hardened
> Runtime, notarized and stapled** by Apple — see [`SECURITY.md`](SECURITY.md) for how to
> verify that yourself. Data comes from an **undocumented, reverse-engineered** Anthropic
> endpoint (`/api/oauth/usage`) — it works today but Anthropic could change it at any time.
> You monitor **your own** accounts at your own risk.

---

## Requirements

**macOS 14 (Sonoma) or later** — that's all you need to run it; just download a release below.
(Building it yourself needs **Xcode 26+**: releases are linked against the macOS 26 SDK so the
app picks up the current window chrome on macOS 26, while still deploying back to macOS 14 — see
[Build from source](#build-from-source) near the bottom.)

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

## Usage

### Add an account
1. Click the **gauge icon** → **Add Account…**.
2. Click **Sign in with Claude…** → a browser opens → sign in.
3. Copy the authorization **code** shown on the callback page, paste it into the app, and
   click **Connect**. Approve any Keychain prompt.
4. Within one sync cycle the account appears with its usage bars, and the menu-bar gauge
   reflects your most-constrained limit across all accounts.

### The app window
Click the menu-bar **gauge icon** for a popover — a quick glance at every account, plus buttons
that open the app's **single window**. That window has a sidebar; only **one window is ever
open**, and every action lives in it (you never need the popover for anything):

- **Dashboard** — one full-width tile per account, stacked top to bottom: large usage bars,
  reset day/date/time, per-account **Name**, **Menu label**
  (prefix), **sync interval**, a **"Synced N min ago"** button (click to sync that account now),
  **▲ / ▼ chevrons** in each tile's header to reorder accounts (the order is remembered and is
  also the order used in the popover and the menu-bar label), and remove / **Sign in again**
  controls. **Sign in again** re-authenticates *that* account in place — it keeps the account's
  name, menu label, interval and position instead of adding a second tile for the same person.
- **Add Account** — the sign-in flow above.
- **Settings** — default sync interval, **Launch at login**, **Show icon in Dock** (off by
  default; the app lives in the menu bar), and **Show each account's percentages in the menu bar**
  (uses the per-account "Menu label" prefixes to tell accounts apart, e.g. `W 20/19/5  P 30/40`),
  and **Show usage rings in the notch** (see below).
- **About** — the app icon, version, a link to this repo, and **Check for Updates…**.

### Notch panel (optional, off by default)
Turn on **Settings → Show usage rings in the notch** for a panel anchored to the MacBook notch —
or, on a display without one, a pill over the middle of the menu bar. Hover it and it expands
into one ring per account: the account's **worst** window, colour-coded on the same 70 % / 90 %
thresholds as the menu-bar icon, with the percentage underneath and a gear that opens the
Dashboard.

When a number can't be trusted, the ring says so instead of quietly showing a stale one — the
glyph in the middle becomes **offline**, **needs sign-in**, **rate limited** or **syncing**.

The menu-bar icon is unaffected: the notch is a second view of the same data, not a replacement,
and turning the setting off removes the panel immediately.

### Updates
The app checks for updates automatically via **Sparkle**; you can also trigger a check from
**Check for Updates…** in the **About** window. Update archives are **EdDSA-signed** (separate
from Apple's notarization — see [`SECURITY.md`](SECURITY.md#update-integrity-sparkle--eddsa));
Sparkle verifies that signature before installing anything.

> **Upgrading from a pre-0.2.0 build** (the old unsigned, non-sandboxed versions)? Install 0.2.0
> from the **DMG** on the Releases page rather than via a Sparkle auto-update — this release
> changed both its signing identity and its sandbox status — then **re-add your accounts once**
> (see [`SECURITY.md`](SECURITY.md#upgrading-from-a-pre-sandbox-install)).

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

## Build from source

Prefer to build it yourself (no download at all)? You need **Xcode 26+** (older Xcodes still
compile, but the resulting binary gets the legacy pre-Tahoe window chrome on macOS 26) and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/ivan-mihalic/claude-status-bar.git
cd claude-status-bar
brew install xcodegen

# Run the tests (swift-testing, Swift 6 toolchain):
swift test

# Build + launch the app:
xcodegen generate
xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar \
  -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Release/ClaudeStatusBar.app
```

`scripts/package.sh <version>` builds, signs (ad-hoc locally, or Developer ID + Apple
notarization + stapling when the CI signing env vars are set), and produces a notarized `.dmg`
plus a `.zip` for Sparkle.

The codebase is a headless, unit-tested Swift package (`Sources/ClaudeStatusBarCore` +
`Sources/ClaudeStatusBarApp`) plus a thin SwiftUI app target (`App/`, generated into an Xcode
project by `project.yml`). Design docs and implementation plans live under `docs/`.

## License

[PolyForm Noncommercial License 1.0.0](LICENSE.md) — **source-available, not open source.**
You may view the source and use it for **noncommercial** purposes (personal use, study,
hobby, research); **commercial use is not permitted**. Provided "as is", without any warranty.
© 2026 Ivan Mihalič.
