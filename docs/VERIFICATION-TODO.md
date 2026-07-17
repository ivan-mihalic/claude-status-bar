# Verification TODO — critical, do before trusting the app

## 🔴 CRITICAL: live end-to-end OAuth + usage-endpoint verification (Plan 2, Task 14)

**Status: NOT DONE.** Deferred because the developer was remote via SSH with no GUI / remote-desktop access, so the interactive menu-bar + browser-OAuth flow couldn't be exercised.

Everything around it is verified: SPM builds 0 warnings, 66 unit tests pass (swift-testing), and the `.app` builds `** BUILD SUCCEEDED **` locally and on CI (macos-15). What is NOT yet confirmed by a human is the **runtime** behavior of the reverse-engineered endpoint through the real UI.

### How to verify (at the Mac, with a display)

1. Build + launch the app:
   ```bash
   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   cd <repo>
   xcodegen generate
   xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar \
     -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
   open build/Build/Products/Debug/ClaudeStatusBar.app
   ```
2. In the menu bar (top-right) find the **gauge icon + "—"** (LSUIElement app, no Dock icon).
3. Click it → **Add Account…** → optionally **Use my Claude Code account** (pre-fills email) → **Sign in with Claude…** (browser opens) → sign in → copy the code from Anthropic's callback page → paste → **Connect**. Approve the **Keychain "Always Allow"** prompt.
4. **Confirm:** within one sync cycle the account shows **3 usage bars** (Session / Week all / Week premium) with real percentages + reset countdowns, and the menu-bar indicator shows the max %. Also confirm the Dashboard window (Open Dashboard) and quit→relaunch persistence (account + last snapshot reappear from `SnapshotStore`, no secrets on disk).
5. **Multi-account:** add a SECOND account (repeat) and confirm both appear independently, and that the second add works cleanly (the stale-`@State` fix — `AddAccountView` resets on reopen).
6. **Remove:** remove an account and confirm it disappears and does NOT reappear after a sync cycle or relaunch (the resurrection fix).

### If the endpoint behavior differs from the confirmed response shape
The whole data path is unit-tested against the research-confirmed `/api/oauth/usage` JSON shape. If the live call returns a different shape / a 4xx, adjust `UsageDTO`/`UsageAdapter` (the tolerant adapter should degrade, not crash) and re-run. The `usage-cli` (Plan 1) is a faster loop for this: `swift run usage-cli` reads the local Claude Code token and prints the bars (also needs a Keychain "Allow" at a real terminal).

## 🟠 Plan 3 — manual/at-Mac tasks (distribution + self-update)

The distribution code (error surface, Sparkle wiring, `scripts/package.sh`, `release.yml`, `INSTALL.md`) is done + CI-buildable. Two tasks need a human at the Mac:

### Task 3 — generate the EdDSA signing keys
1. Get Sparkle's `bin/generate_keys` (from the Sparkle distribution matching the resolved SPM version, or the resolved SwiftPM artifacts under `build/.../SourcePackages/artifacts/sparkle/`). Run `./bin/generate_keys` → creates a private key in the login Keychain, prints the **public** key.
2. Put the printed public key into **`project.yml`** → `info.properties.SUPublicEDKey` (NOT `App/Info.plist` directly — `xcodegen generate` regenerates the plist from `project.yml`, so a direct plist edit gets clobbered). Regenerate, rebuild, commit `project.yml`.
3. Export the private key and add it as the GitHub Actions repo secret `SPARKLE_ED_PRIVATE_KEY`. **Never commit it.** Then enable GitHub Pages (Settings → Pages → Source: GitHub Actions).

### Task 7 — cut a release + verify the update round-trip
1. **Before the first tag:** confirm `generate_appcast`'s private-key flag name (`--ed-key-file` used in `release.yml`) against the resolved Sparkle version — check via context7 MCP or `generate_appcast --help`. Adjust `release.yml` if the flag differs.
2. Bump version in `project.yml`, tag `v0.1.0`, push. Watch the `Release` workflow → it should create a Release with the zip + publish `appcast.xml` to Pages. Confirm `https://ivan-mihalic.github.io/claude-status-bar/appcast.xml` loads and has an `<item>` with a `sparkle:edSignature`.
3. Install `0.1.0`, then bump to `0.1.1`, tag `v0.1.1`, push. In the installed app → **Check for Updates…** → Sparkle should find, verify (EdDSA), download, and install `0.1.1`. Confirm relaunch at `0.1.1`.

## Also un-run (lower priority)
- **Plan 1 `usage-cli` live E2E** — same Keychain-consent reason; never run by a human. The Plan-2 Task-14 verification above supersedes it (the app exercises the real OAuth + endpoint through its own grant).
