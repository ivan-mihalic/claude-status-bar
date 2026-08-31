# Notch Panel (Dynamic-Island-style usage rings) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** An optional, always-on-top panel anchored to the MacBook notch (and a synthetic notch
on displays that have none) showing one usage ring per Claude account, expanding on hover into
the full per-window detail — without replacing or changing the existing `MenuBarExtra`.

**Architecture:** All decision logic (geometry, shape, phase, ring model) lives as pure,
`swift test`-able types in `Sources/ClaudeStatusBarApp/Notch/`. A single borderless
`NSPanel` hosts a SwiftUI tree fed by the *existing* `AppEnvironment` / `AppState` — the notch is
a second **view** of the same state, never a second source of truth. A `NotchWindowController`
owns the panel's lifecycle and is driven by one `@AppStorage("showNotchPanel")` toggle.

**Tech Stack:** Swift 6, SwiftUI + AppKit (`NSPanel`, `NSScreen`, `NSHostingView`),
swift-testing, XcodeGen, macOS 14.0 deployment target.

**Spec:** this document, §Design decisions (no separate spec file — the design fits in one page
and duplicating it would let the two drift).

---

## Design decisions

| Decision | Choice | Why |
|---|---|---|
| Coexistence | Notch is **opt-in, alongside** `MenuBarExtra` | Chosen 2026-08-31. Both surfaces render from `AppState`; no second model. |
| Providers | **Claude only, N accounts** | `UsageAPIClient` speaks only the Anthropic OAuth usage endpoint. See §Deferred. |
| Window | one `NSPanel`, always sized to the **expanded** bounding box, transparent outside the shape | Avoids resizing/repositioning a window on every hover (jank, multi-display races). Hit-testing is clipped to the shape so clicks pass through the transparent margin. |
| Hit-testing | `NotchHostingView.hitTest` returns `nil` outside the current shape path | Without it the invisible panel swallows clicks across the whole top of the screen. |
| Displays without a notch | **synthetic** notch pill at top-centre of the main screen | The primary dev machine (Mac Studio + external ASUS MB16AC, verified `system_profiler` 2026-08-31) has **no notch** — the synthetic path is the only one visible during development, so it ships first. |
| Failure states | every ring carries a badge for `offline` / `needsReauth` / `rateLimited` / `never` | Lesson from 0.4.x: a surface that can only render a percentage will confidently show a stale number when the token is dead. |
| Tests | pure logic only; window wiring verified by running the app | AppKit tracking loops hang `swift test` (see Global Constraints). |

### Deferred — NOT in this plan (recorded so it isn't re-litigated)

- **Other providers (OpenAI / ChatGPT, Cursor, …) with N accounts each.** Wanted eventually;
  parked deliberately. Nothing in this plan may hard-code "Claude" into the notch *layout* —
  a ring takes a label, a percent, a colour and a badge, so a future provider drops in without
  reshaping the panel. No `Provider` protocol is introduced now: there is exactly one known
  response shape, and an abstraction built on one example is a guess.
  Blocking unknown, **unverified**: whether a personal ChatGPT/Cursor plan exposes *any*
  endpoint for limit windows. Settle that before planning provider #2.
- Per-ring click-through to a provider dashboard, drag-to-reorder inside the notch,
  media/now-playing widgets, file-drop shelf.

## Global Constraints

- macOS **14.0+** deployment target (`project.yml`); the notch APIs used
  (`NSScreen.safeAreaInsets`, `NSScreen.auxiliaryTopLeftArea`) are macOS 12+. **Unverified from
  documentation in this session** — Task 1 pins them down by measurement before anything is built
  on top.
- **No new entitlement.** The App Sandbox (`App/ClaudeStatusBar.entitlements`) stays exactly as
  it is; a floating panel of one's own app needs no Accessibility or Screen Recording permission.
  If any step seems to need one, stop and report — that is a design error, not a checkbox.
- **Never run `xcodebuild test` or any GUI-hosted test suite automatically.** The runner
  activates the app and steals focus while the machine's owner is working. `swift test` (pure
  SPM, no host app) and `xcodebuild build` are fine.
- **Never bring the app to the foreground.** Launch with `open -g -a <path>.app`; never
  `osascript … activate`, never `open` without `-g`.
- Identifiers, filenames and code in **English**; comments and docs in the repo's existing
  English style (this repo is English throughout — do not introduce Czech here).
- Conventional commits (commitlint). Commit **by pathspec after `-m`**:
  `git commit -m "…" -- <paths>`. Never `-a`, `-A`, or `.`. New files need `git add <path>`
  first, otherwise the pathspec commit fails with *"did not match any file(s) known to git"*.
- CI is disabled in this repo's world; verification is local and must actually be run.
- Test commands: `export PATH="$HOME/.swiftly/bin:$PATH"; swift test`
  Build: `xcodegen generate && xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar -configuration Debug build`

## File Structure

- **Create:**
  - `Sources/ClaudeStatusBarApp/Notch/NotchGeometry.swift` — screen metrics → notch rects (pure)
  - `Sources/ClaudeStatusBarApp/Notch/NotchShape.swift` — the inverse-cornered path (pure)
  - `Sources/ClaudeStatusBarApp/Notch/NotchModel.swift` — `Account` → ring view models (pure)
  - `Sources/ClaudeStatusBarApp/Notch/NotchPanel.swift` — `NSPanel` + `NotchHostingView`
  - `Sources/ClaudeStatusBarApp/Notch/NotchWindowController.swift` — lifecycle, screen changes
  - `Sources/ClaudeStatusBarApp/Notch/NotchRootView.swift` — collapsed/expanded SwiftUI content
  - `Sources/ClaudeStatusBarApp/Notch/UsageRingView.swift` — one ring
  - `Tests/ClaudeStatusBarAppTests/NotchGeometryTests.swift`
  - `Tests/ClaudeStatusBarAppTests/NotchShapeTests.swift`
  - `Tests/ClaudeStatusBarAppTests/NotchModelTests.swift`
