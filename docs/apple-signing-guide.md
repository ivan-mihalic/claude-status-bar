# Apple Developer ID Signing & Notarization Setup

This is a one-time, do-this-then-that guide for the repo owner to set up **Developer ID**
code signing and **notarization** so the `Release` GitHub Actions workflow
(`.github/workflows/release.yml`) can produce a signed, notarized, stapled DMG/ZIP every
time you push a `v*` tag.

Everything here happens **once** (the Developer ID certificate is valid ~5 years; the API
key doesn't expire unless you revoke it). After this setup, releases are fully automated —
push a tag, wait for CI, done.

**Scope note:** `SPARKLE_ED_PRIVATE_KEY` (used to sign Sparkle update archives) is a
separate concern from Apple signing/notarization and is already configured in this repo's
secrets — nothing to do here for it.

## What you'll end up with

Six GitHub Actions secrets on `ivan-mihalic/claude-status-bar`, matching exactly what
`.github/workflows/release.yml` reads:

| Secret name | Holds | Read by `release.yml` as |
|---|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | base64 of your exported `.p12` | `CERT_P12_BASE64` (Set up signing + notarization step) |
| `DEVELOPER_ID_CERT_PASSWORD` | the `.p12` export password | `CERT_PASSWORD` (same step) |
| `AC_API_KEY_P8_BASE64` | base64 of your App Store Connect API key `.p8` | `AC_API_KEY_P8_BASE64` (same step) |
| `AC_API_KEY_ID` | the API key's Key ID | `AC_API_KEY_ID` (Package step) |
| `AC_API_ISSUER_ID` | your Issuer ID | `AC_API_ISSUER_ID` (Package step) |
| `APPLE_TEAM_ID` *(optional)* | your 10-character Team ID | **not currently read** by the workflow — `SIGN_IDENTITY: "Developer ID Application"` is a prefix match against the one identity in the temp keychain, so the Team ID isn't needed by CI. Storing it anyway is harmless and useful as a reference if the workflow ever needs to disambiguate. |

The workflow imports your certificate into a **fresh, throwaway keychain** for each CI run
and deletes it afterward (see the "Clean up signing material" step). Because `SIGN_IDENTITY`
is only the prefix `"Developer ID Application"` (not your full name/Team ID), **that
temporary keychain must end up with exactly one `Developer ID Application` identity** — see
the warning in Step 2 about what to export.

---

## Step 1 — Enroll in the Apple Developer Program

1. Go to <https://developer.apple.com/programs/enroll/> and enroll (Individual or
   Organization) — this is the paid membership ($99/year as of writing).
2. Wait for payment/enrollment to complete. You'll get a confirmation email once your
   account is active. Everything below requires an active, paid membership — Developer ID
   certificates aren't available on a free Apple ID.

## Step 2 — Create a Developer ID Application certificate, then export it as `.p12`

### 2a. Create a Certificate Signing Request (CSR)

1. Open **Keychain Access** (Spotlight → "Keychain Access").
2. Menu bar → **Keychain Access → Certificate Assistant → Request a Certificate From a
   Certificate Authority…**
