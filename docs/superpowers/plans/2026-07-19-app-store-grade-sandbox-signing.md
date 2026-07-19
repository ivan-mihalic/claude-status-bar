# App Store-grade Sandbox + Developer ID Signing + Notarization — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `ClaudeStatusBar` App-Sandboxed, Hardened-Runtime, Developer-ID-signed and
notarized (App Store-grade), remove the Claude Code direct import, and add transparency artifacts
+ an AI signing guide — while keeping GitHub/DMG/Sparkle distribution.

**Architecture:** The SwiftUI app target (`App/`) gains a minimal entitlements file, hardened
runtime, a privacy manifest, and a first-run welcome sheet. The `ClaudeStatusBarCore` package
loses all cross-app file/Keychain code. `scripts/package.sh` is rewritten to sign inside-out
(Developer ID or ad-hoc), remove Sparkle's Downloader XPC, and (in CI) notarize + staple. The
Sparkle EdDSA update signing and Pages hosting are unchanged.

**Tech Stack:** Swift 6 / SwiftUI / AppKit, XcodeGen, Sparkle 2.6, `codesign`, `xcrun notarytool`,
`xcrun stapler`, GitHub Actions, App Store Connect API key.

## Global Constraints

- macOS **14.0+** deployment target.
- **Never** `codesign --deep` (Sparkle forbids it; sign each component individually).
- Every signature uses **Hardened Runtime** (`-o runtime`); Developer ID signatures also use
  `--timestamp` (ad-hoc local signatures omit `--timestamp`, which needs a real cert).
- Retain the **EdDSA/Sparkle** appcast signing (`SPARKLE_ED_PRIVATE_KEY`) and Pages hosting.
- **Secrets are never printed or committed** (only names may appear).
- Bundle id is **`cz.mihalic.claude-status-bar`**; Sparkle's Mach service names are
  `cz.mihalic.claude-status-bar-spks` and `cz.mihalic.claude-status-bar-spki`.