- **Modify:**
  - `Sources/ClaudeStatusBarApp/Views/SettingsView.swift` — the opt-in toggle
  - `App/ClaudeStatusBarMain.swift` — own the controller, react to the toggle
  - `README.md` — one paragraph on the notch panel

---

## Task 1: Notch geometry (pure)

**Files:**
- Create: `Sources/ClaudeStatusBarApp/Notch/NotchGeometry.swift`
- Test: `Tests/ClaudeStatusBarAppTests/NotchGeometryTests.swift`

**Interfaces:**
- Produces: `ScreenMetrics(frame:topInset:auxiliaryTopLeftWidth:)`, `NotchKind`,
  `NotchLayout(kind:collapsed:)`, `NotchLayout.panelFrame(expandedSize:)`,
  `NotchGeometry.layout(for:)`, `NotchGeometry.metrics(of: NSScreen)`.
  All rects are in **screen coordinates with a bottom-left origin** (AppKit's convention),
  because they are handed straight to `NSWindow.setFrame(_:display:)`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/ClaudeStatusBarAppTests/NotchGeometryTests.swift
import Testing
import CoreGraphics
@testable import ClaudeStatusBarApp

// Illustrative numbers, not a claim about any specific Mac: a 1710×1107 point screen
// whose menu-bar area is 38pt tall and whose usable top-left region is 727pt wide,
// leaving 1710 − 2×727 = 256pt of notch.
private let notched = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1710, height: 1107),
                                    topInset: 38, auxiliaryTopLeftWidth: 727)
private let plain = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                  topInset: 0, auxiliaryTopLeftWidth: nil)

@Test func hardwareNotch_isDerivedFromTheAuxiliaryArea() {
    let layout = NotchGeometry.layout(for: notched)
    #expect(layout.kind == .hardware)
    #expect(layout.collapsed.width == 256)
    #expect(layout.collapsed.height == 38)
    // Horizontally centred, and flush with the top edge (bottom-left origin!).
    #expect(layout.collapsed.midX == 855)
    #expect(layout.collapsed.maxY == 1107)
}

@Test func screenWithoutNotch_getsASyntheticPill() {
    let layout = NotchGeometry.layout(for: plain)
    #expect(layout.kind == .synthetic)
    #expect(layout.collapsed.size == NotchGeometry.syntheticCollapsedSize)
    #expect(layout.collapsed.midX == 960)
    #expect(layout.collapsed.maxY == 1080)
}

@Test func missingAuxiliaryWidth_fallsBackToSynthetic() {
    // A top inset with no auxiliary area is a shape we cannot measure; guessing a
    // width here would silently mis-place the panel, so treat it as no notch.
    let odd = ScreenMetrics(frame: plain.frame, topInset: 38, auxiliaryTopLeftWidth: nil)
    #expect(NotchGeometry.layout(for: odd).kind == .synthetic)
}

@Test func panelFrame_isCentredOnTheNotchAndClampedToTheScreen() {
    let layout = NotchGeometry.layout(for: notched)
    let frame = layout.panelFrame(expandedSize: CGSize(width: 400, height: 300))
    #expect(frame.midX == layout.collapsed.midX)
    #expect(frame.maxY == 1107)
    #expect(frame.width == 400)

    // Wider than the screen → clamped, never hanging off the edge.
    let huge = layout.panelFrame(expandedSize: CGSize(width: 5000, height: 300))
    #expect(huge.width == 1710)
    #expect(huge.minX == 0)
}