3. Fill in:
   - **User Email Address** — your Apple ID email (doesn't need to match anything else).
   - **Common Name** — your name or org name, e.g. "Jane Doe" or "Acme Inc.".
   - **CA Email Address** — leave blank.
   - Select **"Saved to disk"** (not "Emailed to CA").
4. Save the resulting `CertificateSigningRequest.certSigningRequest` file somewhere you can
   find it. This also generates a matching private key in your login keychain — don't
   delete it before Step 2b finishes (it's what turns the downloaded certificate into a
   usable identity).

### 2b. Create the certificate at developer.apple.com

1. Go to <https://developer.apple.com/account/resources/certificates/list>.
2. Click **+** to create a new certificate.
   - If you don't see **Developer ID Application** as an option, you may need to accept the
     Developer ID agreement first: **Account → Agreements, Tax, and Banking** (or you may
     need the Account Holder / Admin role — Developer ID certs require elevated permissions
     on some team setups).
3. Select **Developer ID Application**, click **Continue**.
4. Upload the `.certSigningRequest` file from Step 2a, click **Continue**.
5. **Download** the resulting `.cer` file.
6. **Double-click** the downloaded `.cer` to install it into Keychain Access (login
   keychain). Combined with the private key from Step 2a, this now shows up under
   **Keychain Access → My Certificates** as a complete identity:
   `Developer ID Application: <Your Name> (<TEAMID>)`.

### 2c. Export as `.p12`

1. In **Keychain Access → My Certificates**, find the
   `Developer ID Application: …` entry.
2. Right-click it → **Export "Developer ID Application: …"…**
3. Save as e.g. `DeveloperID.p12`, **File Format: Personal Information Exchange (.p12)**.
4. Set a strong **export password** when prompted — you'll need this exact password again
   in Step 6. You may also be prompted for your macOS login-keychain password to authorize
   the export.

> **WARNING — export exactly one identity.** Select and export *only* the single
> `Developer ID Application: …` row, not "All Items" and not multiple certificates at once.
> If the `.p12` ends up containing more than one `Developer ID Application` identity (e.g.
> an old, still-valid one from a previous cert), the CI keychain in Step 6/7 will contain
> more than one match for the `SIGN_IDENTITY: "Developer ID Application"` prefix, and
> `codesign`/`security import` will fail with an ambiguous-identity error.

## Step 3 — Verify the identity string locally

```bash
security find-identity -v -p codesigning
```

Expect a line like:

```
  1) A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6A1B2 "Developer ID Application: Jane Doe (AB12CD34EF)"
     1 valid identities found
```

(You may see other identities too, e.g. leftover `Apple Development` certs — those are
fine and unrelated; only the `Developer ID Application: …` line matters here.)

Copy the full string in quotes: `Developer ID Application: <Name> (<TEAMID>)`. The
10-character code in parentheses is your **Team ID** (cross-check against Step 5). This
identity string is what `release.yml`'s `SIGN_IDENTITY` prefix-matches against — you don't
need to paste the full string anywhere, just confirm there's exactly one such line.

## Step 4 — Create an App Store Connect API key

1. Go to <https://appstoreconnect.apple.com/> → **Users and Access** → **Integrations**
   tab → **Team Keys** (sometimes just labeled "Keys").
2. Click **Generate API Key** (or **+**).
3. **Name**: something identifiable, e.g. `CI Notarization`.
4. **Access**: choose the least-privileged role sufficient for notarization — **Developer**
   works (notarization only needs the ability to submit builds; it doesn't need Admin/App
   Manager). If your team's role options differ, pick the lowest one available that still
   permits notarization.
5. Click **Generate**. In the resulting table row, note:
   - **Key ID** — a short alphanumeric string.
   - **Issuer ID** — a UUID, shown at the top of the Keys page (shared across all your
     team's keys).
6. Click **Download API Key** and save the `AuthKey_<KEYID>.p8` file.

> **This download link works exactly once.** Apple does not let you re-download the same
> `.p8` later — if you lose it, revoke the key and generate a new one.

## Step 5 — Find your Team ID

1. Go to <https://developer.apple.com/account> → **Membership** (or **Membership
   Details**).
2. Copy the **Team ID** — a 10-character alphanumeric string.
3. It should match the code you saw in parentheses in Step 3's output.

## Step 6 — Add the GitHub secrets

All commands below are written so **no secret value is ever printed to your terminal,
shell history, or logs.** Run them from the directory where you saved the downloaded
files (adjust filenames to match what you actually downloaded).

```bash
# File-based secrets: base64-encode, pipe straight into gh (never touches disk as base64,
# never printed).
base64 -i DeveloperID.p12  | gh secret set DEVELOPER_ID_CERT_P12_BASE64 --repo ivan-mihalic/claude-status-bar
base64 -i AuthKey_XXXX.p8  | gh secret set AC_API_KEY_P8_BASE64        --repo ivan-mihalic/claude-status-bar

# Scalar secrets: gh prompts you interactively and reads the value straight into the
# encrypted request — nothing is echoed back or logged.
gh secret set DEVELOPER_ID_CERT_PASSWORD --repo ivan-mihalic/claude-status-bar   # paste the .p12 export password from Step 2c
gh secret set AC_API_KEY_ID              --repo ivan-mihalic/claude-status-bar   # paste the Key ID from Step 4
gh secret set AC_API_ISSUER_ID           --repo ivan-mihalic/claude-status-bar   # paste the Issuer ID from Step 4
gh secret set APPLE_TEAM_ID              --repo ivan-mihalic/claude-status-bar   # optional, paste the Team ID from Step 5
```

Verify they landed (this only lists secret **names**, never values):

```bash
gh secret list --repo ivan-mihalic/claude-status-bar
```

You should see all five (or six, with the optional `APPLE_TEAM_ID`) names listed above.

> **WARNING — never commit or echo secret material.**
> - Never `git add`/commit `DeveloperID.p12`, `AuthKey_*.p8`, or the export password —
>   not even temporarily, not even in a private branch.
> - Never run `cat`, `echo`, `pbcopy | pbpaste` (with output shown), or print these files'
>   contents to a terminal you might screen-share or record.
> - When you're done, delete the local `.p12`/`.p8` files (or move them to your own
>   password manager) — GitHub Secrets is now the source of truth for CI, and CI deletes
>   its copies after each run (see the workflow's "Clean up signing material" step).
> - If a value is ever pasted into a terminal, chat, or ticket by accident, rotate it
>   immediately: re-export a new `.p12`/generate a new API key and re-run the `gh secret
>   set` commands above.

## Step 7 — Push a tag to trigger the release

```bash
git tag v1.0.0
git push origin v1.0.0
```

Pushing a tag matching `v*` triggers `.github/workflows/release.yml`, which builds,
signs with your Developer ID identity, notarizes via the App Store Connect API key,
staples the notarization ticket to both the `.app` and `.dmg`, and publishes a GitHub
Release plus a Sparkle appcast update.

Watch it run — either open
<https://github.com/ivan-mihalic/claude-status-bar/actions>, or from the CLI:

```bash
gh run list --repo ivan-mihalic/claude-status-bar --limit 1
gh run watch <run-id> --repo ivan-mihalic/claude-status-bar
```

## Step 8 — Verify the signed + notarized result

1. Download the DMG from the new release:
   ```bash
   gh release download v1.0.0 --repo ivan-mihalic/claude-status-bar --pattern '*.dmg'
   ```
2. Check Gatekeeper's verdict on the DMG itself:
   ```bash
   spctl -a -t open -vv ClaudeStatusBar-*.dmg
   ```
   Expect:
   ```
   ClaudeStatusBar-1.0.0.dmg: accepted
   source=Notarized Developer ID
   origin=Developer ID Application: <Your Name> (<TEAMID>)
   ```
3. Open the DMG and drag `ClaudeStatusBar.app` into `/Applications`, then check the
   installed app's signature and entitlements together:
   ```bash
   codesign -dvvv --entitlements :- /Applications/ClaudeStatusBar.app
   ```
   Expect, among the output:
   - `Authority=Developer ID Application: <Your Name> (<TEAMID>)`
   - `flags=0x10000(runtime)` — confirms the Hardened Runtime is on.
   - In the printed entitlements plist near the end: `com.apple.security.app-sandbox` →
     `<true/>` — confirms the app is running under the full App Sandbox.

   (See [`SECURITY.md`](../SECURITY.md#signing--notarization) for the same checks phrased
   for end users, and for the full entitlements rationale.)

If any of the above doesn't match — e.g. `spctl` says `rejected`, or `codesign` shows no
`Authority=Developer ID Application`, or `flags` lacks `runtime` — see Troubleshooting
below before re-tagging.

---

## Troubleshooting

- **`security find-identity` shows more than one `Developer ID Application` line** —
  you have multiple valid Developer ID certs (e.g. an old one not yet expired). Re-export
  the `.p12` selecting only the current one (Step 2c), or revoke the stale certificate at
  developer.apple.com first.
- **`security import`/`codesign` in CI fails with an ambiguous or "multiple matches"
  identity error** — the `.p12` contains more than one `Developer ID Application` identity;
  see the WARNING in Step 2c.
- **Notarization fails or times out** — fetch the detailed rejection log with the same
  credentials used in CI:
  ```bash
  xcrun notarytool log <submission-id> --key AuthKey_XXXX.p8 --key-id <KEYID> --issuer <ISSUER_ID>
  ```
  The submission ID is printed by `notarytool submit` (visible in the CI job log for the
  "Package (signed + notarized)" step).
- **`gh secret set` seems to hang** — it's waiting for you to paste the value and press
  Enter/Ctrl-D; it isn't reading from a file unless you redirect stdin.
- **API key "Access" role turns out insufficient** — regenerate the key in Step 4 with a
  higher role and repeat Step 6 for the three `AC_API_*` secrets (the old key still works
  until you explicitly revoke it in App Store Connect).