- Follow Apple + Sparkle documentation exactly (see the design spec's Sources).
- Individual Developer ID — the signer's legal name is public in the signature (accepted).

## File Structure

- **Delete:** `Sources/ClaudeStatusBarCore/Import/ClaudeCodeImporter.swift`,
  `Tests/ClaudeStatusBarCoreTests/ClaudeCodeImporterTests.swift`
- **Modify:** `Sources/ClaudeStatusBarApp/Environment/AppEnvironment.swift`,
  `Sources/ClaudeStatusBarApp/Accounts/AccountManager.swift`,
  `Sources/ClaudeStatusBarApp/Views/AddAccountView.swift`,
  `Sources/usage-cli/UsageCLI.swift`,
  `Tests/ClaudeStatusBarAppTests/AccountManagerTests.swift`,
  `project.yml`, `scripts/package.sh`, `.github/workflows/release.yml`,
  `App/ClaudeStatusBarMain.swift`, `README.md`, `INSTALL.md`
- **Create:** `App/ClaudeStatusBar.entitlements`, `App/PrivacyInfo.xcprivacy`,
  `App/WelcomeView.swift`, `SECURITY.md`, `docs/apple-signing-guide.md`

---

## Task 1: Remove the Claude Code import (app + CLI + Core)

**Files:**
- Delete: `Sources/ClaudeStatusBarCore/Import/ClaudeCodeImporter.swift`,
  `Tests/ClaudeStatusBarCoreTests/ClaudeCodeImporterTests.swift`
- Modify: `Sources/ClaudeStatusBarApp/Accounts/AccountManager.swift`,
  `Sources/ClaudeStatusBarApp/Environment/AppEnvironment.swift`,
  `Sources/ClaudeStatusBarApp/Views/AddAccountView.swift`,
  `Sources/usage-cli/UsageCLI.swift`,
  `Tests/ClaudeStatusBarAppTests/AccountManagerTests.swift`

**Interfaces:**
- `AccountManager.init` loses its `importer:` parameter; `detectClaudeCodeEmail()` is deleted.
- `usage-cli` reads the bearer token from the `CLAUDE_OAUTH_TOKEN` environment variable instead of
  importing it from Claude Code.

- [ ] **Step 1: Update `AccountManagerTests`** to construct `AccountManager` without an importer and
  drop any `detectClaudeCodeEmail` assertions. (This is the failing state: it won't compile against
  the current initializer until Step 3.)

- [ ] **Step 2: Run the suite to confirm the expected break**
  Run: `export PATH="$HOME/.swiftly/bin:$PATH"; swift test`
  Expected: compile failure referencing the removed `importer` parameter (proves the test now
  drives the new API).

- [ ] **Step 3: Remove the importer from `AccountManager`** — delete the `importer` stored property
  and init parameter and the `detectClaudeCodeEmail()` method.

- [ ] **Step 4: Remove the importer wiring from `AppEnvironment`** — delete the `ClaudeCodeImporter`
  construction and pass nothing for it to `AccountManager(...)`.

- [ ] **Step 5: Remove the "Use my Claude Code account" button** from `AddAccountView` (the button
  and its `detectClaudeCodeEmail()` call).

- [ ] **Step 6: Repoint `usage-cli`** — replace the `ClaudeCodeImporter` usage in
  `Sources/usage-cli/UsageCLI.swift` with:
  ```swift
  guard let token = ProcessInfo.processInfo.environment["CLAUDE_OAUTH_TOKEN"], !token.isEmpty else {
      FileHandle.standardError.write(Data("Set CLAUDE_OAUTH_TOKEN to an OAuth access token.\n".utf8))
      exit(2)
  }
  ```
  then feed `token` where the imported token was used.

- [ ] **Step 7: Delete** `Sources/ClaudeStatusBarCore/Import/ClaudeCodeImporter.swift` and
  `Tests/ClaudeStatusBarCoreTests/ClaudeCodeImporterTests.swift`.

- [ ] **Step 8: Run the full suite**
  Run: `export PATH="$HOME/.swiftly/bin:$PATH"; swift test`
  Expected: PASS, with no references to `ClaudeCodeImporter` / `detectClaudeCodeEmail` remaining
  (`grep -rn "ClaudeCodeImporter\|detectClaudeCodeEmail" Sources App Tests` returns nothing).

- [ ] **Step 9: Commit**
  ```bash
  git add -A && git commit -m "refactor: remove Claude Code import (sandbox-incompatible cross-app reads)"
  ```

---

## Task 2: App Sandbox + Hardened Runtime entitlements

**Files:**
- Create: `App/ClaudeStatusBar.entitlements`
- Modify: `project.yml`

**Interfaces:**
- `project.yml` references `App/ClaudeStatusBar.entitlements` via `CODE_SIGN_ENTITLEMENTS` and
  enables `ENABLE_HARDENED_RUNTIME`. `package.sh` (Task 5) signs with `--entitlements` pointing at
  the same file.

- [ ] **Step 1: Create `App/ClaudeStatusBar.entitlements`** (literal Mach names because `codesign`
  does not substitute build variables):
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <!-- Full App Sandbox (App Store-grade isolation). -->
      <key>com.apple.security.app-sandbox</key>
      <true/>
      <!-- Outgoing HTTPS only: Anthropic usage API, OAuth token host, Sparkle appcast + update download. -->
      <key>com.apple.security.network.client</key>
      <true/>
      <!-- Sparkle XPC communication, scoped to Sparkle's own Mach service names. -->
      <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
      <array>
          <string>cz.mihalic.claude-status-bar-spks</string>
          <string>cz.mihalic.claude-status-bar-spki</string>
      </array>
  </dict>
  </plist>
  ```

- [ ] **Step 2: Wire it into `project.yml`** — under `targets.ClaudeStatusBar.settings.base` add:
  ```yaml
        CODE_SIGN_ENTITLEMENTS: App/ClaudeStatusBar.entitlements
        ENABLE_HARDENED_RUNTIME: "YES"
  ```

- [ ] **Step 3: Regenerate + build (signing off compiles fine)**
  Run:
  ```bash
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  xcodegen generate && xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar \
    -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
  ```
  Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Ad-hoc sign with the entitlements and verify sandbox + hardened runtime** (no
  Developer ID needed to validate the entitlements locally):
  ```bash
  APP=build/Build/Products/Release/ClaudeStatusBar.app
  codesign -f -o runtime --entitlements App/ClaudeStatusBar.entitlements -s - "$APP"
  codesign -d --entitlements :- "$APP" | grep -q app-sandbox && echo "SANDBOX OK"
  codesign -dvvv "$APP" 2>&1 | grep -q "flags=.*runtime" && echo "HARDENED RUNTIME OK"
  ```
  Expected: `SANDBOX OK` and `HARDENED RUNTIME OK`.

- [ ] **Step 5: Smoke-test the sandboxed app** — launch the ad-hoc-signed app, add an account
  (OAuth browser + paste), confirm the token stores in the sandbox Keychain and a sync succeeds.
  (Manual GUI check; document the result in the task report.)

- [ ] **Step 6: Commit**
  ```bash
  git add -A && git commit -m "feat: App Sandbox + Hardened Runtime entitlements"
  ```

---

## Task 3: Privacy manifest

**Files:** Create `App/PrivacyInfo.xcprivacy`; Modify `project.yml` (ensure it ships as a resource).

- [ ] **Step 1: Create `App/PrivacyInfo.xcprivacy`:**
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>NSPrivacyTracking</key><false/>
      <key>NSPrivacyTrackingDomains</key><array/>
      <key>NSPrivacyCollectedDataTypes</key><array/>
      <key>NSPrivacyAccessedAPITypes</key>
      <array>
          <dict>
              <key>NSPrivacyAccessedAPIType</key>
              <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
              <key>NSPrivacyAccessedAPITypeReasons</key>
              <array><string>CA92.1</string></array>
          </dict>
      </array>
  </dict>
  </plist>
  ```

- [ ] **Step 2: Ensure it lands in the bundle** — since `sources: [App]` already includes the
  folder, confirm XcodeGen treats it as a resource. Regenerate and build, then:
  Run: `ls build/Build/Products/Release/ClaudeStatusBar.app/Contents/Resources/PrivacyInfo.xcprivacy`
  Expected: the file exists. If it does not, add an explicit `App/PrivacyInfo.xcprivacy` entry to the
  target's `sources` with `buildPhase: resources` in `project.yml` and rebuild.

- [ ] **Step 3: Commit**
  ```bash
  git add -A && git commit -m "feat: add PrivacyInfo.xcprivacy (no tracking, no data collection)"
  ```

---

## Task 4: First-run welcome sheet

**Files:** Create `App/WelcomeView.swift`; Modify `App/RootView.swift` (present the sheet).

**Interfaces:**
- `@AppStorage("didShowWelcome")` gates a one-time sheet presented from `RootView`. The first
  window a new user opens (to add an account) shows it.

- [ ] **Step 1: Create `App/WelcomeView.swift`** — app icon, one paragraph on what the app does, a
  bulleted transparency list (menu-bar only; Add Account triggers a Keychain prompt; it contacts
  only `claude.ai` / the OAuth host / `api.anthropic.com`; tokens live in the Keychain; a link to
  `SECURITY.md`), and a **Get Started** button whose action sets `didShowWelcome = true`.

- [ ] **Step 2: Present it from `RootView`** — add
  `@AppStorage("didShowWelcome") private var didShowWelcome = false` and
  `.sheet(isPresented: Binding(get: { !didShowWelcome }, set: { if !$0 { didShowWelcome = true } })) { WelcomeView() }`
  on the `NavigationSplitView`.

- [ ] **Step 3: Build**
  Run: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; xcodegen generate && xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build`
  Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Manual check** — fresh defaults (`defaults delete cz.mihalic.claude-status-bar
  didShowWelcome` or a clean container), open a window → welcome appears once; reopen → it does not.
  Document in the task report.

- [ ] **Step 5: Commit**
  ```bash
  git add -A && git commit -m "feat: first-run welcome sheet (transparency)"
  ```

---

## Task 5: Rewrite `scripts/package.sh` — inside-out signing, drop Downloader XPC, notarize + staple

**Files:** Modify `scripts/package.sh`.

**Interfaces (env the script reads):**
- `SIGN_IDENTITY` — Developer ID Application identity; defaults to `-` (ad-hoc) for local runs.
- `NOTARIZE` — when `1`, run notarytool + stapler (needs the API-key env below).
- `AC_API_KEY_PATH`, `AC_API_KEY_ID`, `AC_API_ISSUER_ID` — App Store Connect API key for notarytool.

- [ ] **Step 1: Rewrite `package.sh`** with this signing + packaging flow (no `--deep`):
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
  VERSION="${1:?usage: package.sh <version>}"
  IDENTITY="${SIGN_IDENTITY:--}"
  ENT="App/ClaudeStatusBar.entitlements"
  rm -rf build dist && mkdir -p dist
  xcodegen generate
  xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar \
    -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
  APP="build/Build/Products/Release/ClaudeStatusBar.app"
  FW="$APP/Contents/Frameworks/Sparkle.framework"

  # Drop Sparkle's Downloader XPC — the app has network.client, so it's unnecessary
  # (and pulls in a deprecated WebView). Keep Installer.xpc for the sandboxed install.
  rm -rf "$FW/Versions/B/XPCServices/Downloader.xpc"

  # Timestamp only with a real identity (ad-hoc cannot timestamp).
  if [ "$IDENTITY" = "-" ]; then TS=(); else TS=(--timestamp); fi
  sign() { codesign -f -o runtime "${TS[@]}" -s "$IDENTITY" "$@"; }

  # Sign inside-out; app last with entitlements. NEVER --deep.
  sign "$FW/Versions/B/XPCServices/Installer.xpc"
  sign "$FW/Versions/B/Autoupdate"
  sign "$FW/Versions/B/Updater.app"
  sign "$FW"
  codesign -f -o runtime "${TS[@]}" --entitlements "$ENT" -s "$IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"

  # DMG (volume icon + drag-to-Applications) — build from the signed app.
  ICONSET_TMP="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET_TMP"
  for pair in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" "128:128x128" \
              "256:128x128@2x" "256:256x256" "512:256x256@2x" "512:512x512" "1024:512x512@2x"; do
    src="${pair%%:*}"; dst="${pair##*:}"
    cp "App/Assets.xcassets/AppIcon.appiconset/icon_${src}.png" "$ICONSET_TMP/icon_${dst}.png"
  done
  ICNS="$(mktemp -d)/AppIcon.icns"; iconutil -c icns "$ICONSET_TMP" -o "$ICNS"
  DMG="dist/ClaudeStatusBar-$VERSION.dmg"
  STAGE="$(mktemp -d)/dmg"; mkdir -p "$STAGE"; cp -R "$APP" "$STAGE/"
  if command -v create-dmg >/dev/null 2>&1 && create-dmg \
        --volname "Claude Status Bar" --volicon "$ICNS" \
        --window-pos 200 120 --window-size 600 400 --icon-size 120 \
        --icon "ClaudeStatusBar.app" 150 200 --app-drop-link 450 200 \
        --hide-extension "ClaudeStatusBar.app" --no-internet-enable "$DMG" "$STAGE"; then
    echo "built $DMG via create-dmg"
  else
    ln -sf /Applications "$STAGE/Applications"
    hdiutil create -volname "Claude Status Bar" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
  fi

  # Notarize the DMG (one submission notarizes the app's cdhash too), then staple both.
  if [ "${NOTARIZE:-0}" = "1" ]; then
    xcrun notarytool submit "$DMG" --key "$AC_API_KEY_PATH" --key-id "$AC_API_KEY_ID" \
      --issuer "$AC_API_ISSUER_ID" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler staple "$APP"   # same cdhash, notarized via the DMG submission
    spctl -a -t open --context context:primary-signature -vv "$DMG" || true
  fi

  # Sparkle update zip contains the (stapled, when notarized) app.
  ZIP="dist/ClaudeStatusBar-$VERSION.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  echo "$ZIP"; echo "$DMG"
  ```

- [ ] **Step 2: Local ad-hoc run** (no cert/notarization)
  Run: `./scripts/package.sh 0.2.0`
  Expected: builds; `dist/ClaudeStatusBar-0.2.0.dmg` + `.zip` produced; the printed
  `codesign --verify --strict` step succeeds; `Downloader.xpc` is absent
  (`unzip -l dist/ClaudeStatusBar-0.2.0.zip | grep -c Downloader.xpc` → `0`).

- [ ] **Step 3: Verify the packaged app is sandboxed + hardened**
  ```bash
  MP="/Volumes/Claude Status Bar"; hdiutil attach dist/ClaudeStatusBar-0.2.0.dmg -nobrowse -quiet
  codesign -d --entitlements :- "$MP/ClaudeStatusBar.app" | grep -q app-sandbox && echo SANDBOX_OK
  codesign -dvvv "$MP/ClaudeStatusBar.app" 2>&1 | grep -q "flags=.*runtime" && echo RUNTIME_OK
  hdiutil detach "$MP" -quiet
  ```
  Expected: `SANDBOX_OK` and `RUNTIME_OK`.

- [ ] **Step 4: Commit**
  ```bash
  git add -A && git commit -m "build: Developer ID/ad-hoc inside-out signing, drop Downloader XPC, notarize+staple"
  ```

---

## Task 6: Release workflow — cert import + notarization secrets

**Files:** Modify `.github/workflows/release.yml`.

**Interfaces (new GitHub secrets):** `DEVELOPER_ID_CERT_P12_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`,
`APPLE_TEAM_ID`, `AC_API_KEY_P8_BASE64`, `AC_API_KEY_ID`, `AC_API_ISSUER_ID`
(plus existing `SPARKLE_ED_PRIVATE_KEY`).

- [ ] **Step 1: Add a signing-setup step before packaging** — import the Developer ID cert into a
  temporary keychain and write the API key to a temp file (never echo secret values):
  ```yaml
      - name: Set up signing + notarization
        env:
          CERT_P12_BASE64: ${{ secrets.DEVELOPER_ID_CERT_P12_BASE64 }}
          CERT_PASSWORD: ${{ secrets.DEVELOPER_ID_CERT_PASSWORD }}
          AC_API_KEY_P8_BASE64: ${{ secrets.AC_API_KEY_P8_BASE64 }}
        run: |
          set -euo pipefail
          KEYCHAIN="$RUNNER_TEMP/signing.keychain-db"
          KEYCHAIN_PW="$(openssl rand -base64 24)"
          security create-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN"
          security set-keychain-settings -lut 3600 "$KEYCHAIN"
          security unlock-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN"
          CERT="$RUNNER_TEMP/cert.p12"; printf '%s' "$CERT_P12_BASE64" | base64 -d > "$CERT"
          security import "$CERT" -k "$KEYCHAIN" -P "$CERT_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PW" "$KEYCHAIN"
          security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
          rm -f "$CERT"
          printf '%s' "$AC_API_KEY_P8_BASE64" | base64 -d > "$RUNNER_TEMP/AuthKey.p8"
          echo "KEYCHAIN=$KEYCHAIN" >> "$GITHUB_ENV"
  ```

- [ ] **Step 2: Run packaging with signing + notarization** — replace the current
  `./scripts/package.sh "$VERSION"` invocation with:
  ```yaml
      - name: Package (signed + notarized)
        env:
          # Prefix match: the temp keychain holds exactly one Developer ID Application
          # identity, so codesign resolves it without needing the signer's exact name.
          SIGN_IDENTITY: "Developer ID Application"
          NOTARIZE: "1"
          AC_API_KEY_PATH: ${{ runner.temp }}/AuthKey.p8
          AC_API_KEY_ID: ${{ secrets.AC_API_KEY_ID }}
          AC_API_ISSUER_ID: ${{ secrets.AC_API_ISSUER_ID }}
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          ./scripts/package.sh "$VERSION"
  ```
  (`notarytool` with an App Store Connect API key needs only the key/key-id/issuer — no Team ID.
  `APPLE_TEAM_ID` is kept only as an optional verification convenience, not required by the build.)

- [ ] **Step 3: Cleanup step (always)** — delete the temp keychain + API key:
  ```yaml
      - name: Clean up signing material
        if: always()
        run: |
          security delete-keychain "$KEYCHAIN" 2>/dev/null || true
          rm -f "$RUNNER_TEMP/AuthKey.p8"
  ```

- [ ] **Step 4: Keep** the existing EdDSA appcast-signing, GitHub Release upload (dmg + zip), and
  Pages steps unchanged.

- [ ] **Step 5: Validate the YAML**
  Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('YAML OK')"`
  Expected: `YAML OK`. (A real signed release is verified in Task 8 once the user adds secrets.)

- [ ] **Step 6: Commit**
  ```bash
  git add -A && git commit -m "ci: import Developer ID cert + notarize releases via App Store Connect API key"
  ```

---

## Task 7: Transparency docs — SECURITY.md + README/INSTALL update

**Files:** Create `SECURITY.md`; Modify `README.md`, `INSTALL.md`.

- [ ] **Step 1: Write `SECURITY.md`** covering: the signing identity + how to verify
  (`codesign -dvvv /Applications/ClaudeStatusBar.app`, `spctl -a -vv`), the exact entitlements and
  why each exists, the endpoints the app contacts (`claude.ai`, the OAuth token host,
  `api.anthropic.com/api/oauth/usage`), where data lives (Keychain + the app sandbox container),
  the Sparkle EdDSA update-integrity note, and a statement that the app is App-Sandboxed with no
  file access.

- [ ] **Step 2: Update `README.md` + `INSTALL.md`** — replace the "unsigned / Gatekeeper bypass"
  first-launch section with the notarized flow (drag to Applications → benign verified-developer
  prompt → Open), link `SECURITY.md`, and remove the `xattr -dr com.apple.quarantine` instructions.

- [ ] **Step 3: Commit**
  ```bash
  git add -A && git commit -m "docs: SECURITY.md + notarized install instructions"
  ```

---

## Task 8: AI signing guide (deliverable)

**Files:** Create `docs/apple-signing-guide.md`.

- [ ] **Step 1: Write `docs/apple-signing-guide.md`** — a numbered, do-this-then-that guide:
  1. Enroll / pay for the Apple Developer Program.
  2. Create a **Developer ID Application** certificate (CSR via Keychain Access → request from
     developer.apple.com → download → double-click to install), then export it as `.p12` with a
     password (Keychain Access → export).
  3. Read the identity string: `security find-identity -v -p codesigning` → copy
     `Developer ID Application: <Name> (<TEAMID>)` (this fills `SIGN_IDENTITY` in `release.yml`).
  4. Create an **App Store Connect API key** (App Store Connect → Users and Access → Integrations →
     Keys → generate a key with access sufficient for notarization) → download the `.p8`, note the
     **Key ID** and **Issuer ID**.
  5. Find the **Team ID** (Apple Developer → Membership).
  6. Add the GitHub secrets with exact commands that never print values, e.g.:
     ```bash
     base64 -i DeveloperID.p12   | gh secret set DEVELOPER_ID_CERT_P12_BASE64 --repo ivan-mihalic/claude-status-bar
     base64 -i AuthKey_XXXX.p8   | gh secret set AC_API_KEY_P8_BASE64        --repo ivan-mihalic/claude-status-bar
     gh secret set DEVELOPER_ID_CERT_PASSWORD --repo ivan-mihalic/claude-status-bar   # paste when prompted
     gh secret set APPLE_TEAM_ID --repo ivan-mihalic/claude-status-bar
     gh secret set AC_API_KEY_ID --repo ivan-mihalic/claude-status-bar
     gh secret set AC_API_ISSUER_ID --repo ivan-mihalic/claude-status-bar
     ```
  7. Push a tag → the release workflow signs + notarizes.
  8. Verify: download the DMG, `spctl -a -t open -vv ClaudeStatusBar-*.dmg` (accepted, source =
     Notarized Developer ID), `codesign -dvvv` on the installed app (shows the Developer ID + the
     sandbox/runtime flags).

- [ ] **Step 2: Commit**
  ```bash
  git add -A && git commit -m "docs: Apple signing + notarization guide"
  ```

---

## Task 9: Version bump + end-to-end (after the user adds secrets)

**Files:** Modify `project.yml`.

- [ ] **Step 1: Bump** `CFBundleShortVersionString`/`MARKETING_VERSION` to `0.2.0` and
  `CFBundleVersion` to `8` in `project.yml`; commit.

- [ ] **Step 2: (User action)** add the six new secrets per the guide, then tag `v0.2.0`.

- [ ] **Step 3: Verify the release** — the release workflow succeeds; download the DMG on a clean
  Mac; `spctl -a -t open -vv` reports `accepted` + `Notarized Developer ID`; open without any
  scary prompt; `codesign -dvvv` shows the Developer ID and `flags=…runtime` + `app-sandbox`; the
  Sparkle "Check for Updates" round-trip installs cleanly.

---

## Notes on execution order & dependencies
- Tasks 1–5 and 7–8 can be fully built and verified **now** (ad-hoc signing validates sandbox +
  hardened runtime locally). Task 6 is authored now but its live run + Task 9's tag require the
  user's paid account + secrets. Do not block earlier tasks on the account.