@Test func panelFrame_neverSmallerThanTheCollapsedNotch() {
    let layout = NotchGeometry.layout(for: notched)
    let frame = layout.panelFrame(expandedSize: CGSize(width: 10, height: 10))
    #expect(frame.width >= layout.collapsed.width)
    #expect(frame.height >= layout.collapsed.height)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `export PATH="$HOME/.swiftly/bin:$PATH"; swift test --filter NotchGeometry`
Expected: FAIL — `cannot find 'ScreenMetrics' in scope`.

- [ ] **Step 3: Implement the geometry**

```swift
// Sources/ClaudeStatusBarApp/Notch/NotchGeometry.swift
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

/// Everything the layout needs to know about a screen, lifted out of `NSScreen` so the
/// math is testable without a display attached (the dev machine has no notch).
public struct ScreenMetrics: Equatable, Sendable {
    /// `NSScreen.frame` — bottom-left origin, in points.
    public let frame: CGRect
    /// `NSScreen.safeAreaInsets.top`. 0 on a screen with no notch.
    public let topInset: CGFloat
    /// Width of `NSScreen.auxiliaryTopLeftArea` — the usable strip left of the notch.
    /// `nil` when the screen reports no such area.
    public let auxiliaryTopLeftWidth: CGFloat?

    public init(frame: CGRect, topInset: CGFloat, auxiliaryTopLeftWidth: CGFloat?) {
        self.frame = frame; self.topInset = topInset
        self.auxiliaryTopLeftWidth = auxiliaryTopLeftWidth
    }
}

public enum NotchKind: Equatable, Sendable {
    /// A real hardware notch; the collapsed panel hides inside it.
    case hardware
    /// No notch on this screen — we draw a pill over the top of the menu bar instead.
    case synthetic
}

public struct NotchLayout: Equatable, Sendable {
    public let kind: NotchKind
    /// Resting rect, screen coordinates, bottom-left origin, flush with the screen top.
    public let collapsed: CGRect
    public let screen: CGRect

    public init(kind: NotchKind, collapsed: CGRect, screen: CGRect) {
        self.kind = kind; self.collapsed = collapsed; self.screen = screen
    }

    /// The window frame. The panel is *always* this size — expansion happens inside it,
    /// so no window ever moves or resizes while the pointer is over it.
    public func panelFrame(expandedSize: CGSize) -> CGRect {
        let width = min(max(expandedSize.width, collapsed.width), screen.width)
        let height = min(max(expandedSize.height, collapsed.height), screen.height)
        var x = collapsed.midX - width / 2
        x = min(max(x, screen.minX), screen.maxX - width)
        return CGRect(x: x, y: screen.maxY - height, width: width, height: height)
    }
}

public enum NotchGeometry {
    /// Size of the fake notch drawn on screens that have none.
    public static let syntheticCollapsedSize = CGSize(width: 180, height: 32)

    public static func layout(for m: ScreenMetrics) -> NotchLayout {
        if m.topInset > 0, let aux = m.auxiliaryTopLeftWidth, aux > 0 {
            let width = m.frame.width - 2 * aux
            if width > 0 {
                let rect = CGRect(x: m.frame.midX - width / 2,
                                  y: m.frame.maxY - m.topInset,
                                  width: width, height: m.topInset)
                return NotchLayout(kind: .hardware, collapsed: rect, screen: m.frame)
            }
        }
        let size = syntheticCollapsedSize
        let rect = CGRect(x: m.frame.midX - size.width / 2,
                          y: m.frame.maxY - size.height,
                          width: size.width, height: size.height)
        return NotchLayout(kind: .synthetic, collapsed: rect, screen: m.frame)
    }

    #if canImport(AppKit)
    @MainActor
    public static func metrics(of screen: NSScreen) -> ScreenMetrics {
        ScreenMetrics(frame: screen.frame,
                      topInset: screen.safeAreaInsets.top,
                      auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width)
    }
    #endif
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `export PATH="$HOME/.swiftly/bin:$PATH"; swift test --filter NotchGeometry`
Expected: PASS, 5 tests.

- [ ] **Step 5: Verify the two `NSScreen` properties actually exist and report what we assume**

The API names above are **unverified from documentation**. Confirm them against the SDK before
building anything on top:

```bash
xcrun --sdk macosx --show-sdk-path
grep -n "auxiliaryTopLeftArea\|auxiliaryTopRightArea\|safeAreaInsets" \
  "$(xcrun --sdk macosx --show-sdk-path)/System/Library/Frameworks/AppKit.framework/Headers/NSScreen.h"
```
Expected: both symbols present with their availability annotation. If `auxiliaryTopLeftArea` is
absent or gated above macOS 14, **stop and report** — the fallback is
`safeAreaInsets.top` plus a fixed notch width, which changes Task 1's contract.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeStatusBarApp/Notch/NotchGeometry.swift \
        Tests/ClaudeStatusBarAppTests/NotchGeometryTests.swift
git commit -m "feat(notch): derive notch geometry from screen metrics" \
  -- Sources/ClaudeStatusBarApp/Notch/NotchGeometry.swift \
     Tests/ClaudeStatusBarAppTests/NotchGeometryTests.swift
```

---

## Task 2: The notch shape (pure)

**Files:**
- Create: `Sources/ClaudeStatusBarApp/Notch/NotchShape.swift`
- Test: `Tests/ClaudeStatusBarAppTests/NotchShapeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `NotchShape(topRadius:bottomRadius:)` conforming to `SwiftUI.Shape`, and
  `NotchShape.cgPath(in: CGRect) -> CGPath` — the same path as a `CGPath`, used by Task 4's
  hit-testing so the panel's clickable region and its drawn region can never disagree.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/ClaudeStatusBarAppTests/NotchShapeTests.swift
import Testing
import CoreGraphics
@testable import ClaudeStatusBarApp

private let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
private let shape = NotchShape(topRadius: 8, bottomRadius: 20)

@Test func path_staysInsideItsRect() {
    #expect(shape.cgPath(in: rect).boundingBox.width <= rect.width)
    #expect(shape.cgPath(in: rect).boundingBox.height <= rect.height)
}

@Test func centre_isInsideAndBottomCornersAreRoundedAway() {
    let path = shape.cgPath(in: rect)
    #expect(path.contains(CGPoint(x: 100, y: 50)))
    // Bottom corners are rounded, so the exact corner point is outside the fill.
    #expect(!path.contains(CGPoint(x: 0.5, y: 0.5)))
    #expect(!path.contains(CGPoint(x: 199.5, y: 0.5)))
}

@Test func topEdge_isFlush() {
    // The panel hangs off the top of the screen: the top edge must be square and full width,
    // otherwise a hardware notch shows a sliver of wallpaper beside it.
    let path = shape.cgPath(in: rect)
    #expect(path.contains(CGPoint(x: 1, y: rect.maxY - 1)))
    #expect(path.contains(CGPoint(x: rect.maxX - 1, y: rect.maxY - 1)))
}

@Test func zeroRadii_giveAPlainRectangle() {
    let square = NotchShape(topRadius: 0, bottomRadius: 0).cgPath(in: rect)
    #expect(square.contains(CGPoint(x: 0.5, y: 0.5)))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `export PATH="$HOME/.swiftly/bin:$PATH"; swift test --filter NotchShape`
Expected: FAIL — `cannot find 'NotchShape' in scope`.

- [ ] **Step 3: Implement the shape**

```swift
// Sources/ClaudeStatusBarApp/Notch/NotchShape.swift
import SwiftUI
import CoreGraphics

/// The panel silhouette: square, full-width top edge (it is flush with the screen edge),
/// rounded bottom corners, and a small inverse curve at the top where the black body meets
/// the screen edge — the detail that makes it read as an extension of the notch instead of
/// a floating rectangle.
public struct NotchShape: Shape, Equatable, Sendable {
    public let topRadius: CGFloat
    public let bottomRadius: CGFloat

    public init(topRadius: CGFloat = 8, bottomRadius: CGFloat = 20) {
        self.topRadius = topRadius; self.bottomRadius = bottomRadius
    }

    /// Note the coordinate space: `CGPath` here is built bottom-left-origin (CoreGraphics),
    /// matching `NotchGeometry`'s rects, so hit-testing and drawing agree.
    public func cgPath(in rect: CGRect) -> CGPath {
        let b = min(bottomRadius, min(rect.width, rect.height) / 2)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + b))
        if b > 0 {
            p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.maxX - b, y: rect.minY), radius: b)
        }
        p.addLine(to: CGPoint(x: rect.minX + b, y: rect.minY))
        if b > 0 {
            p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.minX, y: rect.minY + b), radius: b)
        }
        p.closeSubpath()
        return p
    }

    public func path(in rect: CGRect) -> Path {
        // SwiftUI's y axis points down; flip so the shape reads the same either way.
        var flip = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -rect.height)
        let cg = cgPath(in: CGRect(origin: .zero, size: rect.size))
        return Path(cg.copy(using: &flip) ?? cg).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// The inverse corner drawn *outside* the panel, filling the wedge between the panel's
