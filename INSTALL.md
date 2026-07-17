# Installing Claude Status Bar

Download the latest `ClaudeStatusBar-<version>.zip` from
[Releases](https://github.com/ivan-mihalic/claude-status-bar/releases), unzip, and move
`ClaudeStatusBar.app` to `/Applications`.

## First launch (unsigned app)
This app is not notarized by Apple, so Gatekeeper blocks the first open. Do ONE of:
- **Right-click** the app → **Open** → **Open** (only needed once), OR
- `xattr -dr com.apple.quarantine /Applications/ClaudeStatusBar.app`

It runs as a **menu-bar app** (no Dock icon) — look for the gauge icon in the top-right.

## Updates
The app self-updates via **Sparkle** ("Check for Updates…" in the menu-bar popover, plus
automatic checks). Updates are EdDSA-signed; Sparkle-delivered updates aren't re-quarantined,
so after the one-time first-launch step, updates install without the Gatekeeper prompt.

Note: unsigned builds may re-prompt for Keychain access after an update (the binary signature
changes) — click **Always Allow**.
