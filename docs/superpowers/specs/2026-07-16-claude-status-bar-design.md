# claude-status-bar — Design Spec

**Date:** 2026-07-16
**Status:** Approved (brainstorming) → ready for implementation planning
**Repo:** github.com/ivan-mihalic/claude-status-bar (private)

## 1. Overview

Native macOS menu-bar app that tracks Claude subscription usage (Pro/Max) for
**multiple independent Claude accounts simultaneously**, replicating what the
Claude Code CLI `/usage` command shows: current 5-hour session, current week
(all models), current week (premium/most-expensive model, e.g. Fable), each with
a reset time and a progress bar.

Differentiator vs. existing tools: existing apps do single-account or account
*switching*; this app shows **all accounts at once** with **per-model** bars, a
nice dashboard, per-account sync intervals, and self-update.

## 2. Goals / Non-goals

**Goals (v1)**
- Connect N independent Claude accounts via OAuth (browser PKCE) + one-click
  import of the account already logged into Claude Code (keychain).
- Per account, show 3 usage windows with progress bars + reset countdowns:
  Session (5h), Week (all models), Week (premium model).
- Menu-bar widget: icon + compact "most-constrained %" indicator; click → popover
  listing all accounts stacked with their mini bars.
- Dashboard window: richer graphical per-account view.
- Per-account configurable sync interval (default 300 s, hard floor 60 s).
- Direct install from GitHub Releases (ZIP), unsigned; Sparkle self-update.

**Non-goals (v1)**
- No historical/time-series charts (possible fast-follow).
- No local `~/.claude/projects` cost/token estimation (ccusage-style).
- No notarization / Apple Developer ID (unsigned for now; add later).
- No Homebrew tap. No cross-platform (macOS only).

## 3. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Stack | Native SwiftUI, macOS 14+ | Truly native menu bar (MenuBarExtra), best UX, free Keychain, Sparkle. |
| Data source | Official OAuth usage endpoint | Matches `/usage` exactly incl. per-model. Only path that gives % of limit for arbitrary accounts. |
| Auth | Browser OAuth PKCE + import from Claude Code keychain | Full-login token has `user:profile` scope → per-model bars. |
| Token storage | macOS Keychain, one item per account | Secrets never in logs/plists. |
| Signing | Unsigned (v1) | Personal project; no Apple account. Sparkle uses free EdDSA. |
| Distribution | Direct ZIP from GitHub Releases + Sparkle | User wants direct install, no Homebrew. |
| Menu-bar indicator | Yes — max utilization %, color-coded | Instant "am I near a limit" signal. |

## 4. Confirmed technical facts (from research, treat as unstable/undocumented)

All endpoints below are community-reverse-engineered and **undocumented by
Anthropic**. Build an adapter layer; verify empirically at implementation time.

