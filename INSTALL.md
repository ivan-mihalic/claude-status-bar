# Installing Claude Status Bar

Download the latest `ClaudeStatusBar-<version>.dmg` from
[Releases](https://github.com/ivan-mihalic/claude-status-bar/releases), open it, and drag
`ClaudeStatusBar.app` onto the **Applications** shortcut. (A `.zip` is also attached to each
release if you prefer.)

## First launch — get past Gatekeeper (one time)
The app is ad-hoc signed but **not notarized** by Apple (no paid Developer account), so on
first open macOS shows a scary *"unidentified developer / may be malware"* dialog. It is
**not** actually malware — this is just how macOS treats every un-notarized download. Do ONE of:
- **Terminal (cleanest):** `xattr -dr com.apple.quarantine /Applications/ClaudeStatusBar.app`, then open normally, OR
- **System Settings → Privacy & Security →** scroll to the blocked-app notice → **Open Anyway**
  (macOS 15 Sequoia removed the old right-click → Open shortcut for un-notarized apps).

You only do this **once** — Sparkle-delivered updates afterwards install without re-prompting.

> **Want zero Gatekeeper prompts?** Build from source (see the README) — a locally built app
> carries no quarantine flag and launches with no warning at all.

It runs as a **menu-bar app** (no Dock icon by default) — look for the gauge icon in the
top-right. You can enable a Dock icon in **Settings → Show icon in Dock**.

## Updates
The app self-updates via **Sparkle** ("Check for Updates…" in the menu-bar popover, plus
automatic checks). Updates are EdDSA-signed; Sparkle-delivered updates aren't re-quarantined,
so after the one-time first-launch step, updates install without the Gatekeeper prompt.

Note: unsigned builds may re-prompt for Keychain access after an update (the binary signature
changes) — click **Always Allow**.