/// straight side and the screen edge. Two of these, mirrored, sit under the panel's bottom
/// corners; keeping them separate means the panel body stays a simple, hit-testable shape.
public struct InverseCorner: Shape {
    public let radius: CGFloat
    public let flipped: Bool
    public init(radius: CGFloat = 12, flipped: Bool = false) {
        self.radius = radius; self.flipped = flipped
    }
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, min(rect.width, rect.height))
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return flipped ? path.applying(CGAffineTransform(scaleX: -1, y: 1)
            .translatedBy(x: -rect.width, y: 0)) : path
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `export PATH="$HOME/.swiftly/bin:$PATH"; swift test --filter NotchShape`
Expected: PASS, 4 tests.

- [ ] **Step 5: Prove the tests can fail (ablation)**

A geometry test that cannot fail is decoration. Temporarily change `cgPath` to return
`CGPath(rect: rect, transform: nil)` and re-run:
Expected: `centre_isInsideAndBottomCornersAreRoundedAway` FAILS (a plain rect contains its
corners). Revert the change and re-run: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeStatusBarApp/Notch/NotchShape.swift \
        Tests/ClaudeStatusBarAppTests/NotchShapeTests.swift
git commit -m "feat(notch): add the panel silhouette and its CGPath twin" \
  -- Sources/ClaudeStatusBarApp/Notch/NotchShape.swift \
     Tests/ClaudeStatusBarAppTests/NotchShapeTests.swift
```

---

## Task 3: Ring view model — including every failure state (pure)

**Files:**
- Create: `Sources/ClaudeStatusBarApp/Notch/NotchModel.swift`
- Test: `Tests/ClaudeStatusBarAppTests/NotchModelTests.swift`

**Interfaces:**
- Consumes: `Account`, `AccountStatus`, `UsageSnapshot` (`ClaudeStatusBarCore`),
  `IndicatorLevel` + `MenuBarIndicator.level(maxUtilization:)` (existing).
- Produces: `RingBadge`, `RingModel(id:label:percent:level:badge:)`,
  `NotchModel.rings(accounts:) -> [RingModel]`,
  `NotchModel.ring(for: Account) -> RingModel`.

The percentage shown on a ring is the account's **worst** window — the same rule the menu-bar
indicator already uses, so the two surfaces can never disagree about how bad things are.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/ClaudeStatusBarAppTests/NotchModelTests.swift
import Testing
import Foundation
@testable import ClaudeStatusBarApp
@testable import ClaudeStatusBarCore

private func window(_ u: Double) -> UsageWindow {
    UsageWindow(key: "five_hour", label: "Current session", utilization: u,
                resetsAt: Date(timeIntervalSince1970: 1_800_000_000))
}
private func account(status: AccountStatus, snapshot: UsageSnapshot?) -> Account {
    Account(id: UUID(), label: "work", accountUuid: nil, syncInterval: 300,
            status: status, lastSnapshot: snapshot, lastSyncedAt: nil)
}
private let snapshot = UsageSnapshot(session: window(41), weekAll: window(60),
                                     weekPremium: [], fetchedAt: Date(timeIntervalSince1970: 1_799_000_000))

@Test func ring_showsTheWorstWindow() {
    let r = NotchModel.ring(for: account(status: .ok, snapshot: snapshot))
    #expect(r.percent == 60)
    #expect(r.level == .ok)
    #expect(r.badge == nil)
    #expect(r.label == "work")
}

@Test func ring_hasNoPercentWithoutASnapshot() {
    let r = NotchModel.ring(for: account(status: .never, snapshot: nil))
    #expect(r.percent == nil)
    #expect(r.level == .unknown)
    #expect(r.badge == .syncing)
}

// The point of this test: a surface that can only render a number will happily show a
// stale 60% while the token is dead. Every non-ok status must reach the ring.
@Test func everyFailureStatus_reachesTheRing() {
    #expect(NotchModel.ring(for: account(status: .offline, snapshot: snapshot)).badge == .offline)
    #expect(NotchModel.ring(for: account(status: .needsReauth, snapshot: snapshot)).badge == .signIn)
    #expect(NotchModel.ring(for: account(status: .rateLimited(retryAt: Date()),
                                         snapshot: snapshot)).badge == .rateLimited)
    #expect(NotchModel.ring(for: account(status: .never, snapshot: snapshot)).badge == .syncing)
    #expect(NotchModel.ring(for: account(status: .ok, snapshot: snapshot)).badge == nil)
}

@Test func failingAccount_keepsItsLastKnownPercent() {
    // Showing the last number is fine — showing it *without* the badge is not.
    let r = NotchModel.ring(for: account(status: .offline, snapshot: snapshot))
    #expect(r.percent == 60)
    #expect(r.badge == .offline)
}

@Test func rings_preserveAccountOrder() {
    let a = account(status: .ok, snapshot: snapshot)
    let b = account(status: .ok, snapshot: snapshot)
    #expect(NotchModel.rings(accounts: [a, b]).map(\.id) == [a.id, b.id])
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `export PATH="$HOME/.swiftly/bin:$PATH"; swift test --filter NotchModel`
Expected: FAIL — `cannot find 'NotchModel' in scope`.

The initialisers above were read from
`Sources/ClaudeStatusBarCore/Usage/UsageSnapshot.swift:9` and `:20` on 2026-08-31. If they have
moved on, match the real ones — `Tests/ClaudeStatusBarAppTests/Fixtures` holds only
`usage_full.json` (a decoding fixture), so there is no existing builder to reuse.

- [ ] **Step 3: Implement the model**

```swift
// Sources/ClaudeStatusBarApp/Notch/NotchModel.swift
import Foundation
import ClaudeStatusBarCore