### 4.1 OAuth 2.0 + PKCE (S256)
- Authorize: `https://claude.ai/oauth/authorize`
- Token / refresh: `https://console.anthropic.com/v1/oauth/token`
  (newer binary: `https://platform.claude.com/v1/oauth/token` — **domain caveat:
  try both, don't hardcode**)
- Public client_id: `9d1c250a-e61b-44d9-88ed-5944d1962f5e` (public, not a secret)
- Redirect URI: `https://console.anthropic.com/oauth/code/callback`
  (or `platform.claude.com/...`) — the callback page displays the code for paste;
  also try localhost auto-capture if the client allows it.
- Token exchange & refresh body: `application/x-www-form-urlencoded`
  (JSON body returns `400 invalid_grant`).
- Scope needed for usage endpoint: must include `user:profile` (full browser
  login). `claude setup-token` (only `user:inference`) → usage endpoint 403.
- Refresh: `POST <token_url>` with `grant_type=refresh_token`, `refresh_token`,
  `client_id`. Returns rotated access + refresh + `expires_in`.
- Access-token lifetime ≈ 8 h. Refresh sparingly (only when near expiry); refresh
  endpoint also rate-limits.

### 4.2 Usage endpoint (core)
- `GET https://api.anthropic.com/api/oauth/usage`
- Headers:
  - `Authorization: Bearer <access_token>`
  - `anthropic-beta: oauth-2025-04-20`
  - `User-Agent: claude-code/<version>`
- Response JSON (shape, verbatim from a captured response):
  ```json
  {
    "five_hour":        { "utilization": 33.0, "resets_at": "2026-04-11T07:00:00+00:00" },
    "seven_day":        { "utilization": 13.0, "resets_at": "2026-04-17T00:59:59+00:00" },
    "seven_day_opus":   null,
    "seven_day_sonnet": { "utilization": 1.0,  "resets_at": "2026-04-16T03:00:00+00:00" },
    "extra_usage":      { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
  }
  ```
  - `utilization` = percent 0–100; `resets_at` = ISO-8601 UTC.
  - `five_hour` → Session; `seven_day` → Week (all); `seven_day_<model>` → per-model
    weekly (premium). Per-model keys are dynamic (opus/sonnet/fable/…); the adapter
    picks/labels whatever the API returns as the premium window(s). `null` when unused.

### 4.3 Rate-limit behavior (THE big risk)
- `/api/oauth/usage` 429s aggressively **per token**; backoff escalates
  30→60→120→240→300 s and sticks at 300 s with **no `Retry-After`**.
- Polling < ~60 s reliably breaks it. → poll multi-minute, stagger across accounts,
  cache last-good, exponential backoff on 429.
- No documented per-IP aggregate limit (unknown).

### 4.4 Fallback data source (later, optional)
- Every `api.anthropic.com/v1/messages` response carries
  `anthropic-ratelimit-unified-*` headers (5h/7d utilization + reset, status).
  Gives only unified 5h/7d (no per-model) and requires a tiny inference call.
  Reserved as a fallback if `/api/oauth/usage` shape changes/breaks.

### 4.5 Claude Code credential import (macOS)
- Keychain item: service `Claude Code-credentials`, account = macOS `$USER`.
- Value is JSON: `{ "claudeAiOauth": { accessToken, refreshToken, expiresAt(ms),
  scopes[], subscriptionType, rateLimitTier } }`.
- Account label from `~/.claude.json` → `oauthAccount = { accountUuid,
  emailAddress, organizationUuid }`.

## 5. Architecture

Menu-bar app (LSUIElement, no Dock icon). SwiftUI `App` with three scenes:

```
UI (SwiftUI)
  MenuBarExtra   widget: icon + "max util %" indicator; click → popover with
                 all accounts stacked (email + 3 mini bars + reset + last-synced);
                 footer: + Add account | Open Dashboard | Settings
  WindowGroup    Dashboard: per-account large progress bars, reset countdowns,
                 status badge, per-account interval + remove + re-auth
  Settings       default interval, launch-at-login, Check for Updates

Core services
  AppState       @Observable; list of Accounts + snapshots; drives all UI
  OAuthService   PKCE build/exchange/refresh; domain fallback
  UsageAPIClient GET /api/oauth/usage; normalize → UsageSnapshot; tolerant adapter
  SyncScheduler  per-account timers, staggered, floor 60s, 429 backoff, refresh-on-expiry
  KeychainStore  token bundle per account; never logs secrets
  SnapshotStore  account metadata + last-good snapshot (Application Support, no secrets)

Updater
  Sparkle 2.x    EdDSA-signed appcast on GitHub Pages; "Check for Updates" + auto-check
```

Token secrets live **only** in Keychain. Application Support holds account
metadata + last snapshot (no secrets) so the UI shows last-good values on launch.

## 6. Data model

```
Account
  id: UUID
  label: String            // email from oauthAccount / profile
  accountUuid: String?
  syncInterval: Int        // seconds, default 300, floor 60
  status: .ok | .rateLimited(retryAt) | .needsReauth | .offline
  lastSnapshot: UsageSnapshot?
  lastSyncedAt: Date?
  // tokens NOT stored here — Keychain only, referenced by id

UsageWindow
  key: String              // "five_hour" | "seven_day" | "seven_day_<model>"
  label: String            // "Session" | "Week (all)" | "Week (Fable)"
  utilization: Double      // 0..100
  resetsAt: Date

UsageSnapshot
  session: UsageWindow
  weekAll: UsageWindow
  weekPremium: [UsageWindow]   // dynamic per-model windows the API returned
  fetchedAt: Date

TokenBundle (Keychain only)
  accessToken, refreshToken, expiresAt(ms), scopes[]
```

## 7. Data flow

1. **Add account** → OAuthService builds PKCE authorize URL → browser login →
   auth code (paste or localhost capture) → exchange → TokenBundle → Keychain →
   fetch profile/email for label → initial usage fetch.
   *Or* one-click **import** from Claude Code keychain → same TokenBundle path.
2. **Sync loop (per account)** → staggered timer fires → if access token near
   expiry, refresh (rotate + persist) → `GET /api/oauth/usage` → adapter normalize
   → update AppState → persist snapshot. On 429 → backoff, keep last-good, set
   `.rateLimited(retryAt)`.
3. **UI** observes AppState → popover + dashboard update reactively; reset
   countdowns computed live from `resetsAt`. Menu-bar indicator = max utilization
   across all accounts/windows, color-coded (green <70 / amber <90 / red).

## 8. Error handling

- `401 / invalid token` → attempt refresh; on failure → `.needsReauth` + re-login button.
- `429` → exponential backoff 30→60→120→240→300 s cap; hold last-good; badge
  "rate-limited, retry in …".
- Offline / network error → show cached + `.offline` badge.
- Endpoint shape change → adapter tolerates missing/unknown fields; on parse
  failure keep last-good + surface a warning (don't crash).
- Secrets: token values never logged/printed; log redaction enforced.

## 9. Distribution & self-update

- GitHub Actions on tag: build (xcodebuild) → ZIP the `.app` → attach to GitHub
  Release → `generate_appcast` (EdDSA) → publish `appcast.xml` to GitHub Pages.
- `SUFeedURL` = stable GitHub Pages appcast URL. `SUPublicEDKey` in Info.plist.
- Sparkle in-app "Check for Updates" + periodic auto-check.
- Unsigned: `INSTALL.md` documents one-time `right-click → Open` (or
  `xattr -dr com.apple.quarantine <app>`). Sparkle-delivered updates aren't
  re-quarantined. Note: unsigned build may re-prompt for Keychain access after an
  update (signature changes) — acceptable for personal use.

## 10. Testing (TDD)

- **Unit:** PKCE challenge/verifier; token exchange & refresh (mocked); UsageAPIClient
  JSON parsing with fixtures (null per-model, unknown model key, `extra_usage`,
  malformed); adapter normalization; SyncScheduler backoff + stagger + floor logic;
  reset-countdown math; KeychainStore (mocked); log redaction.
- **Integration:** mock `URLProtocol` returning 200 / 401 / 429 / malformed →
  assert scheduler state transitions (ok / needsReauth / rateLimited).
- **Fixtures:** derived from the confirmed response shape (§4.2).
- Follows repo rule: reproduce bugs with a failing test first.

## 11. Risks / open questions

1. **Undocumented endpoint** — Anthropic may change/remove `/api/oauth/usage`
   without notice. Mitigate: adapter + header fallback (§4.4).
2. **Aggressive 429 rate-limiting** with no `Retry-After`, sticks at 300 s. Naive
   short-interval polling freezes bars. Mitigate: floor 60 s, default 300 s,
   stagger, cache, backoff.
3. **ToS/ban posture genuinely unknown** — no Anthropic statement either way.
   Framed as: monitoring your own accounts, read-only, low frequency, at your own
   risk. Not represented as sanctioned.
4. **Token/refresh domain instability** (`console.anthropic.com` vs
   `platform.claude.com`) — try both, don't hardcode.
5. **Premium-model key naming** (opus/sonnet/fable/…) changes over time — adapter
   surfaces whatever the API returns; label dynamically.
6. **Unsigned Keychain re-prompt after updates** — accepted trade-off for v1.

## 12. Plan 2 carry-forward (from Plan 1 final review)

Design decisions Plan 2 (the SwiftUI app) must make deliberately — surfaced by
the whole-branch review of the Core engine:

1. **Importing Claude Code's token can log the user out of Claude Code.** The
   "import from Claude Code" path reuses CC's OAuth lineage (same public
   client_id). If Anthropic rotates refresh tokens single-use, a refresh
   triggered by this app invalidates the token Claude Code still holds → the
   user's real `claude` CLI session gets logged out. Low risk for the on-demand
   CLI (in-memory, refresh only near expiry); **real risk for the continuously
   polling app.** Plan 2 must choose: (a) give the app its **own** browser OAuth
   grant instead of piggy-backing the imported CC token, or (b) never
   *proactively* refresh an imported token (only reactively on 401), or (c)
   accept + document the trade-off. Recommendation: (a) — import is a
   convenience; treat it as a one-time seed and immediately run the app's own
   OAuth so the two token lineages don't collide.
2. **`TokenResponse.refresh_token` / `expires_in` should be optional.** RFC 6749
   §5.1 permits a refresh response to omit `refresh_token` (keep the old one).
   Currently non-optional → a missing field decodes as `.decoding` → false
   forced re-login. Make them optional in Plan 2 (fall back to existing refresh
   token; default a sane `expires_in`).
3. **HTTP response headers must be read case-insensitively.** `HTTPResponse.headers`
   preserves server casing. When Plan 2 consumes `Retry-After` /
   `anthropic-ratelimit-unified-*` to populate `AccountStatus.rateLimited(retryAt:)`
   (which `SyncScheduler.nextInterval` already honors), it must lowercase keys at
   ingestion or do case-insensitive lookup, or 429 backoff timing silently breaks.
4. **Deferred Minor test-coverage / polish items** (triaged Plan-2 in the final
   review): pin form-encoding edge cases; test OAuth host-order + both-hosts-fail;
   test `.malformed` import path + 403/`.server`/decode branches of UsageAPIClient;
   strengthen `maxUtilization` test so it fails if `weekPremium` is dropped;
   multi-word model-name title-casing in `UsageAdapter.label`; distinct CLI exit
   codes; `Backoff` empty-`steps` guard.
