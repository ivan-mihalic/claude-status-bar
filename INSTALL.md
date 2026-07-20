# Installing Claude Status Bar

Download the latest `ClaudeStatusBar-<version>.dmg` from
[Releases](https://github.com/ivan-mihalic/claude-status-bar/releases), open it, and drag
`ClaudeStatusBar.app` onto the **Applications** shortcut. (A `.zip` is also attached to each
release if you prefer.)

## First launch
The app is signed with a **Developer ID Application** certificate, built with the **Hardened
Runtime**, and **notarized + stapled** by Apple. Opening it shows only the standard confirmation
dialog macOS shows for any notarized, verified-developer app (an **Open**/Cancel choice, not an
"unidentified developer" block) — click **Open**. No quarantine workaround, no "Open Anyway"
detour through System Settings needed.

Want to verify the signature/notarization yourself? See [`SECURITY.md`](SECURITY.md) for the
exact `codesign`/`spctl` commands.

It runs as a **menu-bar app** (no Dock icon by default) — look for the gauge icon in the
top-right. You can enable a Dock icon in **Settings → Show icon in Dock**.

> **Upgrading from a pre-sandbox install?** This update moved the app into the App Sandbox,
> which changes the Keychain group your tokens were saved under. **Re-add your accounts once**
> — see [`SECURITY.md`](SECURITY.md#upgrading-from-a-pre-sandbox-install).

## Updates
The app self-updates via **Sparkle** (automatic checks, plus a **Check for Updates…** button in
the **About** window). Update archives are **EdDSA-signed** — a signature layer separate from
Apple's notarization — and Sparkle verifies it before installing anything (see
[`SECURITY.md`](SECURITY.md#update-integrity-sparkle--eddsa)).

## More detail
See [`SECURITY.md`](SECURITY.md) for the full picture: how to verify the code signature, the
exact entitlements and why each exists, every network endpoint the app contacts, and where your
data (tokens vs. account metadata) is stored.