/// Why a ring cannot be taken at face value. `nil` means the number is current.
public enum RingBadge: Equatable, Sendable { case offline, signIn, rateLimited, syncing }

public struct RingModel: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let label: String
    /// Worst window utilization, 0...100. `nil` = never synced successfully.
    public let percent: Double?
    public let level: IndicatorLevel
    public let badge: RingBadge?

    public init(id: UUID, label: String, percent: Double?,
                level: IndicatorLevel, badge: RingBadge?) {
        self.id = id; self.label = label; self.percent = percent
        self.level = level; self.badge = badge
    }
}

public enum NotchModel {
    public static func rings(accounts: [Account]) -> [RingModel] { accounts.map(ring(for:)) }

    public static func ring(for account: Account) -> RingModel {
        let worst = account.lastSnapshot.map { $0.allWindows.map(\.utilization).max() ?? 0 }
        return RingModel(id: account.id,
                         label: account.menuBarPrefix ?? account.label,
                         percent: worst,
                         level: MenuBarIndicator.level(maxUtilization: worst),
                         badge: badge(for: account.status))
    }

    private static func badge(for status: AccountStatus) -> RingBadge? {
        switch status {
        case .ok:           return nil
        case .offline:      return .offline
        case .needsReauth:  return .signIn
        case .rateLimited:  return .rateLimited
        case .never:        return .syncing
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `export PATH="$HOME/.swiftly/bin:$PATH"; swift test --filter NotchModel`
Expected: PASS, 5 tests.

- [ ] **Step 5: Prove the badge test can fail (ablation)**

Temporarily make `badge(for:)` return `nil` for every case and re-run:
Expected: `everyFailureStatus_reachesTheRing` and `failingAccount_keepsItsLastKnownPercent`
FAIL. Revert; re-run: PASS. A `switch` over `AccountStatus` is exhaustive, so a *new* status
added later breaks the build here — that is deliberate.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeStatusBarApp/Notch/NotchModel.swift \
        Tests/ClaudeStatusBarAppTests/NotchModelTests.swift
git commit -m "feat(notch): map accounts to rings that carry their failure state" \
  -- Sources/ClaudeStatusBarApp/Notch/NotchModel.swift \
     Tests/ClaudeStatusBarAppTests/NotchModelTests.swift
```

---

## Task 4: The panel window — a black shape that appears and steals nothing

**Files:**
- Create: `Sources/ClaudeStatusBarApp/Notch/NotchPanel.swift`
- Create: `Sources/ClaudeStatusBarApp/Notch/NotchWindowController.swift`
- Create: `Sources/ClaudeStatusBarApp/Notch/NotchRootView.swift` (placeholder body — the
  real content arrives in Task 5)

**Interfaces:**
- Consumes: `NotchGeometry.metrics(of:)`, `NotchLayout.panelFrame(expandedSize:)`,
  `NotchShape.cgPath(in:)`.
- Produces: `NotchWindowController(env:router:)`, `.setEnabled(_ on: Bool)`,
  `.refreshForScreens()`; `NotchPanel`; `NotchHostingView`.
- `NotchRootView(env:router:layout:expanded:onHoverChange:)` — Task 5 fills in the body and
  keeps this signature.

This task has **no unit test**: it is window-server behaviour. Its gate is Step 4's checklist,
run by a human. Do not fake it with a test that only proves the object was constructed.

- [ ] **Step 1: Write the panel**

```swift
// Sources/ClaudeStatusBarApp/Notch/NotchPanel.swift
import AppKit
import SwiftUI

/// Hosting view whose hit-testing is clipped to the drawn shape. Without this the panel's
/// transparent margin swallows every click across the top of the screen — and the symptom
/// (menu-bar items that "stop working") points nowhere near this file.
public final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// Current opaque region, in this view's coordinates. Set by the controller whenever
    /// the panel expands or collapses.
    public var interactivePath: CGPath?

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let path = interactivePath else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        guard path.contains(CGPoint(x: local.x, y: bounds.height - local.y)) else { return nil }
        return super.hitTest(point)
    }
}

/// Borderless, non-activating panel pinned above the menu bar.
public final class NotchPanel: NSPanel {
    public init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar                 // above the menu bar, below system alerts
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        // Present on every Space and over full-screen apps, without pulling the app forward.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary,
                              .ignoresCycle]
    }

    // A borderless panel is not key by default; without this the SwiftUI content can never
    // take a click. `.nonactivatingPanel` keeps the app itself in the background.
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 2: Write the controller and a placeholder root view**

```swift
// Sources/ClaudeStatusBarApp/Notch/NotchRootView.swift
import SwiftUI

public struct NotchRootView: View {
    @Bindable var env: AppEnvironment
    let router: AppRouter
    let layout: NotchLayout
    let expanded: Bool
    let onHoverChange: (Bool) -> Void
    @Environment(\.openWindow) private var openWindow

    public init(env: AppEnvironment, router: AppRouter, layout: NotchLayout,
                expanded: Bool, onHoverChange: @escaping (Bool) -> Void) {
        self.env = env; self.router = router; self.layout = layout
        self.expanded = expanded; self.onHoverChange = onHoverChange
    }

    /// Task 5 replaces this body with the rings. For now: the silhouette only, so the
    /// window plumbing can be judged on its own.
    public var body: some View {
        VStack(spacing: 0) {
            NotchShape()
                .fill(.black)
                .frame(width: expanded ? 220 : layout.collapsed.width,
                       height: expanded ? 260 : layout.collapsed.height)
                .onHover { onHoverChange($0) }
                .animation(.spring(response: 0.32, dampingFraction: 0.78), value: expanded)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
```

```swift
// Sources/ClaudeStatusBarApp/Notch/NotchWindowController.swift
import AppKit
import SwiftUI
import Observation

/// Owns the notch panel: creates it when enabled, tears it down when not, and rebuilds it
/// when the display configuration changes (unplugging a monitor, resolution change, waking).
@MainActor
@Observable
public final class NotchWindowController {
    /// Bounding box the panel always occupies; expansion happens inside it.
    public static let expandedSize = CGSize(width: 260, height: 320)

    private let env: AppEnvironment
    private let router: AppRouter
    private var panel: NotchPanel?
    private var screenObserver: (any NSObjectProtocol)?
    private var expanded = false
    private var enabled = false

    public init(env: AppEnvironment, router: AppRouter) {
        self.env = env; self.router = router
    }

    public func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        on ? build() : teardown()
    }

    /// Rebuild against the current screens. Cheap and idempotent — call it freely.
    public func refreshForScreens() { if enabled { teardown(); build() } }

    private func build() {
        guard let screen = NSScreen.main else { return }
        let layout = NotchGeometry.layout(for: NotchGeometry.metrics(of: screen))
        let frame = layout.panelFrame(expandedSize: Self.expandedSize)

        let panel = NotchPanel(frame: frame)
        let host = NotchHostingView(rootView: NotchRootView(
            env: env, router: router, layout: layout, expanded: false,
            onHoverChange: { [weak self] in self?.setExpanded($0) }))
        host.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = host
        updateInteractivePath(host: host, layout: layout, size: frame.size)
        panel.orderFrontRegardless()      // show without activating the app
        self.panel = panel

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshForScreens() }
            }
    }

    private func teardown() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel?.orderOut(nil)
        panel = nil
        expanded = false
    }

    private func setExpanded(_ on: Bool) {
        guard on != expanded, let panel,
              let host = panel.contentView as? NotchHostingView<NotchRootView>,
              let screen = panel.screen ?? NSScreen.main else { return }
        expanded = on
        let layout = NotchGeometry.layout(for: NotchGeometry.metrics(of: screen))
        host.rootView = NotchRootView(env: env, router: router, layout: layout, expanded: on,
                                      onHoverChange: { [weak self] in self?.setExpanded($0) })
        updateInteractivePath(host: host, layout: layout, size: panel.frame.size)
    }

    /// Keep the clickable region equal to the drawn region — one source of truth (`NotchShape`).
    private func updateInteractivePath(host: NotchHostingView<NotchRootView>,
                                       layout: NotchLayout, size: CGSize) {
        let width = expanded ? 220.0 : layout.collapsed.width
        let height = expanded ? 260.0 : layout.collapsed.height
        let rect = CGRect(x: (size.width - width) / 2, y: size.height - height,
                          width: width, height: height)
        host.interactivePath = NotchShape().cgPath(in: rect)
    }
}
```

- [ ] **Step 3: Wire it into the app behind a hard-coded `true`, then build**

In `App/ClaudeStatusBarMain.swift`, add to the `App` struct:

```swift
@State private var notch: NotchWindowController?
```

and inside the `MenuBarExtra` label closure's enclosing scene, attach a task that creates it:

```swift
.task {
    if notch == nil {
        let controller = NotchWindowController(env: env, router: router)
        controller.setEnabled(true)      // Task 6 replaces this with the setting
        notch = controller
    }
}
```

Run:
```bash
xcodegen generate
xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar -configuration Debug build
```
Expected: BUILD SUCCEEDED. (`xcodebuild` prints hundreds of lines; check the final status line,
not a `grep` — a piped `grep` reports its own exit code, not the build's.)

- [ ] **Step 4: Human verification checklist — the real gate for this task**

Launch **without** stealing focus:
```bash
open -g -a "$(ls -d ~/Library/Developer/Xcode/DerivedData/ClaudeStatusBar-*/Build/Products/Debug/ClaudeStatusBar.app | head -1)"
```
Confirm, on the Mac Studio (synthetic notch — this machine has no hardware notch):

- [ ] a small black pill sits at the top centre of the main display
- [ ] hovering it grows it into a rounded panel; leaving collapses it back
- [ ] clicking it does **not** bring the app forward or change the active app
- [ ] menu-bar items either side of the pill still open normally (proves hit-test clipping)
- [ ] clicking the desktop/another window still works everywhere the panel is transparent
- [ ] the menu-bar extra still works exactly as before

Quit with the app's own Quit item.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatusBarApp/Notch/NotchPanel.swift \
        Sources/ClaudeStatusBarApp/Notch/NotchWindowController.swift \
        Sources/ClaudeStatusBarApp/Notch/NotchRootView.swift
git commit -m "feat(notch): float a hit-test-clipped panel at the top of the screen" \
  -- Sources/ClaudeStatusBarApp/Notch/NotchPanel.swift \
     Sources/ClaudeStatusBarApp/Notch/NotchWindowController.swift \
     Sources/ClaudeStatusBarApp/Notch/NotchRootView.swift \
     App/ClaudeStatusBarMain.swift
```

---

## Task 5: Rings, detail and the gear

**Files:**
- Create: `Sources/ClaudeStatusBarApp/Notch/UsageRingView.swift`
- Modify: `Sources/ClaudeStatusBarApp/Notch/NotchRootView.swift` (replace the placeholder body)

**Interfaces:**
- Consumes: `RingModel`, `RingBadge`, `NotchModel.rings(accounts:)`, `IndicatorLevel`,
  `Format.percent(_:)`, `AppRouter.show(_:)`, `DockController.shared.prepareToShowWindow()`.
- Produces: `UsageRingView(model:diameter:)`.

- [ ] **Step 1: Write the ring view**

```swift
// Sources/ClaudeStatusBarApp/Notch/UsageRingView.swift
import SwiftUI

public struct UsageRingView: View {
    let model: RingModel
    let diameter: CGFloat

    public init(model: RingModel, diameter: CGFloat = 46) {
        self.model = model; self.diameter = diameter
    }

    private var tint: Color {
        switch model.level {
        case .ok:       return .green
        case .warn:     return .yellow
        case .critical: return .red
        case .unknown:  return .secondary
        }
    }

    private var badgeSymbol: String? {
        switch model.badge {
        case .none:        return nil
        case .offline:     return "wifi.slash"
        case .signIn:      return "person.badge.key"
        case .rateLimited: return "clock.badge.exclamationmark"
        case .syncing:     return "arrow.triangle.2.circlepath"
        }
    }

    public var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: (model.percent ?? 0) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if let badgeSymbol {
                    // A badge replaces the glyph rather than sitting next to it: the number
                    // behind it may be stale and must not look authoritative.
                    Image(systemName: badgeSymbol).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                } else {
                    Image(systemName: "gauge.medium").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: diameter, height: diameter)
            Text(model.percent.map(Format.percent) ?? "—")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .help(model.label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.label))
        .accessibilityValue(Text(model.percent.map(Format.percent) ?? "no data"))
    }
}
```

- [ ] **Step 2: Replace the root view body**

```swift
// Sources/ClaudeStatusBarApp/Notch/NotchRootView.swift  (body only; init unchanged)
public var body: some View {
    let rings = NotchModel.rings(accounts: env.appState.accounts)
    let width = expanded ? 220.0 : layout.collapsed.width
    let height = expanded ? contentHeight(ringCount: rings.count) : layout.collapsed.height

    VStack(spacing: 0) {
        ZStack(alignment: .top) {
            NotchShape().fill(.black)
            if expanded {
                VStack(spacing: 14) {
                    if rings.isEmpty {
                        Text("No accounts").font(.caption).foregroundStyle(.white.opacity(0.7))
                    } else {
                        ForEach(rings) { UsageRingView(model: $0) }
                    }
                    Button {
                        router.show(.dashboard)
                        DockController.shared.prepareToShowWindow()
                        openWindow(id: "main")
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help("Open Dashboard")
                }
                .padding(.top, layout.collapsed.height + 10)
                .padding(.bottom, 14)
                .transition(.opacity)
            }
        }
        .frame(width: width, height: height)
        .onHover { onHoverChange($0) }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: expanded)
        Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
}

/// Height grows with the number of accounts; the controller uses the same number for the
/// hit-test path, so both are derived here rather than guessed twice.
public func contentHeight(ringCount: Int) -> CGFloat {
    layout.collapsed.height + 10 + CGFloat(max(ringCount, 1)) * 72 + 34 + 14
}
```

`router` and `openWindow` are already declared on the view from Task 4 — nothing to add.

Then update `NotchWindowController` so the panel's height and hit-test path use the same
number: replace the hard-coded `260.0` in `setExpanded`/`updateInteractivePath` with
`NotchRootView(...).contentHeight(ringCount: env.appState.accounts.count)`, and raise
`expandedSize` to `CGSize(width: 260, height: 520)` so up to five accounts fit inside the
fixed window.

- [ ] **Step 3: Make the panel follow state changes**

`NSHostingView` holds a value-type root view, so it does **not** re-render when `AppState`
changes unless the environment object graph reaches it. Pass the observable through instead of
rebuilding by hand — in `build()`, construct the hosting view with the environment injected:

```swift
let host = NotchHostingView(rootView: NotchRootView(
    env: env, router: router, layout: layout, expanded: false,
    onHoverChange: { [weak self] in self?.setExpanded($0) }))
```

`AppEnvironment` and `AppState` are `@Observable`, so SwiftUI tracks
`env.appState.accounts` through the stored reference and re-renders on sync.

- [ ] **Step 4: Build**

Run:
```bash
xcodegen generate
xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar -configuration Debug build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Human verification checklist**

With at least one account signed in, launch via `open -g -a …` and confirm:

- [ ] hovering shows one ring per account, in the same order as the Dashboard
- [ ] each ring's percentage equals the worst window of that account in the menu-bar popover
- [ ] the gear opens the Dashboard window
- [ ] an account in a failure state shows its badge instead of the gauge glyph. To force one
      without waiting: turn Wi-Fi off, wait for the next sync tick, and check the ring shows
      `wifi.slash`. Turn it back on and confirm the badge clears.
- [ ] adding or removing an account in the Dashboard updates the rings without restarting

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeStatusBarApp/Notch/UsageRingView.swift
git commit -m "feat(notch): render one usage ring per account with its status badge" \
  -- Sources/ClaudeStatusBarApp/Notch/UsageRingView.swift \
     Sources/ClaudeStatusBarApp/Notch/NotchRootView.swift \
     Sources/ClaudeStatusBarApp/Notch/NotchWindowController.swift
```

---

## Task 6: The setting — opt-in, off by default, no restart

**Files:**
- Modify: `Sources/ClaudeStatusBarApp/Views/SettingsView.swift`
- Modify: `App/ClaudeStatusBarMain.swift`

**Interfaces:**
- Consumes: `NotchWindowController.setEnabled(_:)`.
- Produces: `@AppStorage("showNotchPanel")`, default `false`.

- [ ] **Step 1: Add the toggle**

In `SettingsView`, next to the existing toggles:

```swift
@AppStorage("showNotchPanel") private var showNotchPanel = false
```
```swift
Toggle("Show usage rings in the notch", isOn: $showNotchPanel)
Text("Adds a panel at the top of the screen. On Macs without a notch it appears as a pill "
     + "over the middle of the menu bar. The menu-bar icon stays either way.")
    .font(.caption).foregroundStyle(.secondary)
```

- [ ] **Step 2: Drive the controller from it**

In `App/ClaudeStatusBarMain.swift`, replace Task 4's hard-coded `setEnabled(true)`:

```swift
@AppStorage("showNotchPanel") private var showNotchPanel = false
```
```swift
.task {
    if notch == nil { notch = NotchWindowController(env: env, router: router) }
    notch?.setEnabled(showNotchPanel)
}
.onChange(of: showNotchPanel) { _, on in notch?.setEnabled(on) }
```

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Human verification checklist**

- [ ] fresh launch (toggle off): **no** panel anywhere; the app behaves exactly as 0.4.2 did
- [ ] toggling on shows the panel immediately, with no restart
- [ ] toggling off removes it immediately and leaves no invisible click-blocking region
      (click around the top centre of the screen to confirm)
- [ ] the choice survives a quit/relaunch

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(settings): make the notch panel opt-in" \
  -- Sources/ClaudeStatusBarApp/Views/SettingsView.swift App/ClaudeStatusBarMain.swift
```

---

## Task 7: Hardware notch, multi-display and full-screen — measured, not assumed

**Files:** none expected. Any fix lands in `NotchGeometry.swift` or `NotchWindowController.swift`
with a test added to `NotchGeometryTests.swift` for the geometry half.

This task exists because everything before it was verified on a Mac with **no notch**. It is run
on the MacBook Air (the test machine), from a build copied over — not by developing there.

- [ ] **Step 1: Get the build onto the MacBook**

```bash
scp -r "$(ls -d ~/Library/Developer/Xcode/DerivedData/ClaudeStatusBar-*/Build/Products/Debug/ClaudeStatusBar.app | head -1)" \
    macbook.tailc235d9.ts.net:/tmp/
ssh macbook.tailc235d9.ts.net 'open -g -a /tmp/ClaudeStatusBar.app'
```
(`ssh host cmd` runs without a login shell, so `PATH` lacks `/opt/homebrew/bin` — use absolute
paths for anything from Homebrew.)

- [ ] **Step 2: Record the real numbers before judging the layout**

```bash
ssh macbook.tailc235d9.ts.net '/usr/bin/swift -e "
import AppKit
for s in NSScreen.screens {
  print(s.localizedName, s.frame, s.safeAreaInsets.top, s.auxiliaryTopLeftArea as Any)
}"'
```
Write the output into this plan under Step 2 as the measured baseline. If
`auxiliaryTopLeftArea` is `nil` on a notched screen, Task 1's `hardware` branch never fires and
the fallback must change — that is a real finding, not a nuisance.

- [ ] **Step 3: Checklist on the notched Mac**

- [ ] collapsed, the panel is invisible — it sits exactly inside the notch, no black fringe
      beside it
- [ ] hovering the notch expands the panel; the bottom corners curve away from the screen edge
- [ ] the panel does not cover the menu-bar clock or the menu-bar extras either side
- [ ] with an app in full screen, the panel still appears on hover (this is what
      `.fullScreenAuxiliary` is for). If it does not, try `level = .mainMenu + 1` — and record
      which level actually worked.
- [ ] on a second Space, the panel is there too (`.canJoinAllSpaces`)
- [ ] plugging in / unplugging an external display re-places the panel on the new main screen
      within a second, and never leaves a stray panel on the old one
- [ ] closing and reopening the lid leaves exactly one panel

- [ ] **Step 4: Fix what the checklist found, with a test where the fix is geometry**

Any change to `NotchGeometry` gets a case in `NotchGeometryTests.swift` using the numbers
measured in Step 2 — that is the only way the notched-Mac behaviour stays verified from a
machine that has no notch.

- [ ] **Step 5: Run the full suite**

Run: `export PATH="$HOME/.swiftly/bin:$PATH"; swift test`
Expected: PASS. Check the printed test **count** matches the previous run plus the new cases —
a truncated run can still exit 0.

- [ ] **Step 6: Commit**

```bash
git commit -m "fix(notch): place the panel correctly on notched and multi-display Macs" \
  -- Sources/ClaudeStatusBarApp/Notch Tests/ClaudeStatusBarAppTests/NotchGeometryTests.swift
```

---

## Task 8: Documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Document the feature**

Add to the README's feature list, next to the menu-bar description:

```markdown
### Notch panel (optional)

Enable **Settings → Show usage rings in the notch** for a panel anchored to the MacBook notch
(or a pill over the middle of the menu bar on displays without one). Hover it to see one ring
per account — worst window, colour-coded, with a badge when the number can't be trusted
(offline, rate-limited, or needing a fresh sign-in). The menu-bar icon is unaffected; the notch
is a second view of the same data, not a replacement.
```

- [ ] **Step 2: Commit**

```bash
git commit -m "docs: describe the optional notch panel" -- README.md
```

---

## Self-review notes

- **Coverage.** Opt-in coexistence → Tasks 4/6. Claude-only, N accounts → Task 3/5.
  Failure-state parity → Task 3 (tested, with ablation) and Task 5 (rendered). Synthetic notch
  first because the dev machine has none → Tasks 1/4. Hardware notch → Task 7. Deferred
  providers → recorded above, no code.
- **Known weak point.** Tasks 4, 5 and 6 are gated by human checklists, not tests. That is
  deliberate — an AppKit window test needs a GUI host, and this repo's rule is that GUI test
  runners never start unattended. The cost is that a regression in the window plumbing will
  not be caught automatically; keep the *logic* in the pure files where the tests are.
- **Riskiest assumption.** `NSScreen.auxiliaryTopLeftArea` behaves as described. Task 1 Step 5
  checks the SDK header and Task 7 Step 2 measures a real notched Mac before any layout claim
  is believed.
