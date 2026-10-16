# Splark Plan 1: Foundation and Integration Spikes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A buildable, tested Swift package and menu-bar app shell for Splark, plus a `splark-dev` command-line tool that proves the Slack and ChatGPT integrations work against real accounts before any engine code depends on them.

**Architecture:** One Swift package at the repo root with three products:
- `SplarkKit`: all logic, covered by `swift test`.
- `Splark`: the menu-bar app, wrapped into `Splark.app` by `scripts/build-app.sh`.
- `splark-dev`: developer commands that run the spec's §13 spikes.

Every network-facing unit goes through the `HTTPTransport` protocol, so tests replay canned responses. Every OAuth redirect lands on `LoopbackServer`.

**Tech Stack:** Swift 6 (`swift-tools-version: 6.0`, strict concurrency), macOS 14+, AppKit, Network.framework, CryptoKit, Security (Keychain), Swift Testing, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-16-splark-design.md`. Read it before starting; this plan argues from it.

**This is plan 1 of 3:**
1. **Foundation and spikes** (this plan).
2. **Engine:** sync, triage, inbox and actions.
3. **App UI and packaging:** panel, setup, settings, icon, release.

Plans 2 and 3 are written after Tasks 9 and 11 report what Slack and ChatGPT actually do (`docs/spikes.md`).

**One deliberate change from the spec:** the spec's §5.1 and §11 generate an Xcode project with XcodeGen. This plan builds the app with SwiftPM plus a 20-line bundling script instead. That means one `swift build` for everything, no extra tool, and nothing generated. It was verified on macOS 26.5 with Xcode 26.6: the ad-hoc-signed bundle shows its status item on screen. Task 1 updates the spec to match.

## Global Constraints

- **Platform:** deployment target macOS 14 (`platforms: [.macOS(.v14)]`); `// swift-tools-version: 6.0`; Swift 6 language mode with strict concurrency, so no warnings about data races.
- **Dependencies:** none outside Apple frameworks.
- **Bundle identifier:** `dev.splark.Splark`. The app's Keychain service is `dev.splark.Splark`; `splark-dev` uses its own service, `dev.splark.dev`.
- **The soft spark:** an 11×11 grid, rows exactly as in spec §4.1. Levels:
  - **dimmed:** lit pixels where `x` is odd and `y` is odd.
  - **brighter:** outline pixels, plus pixels where `(x + y)` is even.
  - **bright:** every lit pixel.

  Menu-bar images are template images.
- **Slack:**
  - User scopes are exactly the 16 in spec §6.1.
  - Redirect is `http://localhost:<port>/slack/callback`, with ports `53682…53691` (first free wins).
  - PKCE S256, `token_rotation_enabled: false`, and the client secret is never stored.
- **Sign in with ChatGPT:**
  - Authorize at `https://auth.openai.com/api/accounts/authorize`; exchange at `https://auth.openai.com/api/accounts/oauth/token`.
  - First sign-in sends `client_id=dynamic_agent_client` plus `agent_name_hint=Splark`.
  - `scope=openid profile email offline_access resource.invoke chatgpt.tokens.use.direct` and `resource=https://api.openai.com/v1`.
  - Redirect is `http://127.0.0.1:<port>/callback` (127.0.0.1, not localhost).
- **Responses API requests:** `stream: true`, `store: false`, and the system prompt in `instructions`. Never send system-role messages, `temperature`, or `max_output_tokens`.
- **Secrets:**
  - Never printed in full; use `mask(_:)` in `splark-dev`.
  - Never written anywhere except the Keychain.
- **Tests:** use Swift Testing (`import Testing`, `@Test`, `#expect`). Tests that touch the real Keychain are skipped when the `CI` environment variable is set.
- **Commits:** as `Ivan Liagushkin <ivliag@gmail.com>` (already set in the repo's local git config). Check with `git log -1 --format=%ae` before pushing.

## Review Focus

Inputs the spec implies, which a person will actually hit, each pinned by a test in the owning task:

1. **Packet splitting.** A browser that sends the OAuth redirect request across several TCP packets must still have its code and state captured. *Task 5:* `capturesARequestSplitAcrossPackets`.
2. **HTML error pages.** Slack, or a proxy in front of it, answering 5xx with an HTML page must become `SlackError.http(503)`, never a decoding error. *Task 7:* `htmlErrorPageBecomesHTTPError`.
3. **429 without `Retry-After`.** Wait 30 s and retry once more, rather than hammering Slack. *Task 7:* `missingRetryAfterWaitsThirtySeconds`.
4. **"99+" badge.** Slack's Dock badge reading "99+" must mean `count(99)`, not "dot". *Task 4:* `parsesLsappinfoOutput` row `99+`.
5. **Cancelled sign-in.** If the user clicks Cancel, the callback carries `error=access_denied` and no code. No token request may be sent, and the error must be clear. *Task 10:* `cancelledSignInNeverCallsTheTokenEndpoint`.

---

### Task 1: Package scaffold, app bundle script and CI

**Files:**
- Create: `Package.swift`, `Sources/SplarkKit/SplarkInfo.swift`, `Sources/Splark/main.swift`, `Sources/Splark/AppDelegate.swift`, `Sources/splark-dev/CLI.swift`, `Sources/splark-dev/main.swift`, `Tests/SplarkKitTests/SmokeTests.swift`, `Support/Info.plist`, `scripts/build-app.sh`, `.github/workflows/ci.yml`
- Modify: `docs/superpowers/specs/2026-10-16-splark-design.md` (§5.1 "Repository shape", §10 "CI", §11 layout)

**Interfaces:**
- Produces: `SplarkInfo.version: String` (`"0.1.0"`); the products `SplarkKit`, `Splark` and `splark-dev`. In `splark-dev`: the global `args: [String]` and `option(_:) -> String?`, `mask(_:) -> String`, `fail(_:) -> Never`, `openInBrowser(_:)`.

- [ ] **Step 1: Write the failing smoke test**

`Tests/SplarkKitTests/SmokeTests.swift`:

```swift
import Testing
@testable import SplarkKit

@Test func versionIsSet() {
    #expect(SplarkInfo.version == "0.1.0")
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test`
Expected: FAIL. There is no `Package.swift` yet ("Could not find Package.swift").

- [ ] **Step 3: Create the package and minimal sources**

`Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SplarkKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SplarkKit", targets: ["SplarkKit"]),
        .executable(name: "Splark", targets: ["Splark"]),
        .executable(name: "splark-dev", targets: ["splark-dev"]),
    ],
    targets: [
        .target(name: "SplarkKit"),
        .executableTarget(name: "Splark", dependencies: ["SplarkKit"]),
        .executableTarget(name: "splark-dev", dependencies: ["SplarkKit"]),
        .testTarget(name: "SplarkKitTests", dependencies: ["SplarkKit"]),
    ]
)
```

`Sources/SplarkKit/SplarkInfo.swift`:

```swift
/// Facts about this build of Splark.
public enum SplarkInfo {
    public static let version = "0.1.0"
}
```

`Sources/Splark/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

`Sources/Splark/AppDelegate.swift` (a placeholder title until Task 3 draws the spark):

```swift
import AppKit
import SplarkKit

/// Plan 1 shell. Task 3 replaces the title with the pixel spark.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Splark \(SplarkInfo.version)"

        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Splark", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        if ProcessInfo.processInfo.environment["SPLARK_DEBUG_STATUS_ITEM"] != nil { reportStatusItem() }
    }

    /// Prints the status item's on-screen frame, so it can be checked from a terminal
    /// without screen-recording permission. Exits after printing.
    private func reportStatusItem() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let window = self?.statusItem.button?.window else { print("status item: no window"); exit(1) }
            print("status item: frame=\(window.frame) visible=\(window.isVisible) onScreen=\(window.occlusionState.contains(.visible))")
            exit(0)
        }
    }
}
```

`Sources/splark-dev/CLI.swift`:

```swift
import AppKit
import Foundation

// Shared helpers for splark-dev commands.

let args = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func mask(_ token: String) -> String { token.count > 12 ? "\(token.prefix(9))…\(token.suffix(4))" : "…" }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func openInBrowser(_ url: URL) { NSWorkspace.shared.open(url) }
```

`Sources/splark-dev/main.swift` (commands are added by later tasks):

```swift
import Foundation

// splark-dev: developer commands that exercise SplarkKit against real accounts (spec §13 spikes).

let usage = """
usage: splark-dev <command>
"""

print(usage)
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test`
Expected: PASS, `✔ Test run with 1 test`.

- [ ] **Step 5: Add the bundle files and build the app**

`Support/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleDisplayName</key><string>Splark</string>
	<key>CFBundleExecutable</key><string>Splark</string>
	<key>CFBundleIdentifier</key><string>dev.splark.Splark</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>Splark</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHumanReadableCopyright</key><string>© 2026 Ivan Liagushkin. MIT licence.</string>
</dict>
</plist>
```

`scripts/build-app.sh` (then `chmod +x scripts/build-app.sh`):

```bash
#!/usr/bin/env bash
# Builds Splark.app into build/ from the SwiftPM "Splark" product and ad-hoc signs it.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG" --product Splark
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Splark"
APP="build/Splark.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Splark"
cp Support/Info.plist "$APP/Contents/Info.plist"
if [ -f Support/AppIcon.icns ]; then
  cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi
codesign --force --options runtime --sign - "$APP"
echo "$APP"
```

Run: `./scripts/build-app.sh debug && SPLARK_DEBUG_STATUS_ITEM=1 build/Splark.app/Contents/MacOS/Splark`
Expected: the last line reads `build/Splark.app`, followed by `status item: frame=(…) visible=true onScreen=true`. The y value should be near the top of your screen.

- [ ] **Step 6: Add CI**

`.github/workflows/ci.yml`:

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  build-and-test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Toolchain
        run: swift --version
      - name: Test
        run: swift test
      - name: Build app bundle
        run: ./scripts/build-app.sh release
```

(GitHub sets `CI=true`, which skips the Keychain test added in Task 6.)

- [ ] **Step 7: Update the spec to the SwiftPM build**

In `docs/superpowers/specs/2026-10-16-splark-design.md`:

1. In §5.1, replace the bullet that begins `- **Repository shape:**` with:

   `- **Repository shape:** one Swift package at the repo root. The library \`SplarkKit\` holds all logic and is tested with \`swift test\`. The executable \`Splark\` is the app; \`scripts/build-app.sh\` wraps it into \`Splark.app\` with \`Support/Info.plist\` and ad-hoc signs it. The executable \`splark-dev\` holds the developer commands for spikes and evaluation. There is no Xcode project; open \`Package.swift\` in Xcode for previews and debugging.`

2. In §10, replace the bullet that begins `- **CI:**` with:

   `- **CI:** GitHub Actions on macOS runs \`swift test\`, then \`scripts/build-app.sh release\`.`

3. In §11, replace the whole code block with:

   ```
   splark/
     README.md  LICENSE (MIT)  Package.swift  .github/workflows/ci.yml
     Sources/SplarkKit/            # all units from §5.2 except UI
     Sources/Splark/               # the app: AppDelegate, status item, panel, setup, settings
     Sources/splark-dev/           # developer commands (spikes, triage evaluation)
     Tests/SplarkKitTests/         # + Fixtures/
     Support/                      # Info.plist, AppIcon.icns
     design/prototype/             # panel.html, setup.html, icon-explorations.html
     docs/superpowers/specs/       # this spec
     docs/superpowers/plans/       # implementation plans
     docs/spikes.md                # what the §13 spikes found
     scripts/                      # build-app.sh, make-icon.sh
   ```

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources Tests Support scripts .github docs/superpowers/specs
git commit -m "Scaffold the Swift package, app bundle script and CI

One package with three products: SplarkKit (logic), Splark (the
menu-bar app, bundled by scripts/build-app.sh) and splark-dev
(developer commands). The spec now describes the SwiftPM build in
place of XcodeGen."
```

---

### Task 2: Pixel art (the spark and its three brightness levels)

**Files:**
- Create: `Sources/SplarkKit/PixelArt.swift`
- Test: `Tests/SplarkKitTests/PixelArtTests.swift`

**Interfaces:**
- Produces:
  - `enum SparkLevel { dimmed, brighter, bright }` (`String`, `Codable`, `CaseIterable`).
  - `struct PixelPoint { x, y }`.
  - `struct PixelGrid`, with `init(rows:)`, `subscript(x:y:) -> Bool`, `isLit(x:y:level:)`, `litPoints(level:) -> [PixelPoint]` and `rendered(level:) -> [String]`.
  - `enum PixelArt`, with `static let spark: PixelGrid` and `static func image(_:level:scale:color:template:) -> NSImage`.

- [ ] **Step 1: Write the failing tests**

`Tests/SplarkKitTests/PixelArtTests.swift`:

```swift
import AppKit
import Testing
@testable import SplarkKit

@Suite struct PixelArtTests {
    @Test func brightLightsTheWholeSilhouette() {
        #expect(PixelArt.spark.rendered(level: .bright) == [
            ".....#.....", ".....#.....", "....###....", "...#####...", "..#######..", "###########",
            "..#######..", "...#####...", "....###....", ".....#.....", ".....#.....",
        ])
        #expect(PixelArt.spark.litPoints(level: .bright).count == 45)
    }

    @Test func brighterIsOutlinePlusChecker() {
        #expect(PixelArt.spark.rendered(level: .brighter) == [
            ".....#.....", ".....#.....", "....#.#....", "...#.#.#...", "..#.#.#.#..", "##.#.#.#.##",
            "..#.#.#.#..", "...#.#.#...", "....#.#....", ".....#.....", ".....#.....",
        ])
        #expect(PixelArt.spark.litPoints(level: .brighter).count == 29)
    }

    @Test func dimmedLightsOnlyOddOddPixels() {
        #expect(PixelArt.spark.rendered(level: .dimmed) == [
            "...........", ".....#.....", "...........", "...#.#.#...", "...........", ".#.#.#.#.#.",
            "...........", "...#.#.#...", "...........", ".....#.....", "...........",
        ])
        #expect(PixelArt.spark.litPoints(level: .dimmed).count == 13)
    }

    @Test func imageHasGridSizeTimesScaleAndPaintsOnlyLitPixels() throws {
        let image = PixelArt.image(PixelArt.spark, level: .bright, scale: 2, color: .black)
        #expect(image.size == NSSize(width: 22, height: 22))
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let rep = NSBitmapImageRep(cgImage: cg)
        let pxPerPoint = CGFloat(rep.pixelsWide) / image.size.width
        func alpha(atGridX x: Int, y: Int) -> CGFloat {
            let px = Int((CGFloat(x) * 2 + 1) * pxPerPoint), py = Int((CGFloat(y) * 2 + 1) * pxPerPoint)
            return rep.colorAt(x: px, y: py)?.alphaComponent ?? 0
        }
        #expect(alpha(atGridX: 5, y: 5) > 0.9)   // centre is lit
        #expect(alpha(atGridX: 0, y: 0) < 0.1)   // corner is not
    }

    @Test func templateFlagIsPassedThrough() {
        #expect(PixelArt.image(PixelArt.spark, level: .dimmed, template: true).isTemplate)
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter PixelArtTests`
Expected: FAIL to compile with "cannot find 'PixelArt' in scope".

- [ ] **Step 3: Implement**

`Sources/SplarkKit/PixelArt.swift`:

```swift
import AppKit

/// The three brightness levels. Same silhouette; only how many pixels are lit changes.
public enum SparkLevel: String, Sendable, CaseIterable, Codable {
    case dimmed    // just comments: 25% (odd x and odd y)
    case brighter  // question for you: outline + 50% checker inside
    case bright    // needs action: every pixel
}

public struct PixelPoint: Hashable, Sendable {
    public let x: Int
    public let y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

/// A 1-bit pixel grid authored as rows of "#" (lit) and "." (unlit).
public struct PixelGrid: Sendable, Equatable {
    public let width: Int
    public let height: Int
    private let bits: [Bool]

    public init(rows: [String]) {
        precondition(!rows.isEmpty && rows.allSatisfy { $0.count == rows[0].count }, "rows must form a non-empty rectangle")
        height = rows.count
        width = rows[0].count
        bits = rows.flatMap { $0.map { $0 == "#" } }
    }

    public subscript(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height && bits[y * width + x]
    }

    public func isLit(x: Int, y: Int, level: SparkLevel) -> Bool {
        guard self[x, y] else { return false }
        switch level {
        case .bright: return true
        case .dimmed: return x % 2 == 1 && y % 2 == 1
        case .brighter:
            let edge = !self[x - 1, y] || !self[x + 1, y] || !self[x, y - 1] || !self[x, y + 1]
            return edge || (x + y) % 2 == 0
        }
    }

    public func litPoints(level: SparkLevel) -> [PixelPoint] {
        (0..<height).flatMap { y in (0..<width).compactMap { x in isLit(x: x, y: y, level: level) ? PixelPoint(x: x, y: y) : nil } }
    }

    /// Rows of "#"/"." for the given level. Handy for tests and debugging.
    public func rendered(level: SparkLevel) -> [String] {
        (0..<height).map { y in String((0..<width).map { x in isLit(x: x, y: y, level: level) ? "#" : "." }) }
    }
}

public enum PixelArt {
    /// The soft spark, 11×11 (spec §4.1).
    public static let spark = PixelGrid(rows: [
        ".....#.....",
        ".....#.....",
        "....###....",
        "...#####...",
        "..#######..",
        "###########",
        "..#######..",
        "...#####...",
        "....###....",
        ".....#.....",
        ".....#.....",
    ])

    /// Renders a grid at `scale` points per pixel. Template images are tinted by AppKit (menu bar).
    public static func image(_ grid: PixelGrid, level: SparkLevel, scale: CGFloat = 1, color: NSColor = .black, template: Bool = false) -> NSImage {
        let size = NSSize(width: CGFloat(grid.width) * scale, height: CGFloat(grid.height) * scale)
        let points = grid.litPoints(level: level)
        let image = NSImage(size: size, flipped: true) { _ in
            color.setFill()
            for p in points {
                NSRect(x: CGFloat(p.x) * scale, y: CGFloat(p.y) * scale, width: scale, height: scale).fill()
            }
            return true
        }
        image.isTemplate = template
        return image
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test --filter PixelArtTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SplarkKit/PixelArt.swift Tests/SplarkKitTests/PixelArtTests.swift
git commit -m "Add the pixel spark and its three brightness levels

Dimmed lights odd-odd pixels, brighter lights the outline plus a
checker, bright lights everything. Golden patterns pin each level."
```

---

### Task 3: The spark in the menu bar

**Files:**
- Modify: `Sources/Splark/AppDelegate.swift` (replace the whole file)

**Interfaces:**
- Consumes: `PixelArt.spark`, `PixelArt.image(_:level:scale:color:template:)` and `SparkLevel` from Task 2.
- Produces: `AppDelegate.show(level: SparkLevel, count: Int?)`, which Plan 3 drives from the inbox.

- [ ] **Step 1: Replace the placeholder with the spark**

`Sources/Splark/AppDelegate.swift`:

```swift
import AppKit
import SplarkKit

/// Plan 1 shell: the spark in the menu bar (bright, with a placeholder count) and a Quit menu.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        show(level: .bright, count: 5)

        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Splark", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        if ProcessInfo.processInfo.environment["SPLARK_DEBUG_STATUS_ITEM"] != nil { reportStatusItem() }
    }

    func show(level: SparkLevel, count: Int?) {
        statusItem.button?.image = PixelArt.image(PixelArt.spark, level: level, template: true)
        statusItem.button?.title = count.map { " \($0)" } ?? ""
    }

    /// Prints the status item's on-screen frame, so it can be checked from a terminal
    /// without screen-recording permission. Exits after printing.
    private func reportStatusItem() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let window = self?.statusItem.button?.window else { print("status item: no window"); exit(1) }
            print("status item: frame=\(window.frame) visible=\(window.isVisible) onScreen=\(window.occlusionState.contains(.visible))")
            exit(0)
        }
    }
}
```

- [ ] **Step 2: Build and check the status item**

Run: `./scripts/build-app.sh debug && SPLARK_DEBUG_STATUS_ITEM=1 build/Splark.app/Contents/MacOS/Splark`
Expected: `status item: frame=(…, …, ~45.0, ~33.0) visible=true onScreen=true`. The width is about 45 pt (spark plus " 5").

- [ ] **Step 3: Look at it**

Run: `open build/Splark.app`. Ask the human to confirm they see a small solid four-point pixel star with "5" in the menu bar, then quit it from its menu ("Quit Splark"). If the menu bar is crowded, the item may be hidden behind the notch; ⌘-drag it into view.

- [ ] **Step 4: Commit**

```bash
git add Sources/Splark/AppDelegate.swift
git commit -m "Show the pixel spark in the menu bar

The status item draws the bright spark as a template image with a
placeholder count, and keeps a Quit menu."
```

---

### Task 4: Badge watcher and `splark-dev badge`

**Files:**
- Create: `Sources/SplarkKit/BadgeWatcher.swift`, `Sources/splark-dev/BadgeCommand.swift`, `docs/spikes.md`
- Modify: `Sources/splark-dev/main.swift` (replace the whole file)
- Test: `Tests/SplarkKitTests/BadgeWatcherTests.swift`

**Interfaces:**
- Produces:
  - `enum SlackBadge { none, dot, count(Int) }`, with `static func parse(lsappinfoOutput:) -> SlackBadge?`.
  - `protocol CommandRunner`, implemented by `ProcessRunner`.
  - `final class BadgeWatcher`, with `init(runner:interval:isSlackRunning:)`, `current() -> SlackBadge?`, `start(onChange:)` and `stop()`, plus `static let slackBundleID = "com.tinyspeck.slackmacgap"`.

- [ ] **Step 1: Write the failing tests**

`Tests/SplarkKitTests/BadgeWatcherTests.swift`:

```swift
import Foundation
import Testing
@testable import SplarkKit

@Suite struct BadgeWatcherTests {
    @Test(arguments: [
        (#""StatusLabel"={ "label"="" }"#, SlackBadge?.some(.none)),
        (#""StatusLabel"={ "label"="•" }"#, .some(.dot)),
        (#""StatusLabel"={ "label"="12" }"#, .some(.count(12))),
        (#""StatusLabel"={ "label"="0" }"#, .some(.none)),
        (#""StatusLabel"={ "label"="!" }"#, .some(.dot)),
        (#""StatusLabel"={ "label"="99+" }"#, .some(.count(99))),
        ("", nil),
    ])
    func parsesLsappinfoOutput(output: String, expected: SlackBadge?) {
        #expect(SlackBadge.parse(lsappinfoOutput: output) == expected)
    }

    struct FakeRunner: CommandRunner {
        let output: String
        func run(_ executable: String, _ arguments: [String]) throws -> String {
            precondition(executable == "/usr/bin/lsappinfo" && arguments == ["info", "-only", "StatusLabel", "-app", "com.tinyspeck.slackmacgap"])
            return output
        }
    }

    @Test func readsBadgeOnlyWhileSlackRuns() {
        let running = BadgeWatcher(runner: FakeRunner(output: #""StatusLabel"={ "label"="3" }"#), isSlackRunning: { true })
        #expect(running.current() == .count(3))
        let notRunning = BadgeWatcher(runner: FakeRunner(output: #""StatusLabel"={ "label"="3" }"#), isSlackRunning: { false })
        #expect(notRunning.current() == nil)
    }

    @Test func startReportsFirstReadingThenOnlyChanges() async throws {
        final class Box: @unchecked Sendable { let lock = NSLock(); var seen: [SlackBadge?] = [] }
        let box = Box()
        let watcher = BadgeWatcher(runner: FakeRunner(output: #""StatusLabel"={ "label"="•" }"#), interval: .milliseconds(20), isSlackRunning: { true })
        watcher.start { badge in box.lock.withLock { box.seen.append(badge) } }
        try await Task.sleep(for: .milliseconds(150))
        watcher.stop()
        #expect(box.lock.withLock { box.seen } == [.dot])
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter BadgeWatcherTests`
Expected: FAIL to compile with "cannot find 'SlackBadge' in scope".

- [ ] **Step 3: Implement**

`Sources/SplarkKit/BadgeWatcher.swift`:

```swift
import AppKit

/// What Slack's Dock badge currently says.
public enum SlackBadge: Equatable, Sendable {
    case none          // no badge
    case dot           // "•": unread activity, nothing for you specifically
    case count(Int)    // DMs, mentions, keywords, followed threads

    /// Parses `lsappinfo info -only StatusLabel …` output. Returns nil when there is no StatusLabel line.
    public static func parse(lsappinfoOutput output: String) -> SlackBadge? {
        guard let range = output.range(of: #""label"="([^"]*)""#, options: .regularExpression) else { return nil }
        let label = output[range].dropFirst("\"label\"=\"".count).dropLast()
        if label.isEmpty { return SlackBadge.none }
        let digits = label.prefix(while: \.isNumber)
        if let n = Int(digits) { return n > 0 ? .count(n) : SlackBadge.none }   // "99+" → 99
        return .dot
    }
}

public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String]) throws -> String
}

public struct ProcessRunner: CommandRunner {
    public init() {}
    public func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Polls Slack's Dock badge via `lsappinfo` (no permissions needed) while Slack is running.
public final class BadgeWatcher: @unchecked Sendable {
    public static let slackBundleID = "com.tinyspeck.slackmacgap"
    private let runner: CommandRunner
    private let isSlackRunning: @Sendable () -> Bool
    private let interval: Duration
    private var task: Task<Void, Never>?

    public init(runner: CommandRunner = ProcessRunner(),
                interval: Duration = .seconds(2),
                isSlackRunning: @escaping @Sendable () -> Bool = {
                    !NSRunningApplication.runningApplications(withBundleIdentifier: BadgeWatcher.slackBundleID).isEmpty
                }) {
        self.runner = runner
        self.interval = interval
        self.isSlackRunning = isSlackRunning
    }

    /// nil = Slack isn't running, or the badge can't be read.
    public func current() -> SlackBadge? {
        guard isSlackRunning(),
              let output = try? runner.run("/usr/bin/lsappinfo", ["info", "-only", "StatusLabel", "-app", Self.slackBundleID])
        else { return nil }
        return SlackBadge.parse(lsappinfoOutput: output)
    }

    /// Calls `onChange` with the first reading and then on every change, until `stop()`.
    public func start(onChange: @escaping @Sendable (SlackBadge?) -> Void) {
        stop()
        task = Task { [weak self] in
            var last: SlackBadge?? = .none
            while !Task.isCancelled, let self {
                let now = self.current()
                if last != .some(now) { last = .some(now); onChange(now) }
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    public func stop() { task?.cancel(); task = nil }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test --filter BadgeWatcherTests`
Expected: PASS. That's 2 tests plus the 7 parameterised `parsesLsappinfoOutput` cases.

- [ ] **Step 5: Add the `badge` command**

`Sources/splark-dev/BadgeCommand.swift`:

```swift
import Foundation
import SplarkKit

func badgeCommand() async {
    let seconds = Int(option("--seconds") ?? "20") ?? 20
    let watcher = BadgeWatcher()
    print("Watching Slack's badge for \(seconds) s (change it in Slack to see updates)…")
    watcher.start { badge in print("\(Date().formatted(date: .omitted, time: .standard))  \(badge.map { "\($0)" } ?? "unavailable (Slack not running?)")") }
    try? await Task.sleep(for: .seconds(seconds))
    watcher.stop()
}
```

`Sources/splark-dev/main.swift`:

```swift
import Foundation

// splark-dev: developer commands that exercise SplarkKit against real accounts (spec §13 spikes).

let usage = """
usage: splark-dev <command>
  badge [--seconds N]                 watch Slack's Dock badge
"""

switch args.first {
case "badge": await badgeCommand()
default: print(usage)
}
```

- [ ] **Step 6: Spike 2. Does the badge reach Splark?**

1. With the Slack desktop app running, run `swift run splark-dev badge --seconds 60`.
2. While it runs, ask the human to:
   1. Have someone send them a DM, or post in a channel themselves from another device. Expected: `count(n)` or `dot`.
   2. Read everything in Slack. Expected: `none`.
   3. Turn off System Settings → Notifications → Slack → **Badge application icon**, then repeat step 1. Record whether the badge is still readable.
   4. Quit Slack. Expected: `unavailable (Slack not running?)`.
3. Create `docs/spikes.md` and record the observed lines:

```markdown
# Spike results

What the spec's §13 risks turned out to be, measured on real accounts. Plans 2 and 3 build on this file.

## 2. Badge via lsappinfo

- macOS version: (output of `sw_vers -productVersion`)
- DM or mention arrives: (observed `splark-dev badge` line)
- Everything read: (observed line)
- macOS "Badge application icon" off: (observed line — still readable, or not)
- Slack quit: (observed line)
- **Decision:** (one of: "badge signal works, including with macOS badges off" / "badge signal works only with macOS badges on — Settings must say so" / "badge signal unusable — schedule-only polling")
```

- [ ] **Step 7: Commit**

```bash
git add Sources/SplarkKit/BadgeWatcher.swift Sources/splark-dev Tests/SplarkKitTests/BadgeWatcherTests.swift docs/spikes.md
git commit -m "Read Slack's Dock badge with lsappinfo

BadgeWatcher polls only while Slack runs and reports none, dot or a
count. splark-dev badge shows it live; docs/spikes.md records how it
behaved, including with macOS badges turned off."
```

---

### Task 5: PKCE and the loopback OAuth listener

**Files:**
- Create: `Sources/SplarkKit/PKCE.swift`, `Sources/SplarkKit/LoopbackServer.swift`
- Test: `Tests/SplarkKitTests/LoopbackServerTests.swift`

**Interfaces:**
- Produces:
  - `struct PKCE { verifier, challenge }`, with `init(verifier:)`, `static func random() -> PKCE` and `static func randomURLSafeString(byteCount:) -> String`.
  - `final class LoopbackServer`:
    - `init(port: UInt16, path: String, ipv4Only: Bool = false, successHTML:) throws`. Port `0` means "any free port".
    - `let port: UInt16`, `waitForCallback(timeout:) async throws -> Callback`, `stop()`.
    - `struct Callback { path, query: [String: String] }`.
    - `enum ServerError { portUnavailable(UInt16), timedOut, cancelled }`.

- [ ] **Step 1: Write the failing tests**

`Tests/SplarkKitTests/LoopbackServerTests.swift`:

```swift
import Foundation
import Network
import Testing
@testable import SplarkKit

@Suite struct LoopbackServerTests {
    @Test(arguments: ["127.0.0.1", "localhost"])
    func capturesCallback(host: String) async throws {
        let server = try LoopbackServer(port: 0, path: "/callback")
        let waiter = Task { try await server.waitForCallback(timeout: .seconds(5)) }
        let url = URL(string: "http://\(host):\(server.port)/callback?code=abc%20123&state=xyz")!
        let (data, response) = try await URLSession.shared.data(from: url)
        #expect((response as! HTTPURLResponse).statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).contains("You're connected"))
        #expect(try await waiter.value.query == ["code": "abc 123", "state": "xyz"])
    }

    @Test func keepsACallbackThatArrivesBeforeWaiting() async throws {
        let server = try LoopbackServer(port: 0, path: "/callback")
        _ = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(server.port)/callback?code=early&state=s")!)
        #expect(try await server.waitForCallback(timeout: .seconds(2)).query["code"] == "early")
    }

    @Test func capturesARequestSplitAcrossPackets() async throws {
        let server = try LoopbackServer(port: 0, path: "/callback")
        let waiter = Task { try await server.waitForCallback(timeout: .seconds(5)) }
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: server.port)!, using: .tcp)
        connection.start(queue: .global())
        connection.send(content: Data("GET /callback?code=sp".utf8), completion: .contentProcessed { _ in })
        try await Task.sleep(for: .milliseconds(150))
        connection.send(content: Data("lit&state=s HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8), completion: .contentProcessed { _ in })
        #expect(try await waiter.value.query == ["code": "split", "state": "s"])
        connection.cancel()
    }

    @Test func ignoresOtherPathsAndTimesOut() async throws {
        let server = try LoopbackServer(port: 0, path: "/callback")
        let waiter = Task { try await server.waitForCallback(timeout: .milliseconds(800)) }
        let (_, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(server.port)/favicon.ico")!)
        #expect((response as! HTTPURLResponse).statusCode == 404)
        await #expect(throws: LoopbackServer.ServerError.timedOut) { try await waiter.value }
    }

    @Test func refusesAPortInUse() throws {
        let first = try LoopbackServer(port: 0, path: "/callback")
        #expect(throws: LoopbackServer.ServerError.self) { try LoopbackServer(port: first.port, path: "/callback") }
        first.stop()
    }

    @Test func parsesRequestLine() {
        #expect(LoopbackServer.parse(requestHead: "GET /slack/callback?code=a&state=b HTTP/1.1\r\nHost: x\r\n\r\n")
                == .init(path: "/slack/callback", query: ["code": "a", "state": "b"]))
        #expect(LoopbackServer.parse(requestHead: "POST /x HTTP/1.1\r\n\r\n") == nil)
    }
}

@Suite struct PKCETests {
    @Test func matchesRFC7636Vector() {
        #expect(PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk").challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func randomVerifierIs43URLSafeCharacters() {
        let v = PKCE.random().verifier
        #expect(v.count == 43)
        #expect(v.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(PKCE.random() != PKCE.random())
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter "LoopbackServerTests|PKCETests"`
Expected: FAIL to compile with "cannot find 'LoopbackServer' in scope".

- [ ] **Step 3: Implement PKCE**

`Sources/SplarkKit/PKCE.swift`:

```swift
import CryptoKit
import Foundation

public struct PKCE: Sendable, Equatable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public static func random() -> PKCE {
        PKCE(verifier: randomURLSafeString(byteCount: 32))
    }

    public static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

- [ ] **Step 4: Implement the loopback server**

`Sources/SplarkKit/LoopbackServer.swift`:

```swift
import Foundation
import Network

/// One-shot HTTP listener on the loopback interface that captures a single OAuth redirect.
public final class LoopbackServer: @unchecked Sendable {
    public struct Callback: Sendable, Equatable {
        public let path: String
        public let query: [String: String]
    }

    public enum ServerError: Error, Equatable { case portUnavailable(UInt16), timedOut, cancelled }

    public let port: UInt16
    private let path: String
    private let successHTML: String
    private let queue = DispatchQueue(label: "splark.loopback")
    private var listeners: [NWListener] = []
    private var continuation: CheckedContinuation<Callback, Error>?
    private var received: Callback?
    private var finished = false

    /// Binds 127.0.0.1 and, unless `ipv4Only`, ::1 on `port` (0 = pick a free port).
    public init(port: UInt16, path: String, ipv4Only: Bool = false, successHTML: String = LoopbackServer.defaultHTML) throws {
        self.path = path
        self.successHTML = successHTML
        let v4 = try Self.makeListener(host: "127.0.0.1", port: port)
        let actualPort = try Self.start(v4, on: queue)
        self.port = actualPort
        listeners = [v4]
        if !ipv4Only, let v6 = try? Self.makeListener(host: "::1", port: actualPort), (try? Self.start(v6, on: queue)) != nil {
            listeners.append(v6)
        }
        for listener in listeners {
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        }
    }

    public static let defaultHTML = """
    <!doctype html><html><head><meta charset="utf-8"><title>Splark</title></head>
    <body style="font-family:-apple-system,sans-serif;color:#3a3a3e;text-align:center;padding-top:80px">
    <h2 style="font-weight:600">You're connected.</h2><p>You can close this tab and go back to Splark.</p></body></html>
    """

    /// Waits for the first request whose path matches, then stops listening.
    public func waitForCallback(timeout: Duration = .seconds(600)) async throws -> Callback {
        try await withThrowingTaskGroup(of: Callback.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { cont in
                    self.queue.async {
                        if let received = self.received { cont.resume(returning: received) }
                        else if self.finished { cont.resume(throwing: ServerError.cancelled) }
                        else { self.continuation = cont }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ServerError.timedOut
            }
            defer { group.cancelAll(); self.stop() }
            return try await group.next()!
        }
    }

    public func stop() {
        queue.async {
            guard !self.finished else { return }
            self.finished = true
            self.listeners.forEach { $0.cancel() }
            self.continuation?.resume(throwing: ServerError.cancelled)
            self.continuation = nil
        }
    }

    private static func makeListener(host: String, port: UInt16) throws -> NWListener {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? .any)
        return try NWListener(using: params)
    }

    private static func start(_ listener: NWListener, on queue: DispatchQueue) throws -> UInt16 {
        let ready = DispatchSemaphore(value: 0)
        let failure = LockedBox<Error?>(nil)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let error): failure.value = error; ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { $0.cancel() }
        listener.start(queue: queue)
        if ready.wait(timeout: .now() + 2) == .timedOut || failure.value != nil || listener.port == nil {
            listener.cancel()
            throw ServerError.portUnavailable(listener.port?.rawValue ?? 0)
        }
        return listener.port!.rawValue
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHead(connection, buffer: Data())
    }

    /// Reads until the end of the HTTP head (a blank line), however the bytes are split across packets.
    private func receiveHead(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            let headComplete = buffer.range(of: Data("\r\n\r\n".utf8)) != nil
            if !headComplete, !isComplete, error == nil, buffer.count < 65_536 {
                self.receiveHead(connection, buffer: buffer)
                return
            }
            self.respond(connection, head: String(decoding: buffer, as: UTF8.self))
        }
    }

    private func respond(_ connection: NWConnection, head: String) {
        let callback = Self.parse(requestHead: head)
        let matched = callback?.path == path
        let body = matched ? successHTML : "Not found"
        let status = matched ? "200 OK" : "404 Not Found"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        if matched, let callback, !finished {
            finished = true
            received = callback
            listeners.forEach { $0.cancel() }
            continuation?.resume(returning: callback)
            continuation = nil
        }
    }

    /// Parses `GET /path?a=1&b=2 HTTP/1.1` into path and decoded query items.
    static func parse(requestHead: String) -> Callback? {
        guard let line = requestHead.split(separator: "\r\n", omittingEmptySubsequences: false).first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET", let components = URLComponents(string: String(parts[1])) else { return nil }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return Callback(path: components.path, query: query)
    }
}

final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value
    init(_ value: Value) { _value = value }
    var value: Value {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `swift test --filter "LoopbackServerTests|PKCETests"`
Expected: PASS, 8 tests (`capturesCallback` runs twice: 127.0.0.1 and localhost).

- [ ] **Step 6: Commit**

```bash
git add Sources/SplarkKit/PKCE.swift Sources/SplarkKit/LoopbackServer.swift Tests/SplarkKitTests/LoopbackServerTests.swift
git commit -m "Add PKCE and a one-shot loopback OAuth listener

The listener binds 127.0.0.1 and ::1 (Slack's redirect says
localhost), reads the request head across packets, keeps a callback
that arrives before anyone waits, and times out cleanly."
```

---

### Task 6: Secret store (Keychain)

**Files:**
- Create: `Sources/SplarkKit/SecretStore.swift`
- Test: `Tests/SplarkKitTests/SecretStoreTests.swift`

**Interfaces:**
- Produces:
  - `protocol SecretStore`, with `read(_:) throws -> String?`, `write(_:for:) throws` and `delete(_:) throws`.
  - `struct KeychainStore(service:)`, whose default service is `"dev.splark.Splark"`.
  - `final class InMemorySecretStore`.
  - `enum SecretStoreError { keychain(OSStatus) }`.

- [ ] **Step 1: Write the failing tests**

`Tests/SplarkKitTests/SecretStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import SplarkKit

@Suite struct SecretStoreTests {
    @Test func inMemoryRoundTrip() throws {
        let store = InMemorySecretStore()
        #expect(try store.read("a") == nil)
        try store.write("1", for: "a")
        try store.write("2", for: "a")
        #expect(try store.read("a") == "2")
        try store.delete("a")
        try store.delete("a")
        #expect(try store.read("a") == nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil, "CI runners have no unlocked login keychain"))
    func keychainRoundTrip() throws {
        let store = KeychainStore(service: "dev.splark.tests.\(UUID().uuidString)")
        defer { try? store.delete("token") }
        #expect(try store.read("token") == nil)
        try store.write("xoxp-1", for: "token")
        try store.write("xoxp-2", for: "token")
        #expect(try store.read("token") == "xoxp-2")
        try store.delete("token")
        #expect(try store.read("token") == nil)
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter SecretStoreTests`
Expected: FAIL to compile with "cannot find 'InMemorySecretStore' in scope".

- [ ] **Step 3: Implement**

`Sources/SplarkKit/SecretStore.swift`:

```swift
import Foundation
import Security

/// Where Splark keeps tokens. Values are UTF-8 strings (JSON for structured credentials).
public protocol SecretStore: Sendable {
    func read(_ key: String) throws -> String?
    func write(_ value: String, for key: String) throws
    func delete(_ key: String) throws
}

public enum SecretStoreError: Error, Equatable { case keychain(OSStatus) }

/// Generic-password items in the login keychain, one per key, under a single service name.
public struct KeychainStore: SecretStore {
    public let service: String
    public init(service: String = "dev.splark.Splark") { self.service = service }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    public func read(_ key: String) throws -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw SecretStoreError.keychain(status) }
        return String(decoding: data, as: UTF8.self)
    }

    public func write(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(key)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw SecretStoreError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw SecretStoreError.keychain(status)
        }
    }

    public func delete(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError.keychain(status) }
    }
}

/// Test double and preview store.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    public init(_ initial: [String: String] = [:]) { values = initial }
    public func read(_ key: String) throws -> String? { lock.withLock { values[key] } }
    public func write(_ value: String, for key: String) throws { lock.withLock { values[key] = value } }
    public func delete(_ key: String) throws { lock.withLock { _ = values.removeValue(forKey: key) } }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test --filter SecretStoreTests`
Expected: PASS, 2 tests. If macOS shows a Keychain access prompt, ask the human to click **Always Allow**; it's the test runner's own item.

- [ ] **Step 5: Commit**

```bash
git add Sources/SplarkKit/SecretStore.swift Tests/SplarkKitTests/SecretStoreTests.swift
git commit -m "Store secrets in the login Keychain

One generic-password item per key under a single service name, plus
an in-memory store for tests and previews."
```

---

### Task 7: Slack Web API client with rate limiting

**Files:**
- Create: `Sources/SplarkKit/Support/HTTPTransport.swift`, `Sources/SplarkKit/Slack/RateLimiter.swift`, `Sources/SplarkKit/Slack/SlackClient.swift`, `Sources/SplarkKit/Slack/SlackModels.swift`, `Sources/SplarkKit/Slack/SlackClient+Methods.swift`
- Test: `Tests/SplarkKitTests/TestSupport.swift`, `Tests/SplarkKitTests/SlackClientTests.swift`

**Interfaces:**
- Produces:
  - **Transport:** `protocol HTTPTransport { send(URLRequest) async throws -> (Data, HTTPURLResponse) }`, implemented by `URLSessionTransport`. `protocol Sleeper`, implemented by `TaskSleeper`. `URLRequest.form(_:_:bearer:)` (internal).
  - **Rate limiting:** `enum SlackTier { tier1…tier4, perMinute(Int) }`. `actor RateLimiter`, with `init(now:)`, `reserve(_:tier:) -> TimeInterval` and `pause(_:retryAfter:)`.
  - **Client:** `enum SlackError { api(String), rateLimited(retryAfter:), http(Int), decoding(String) }`. `struct SlackClient(token:transport:limiter:sleeper:baseURL:)`, with:
    - generic `call(_:tier:params:bearer:as:)` and `static let decoder`;
    - the methods `authTest()`, `usersConversations(cursor:)`, `allConversations()`, `conversationsInfo(_:)`, `conversationsHistory(_:oldest:limit:)`, `searchMessages(_:count:)`, `appsManifestCreate(configToken:manifestJSON:)` and `oauthV2Access(clientId:code:redirectURI:codeVerifier:)`.
  - **Models:** `SlackAuthTest`, `SlackConversation` (with `kind`), `SlackConversationList`, `SlackConversationInfo`, `SlackMessage`, `SlackHistory`, `SlackSearchResult`, `SlackManifestCreate`, `SlackOAuthAccess`, `SlackResponseMetadata`.
  - **Test doubles** (tests only): `StubTransport` (with `formBody(_:)`), `RecordingSleeper`, `ManualClock`.

- [ ] **Step 1: Write the test doubles**

`Tests/SplarkKitTests/TestSupport.swift`:

```swift
import Foundation
@testable import SplarkKit

/// Replays queued responses in order and records every request it receives.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Reply { let status: Int; let body: String; let headers: [String: String] }
    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }
    convenience init(json bodies: String...) { self.init(bodies.map { Reply(status: 200, body: $0, headers: [:]) }) }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = lock.withLock {
            requests.append(request)
            return replies.isEmpty ? Reply(status: 500, body: "{}", headers: [:]) : replies.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }

    func formBody(_ index: Int) -> [String: String] {
        let body = String(decoding: requests[index].httpBody ?? Data(), as: UTF8.self)
        var out: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            out[kv[0]] = kv.count > 1 ? kv[1].removingPercentEncoding : ""
        }
        return out
    }
}

final class RecordingSleeper: Sleeper, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var slept: [Double] = []
    func sleep(seconds: Double) async throws { lock.withLock { slept.append(seconds) } }
}

/// A clock tests can move by hand.
final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/SplarkKitTests/SlackClientTests.swift`:

```swift
import Foundation
import Testing
@testable import SplarkKit

@Suite struct SlackClientTests {
    @Test func postsFormWithBearerAndDecodesSnakeCase() async throws {
        let stub = StubTransport(json: #"{"ok":true,"user_id":"U1","user":"ivan","team_id":"T1","team":"Lumen","url":"https://lumen.slack.com/"}"#)
        let client = SlackClient(token: "xoxp-test", transport: stub, sleeper: RecordingSleeper())
        let me = try await client.authTest()
        #expect(me == SlackAuthTest(userId: "U1", user: "ivan", teamId: "T1", team: "Lumen", url: "https://lumen.slack.com/"))
        let request = stub.requests[0]
        #expect(request.url?.absoluteString == "https://slack.com/api/auth.test")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer xoxp-test")
    }

    @Test func okFalseBecomesApiError() async {
        let client = SlackClient(token: "x", transport: StubTransport(json: #"{"ok":false,"error":"invalid_auth"}"#), sleeper: RecordingSleeper())
        await #expect(throws: SlackError.api("invalid_auth")) { try await client.authTest() }
    }

    @Test func retriesAfter429UsingRetryAfter() async throws {
        let stub = StubTransport([
            .init(status: 429, body: "", headers: ["Retry-After": "7"]),
            .init(status: 200, body: #"{"ok":true,"user_id":"U1","team_id":"T1"}"#, headers: [:]),
        ])
        let sleeper = RecordingSleeper()
        let client = SlackClient(token: "x", transport: stub, sleeper: sleeper)
        _ = try await client.authTest()
        #expect(stub.requests.count == 2)
        #expect(sleeper.slept.contains { $0 >= 6.9 && $0 <= 7.1 })
    }

    @Test func givesUpAfterThree429s() async {
        let r = StubTransport.Reply(status: 429, body: "", headers: ["Retry-After": "1"])
        let client = SlackClient(token: "x", transport: StubTransport([r, r, r]), sleeper: RecordingSleeper())
        await #expect(throws: SlackError.rateLimited(retryAfter: 1)) { try await client.authTest() }
    }

    @Test func htmlErrorPageBecomesHTTPError() async {
        let stub = StubTransport([.init(status: 503, body: "<html>Service Unavailable</html>", headers: [:])])
        let client = SlackClient(token: "x", transport: stub, sleeper: RecordingSleeper())
        await #expect(throws: SlackError.http(503)) { try await client.authTest() }
    }

    @Test func missingRetryAfterWaitsThirtySeconds() async throws {
        let stub = StubTransport([
            .init(status: 429, body: "", headers: [:]),
            .init(status: 200, body: #"{"ok":true,"user_id":"U1","team_id":"T1"}"#, headers: [:]),
        ])
        let sleeper = RecordingSleeper()
        _ = try await SlackClient(token: "x", transport: stub, sleeper: sleeper).authTest()
        #expect(sleeper.slept.contains { abs($0 - 30) < 0.1 })
    }

    @Test func allConversationsFollowsCursors() async throws {
        let stub = StubTransport(json:
            #"{"ok":true,"channels":[{"id":"D1","is_im":true,"user":"U2"}],"response_metadata":{"next_cursor":"abc"}}"#,
            #"{"ok":true,"channels":[{"id":"C1","name":"eng","is_channel":true,"is_private":false}],"response_metadata":{"next_cursor":""}}"#)
        let all = try await SlackClient(token: "x", transport: stub, sleeper: RecordingSleeper()).allConversations()
        #expect(all.map(\.id) == ["D1", "C1"])
        #expect(all.map(\.kind) == [.im, .publicChannel])
        #expect(stub.formBody(1)["cursor"] == "abc")
        #expect(stub.formBody(0)["types"] == "public_channel,private_channel,mpim,im")
    }

    @Test func oauthExchangeSendsVerifierAndNoAuthHeader() async throws {
        let stub = StubTransport(json: #"{"ok":true,"app_id":"A1","authed_user":{"id":"U1","scope":"im:history","access_token":"xoxp-1","token_type":"user"},"team":{"id":"T1","name":"Lumen"}}"#)
        let r = try await SlackClient(token: nil, transport: stub, sleeper: RecordingSleeper())
            .oauthV2Access(clientId: "123.456", code: "c0de", redirectURI: "http://localhost:53682/slack/callback", codeVerifier: "v3r")
        #expect(r.authedUser.accessToken == "xoxp-1")
        #expect(r.team?.name == "Lumen")
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(stub.formBody(0) == ["client_id": "123.456", "code": "c0de", "redirect_uri": "http://localhost:53682/slack/callback", "code_verifier": "v3r"])
    }

    @Test func manifestCreateUsesConfigTokenAsBearer() async throws {
        let stub = StubTransport(json: #"{"ok":true,"app_id":"A9","credentials":{"client_id":"1.2","client_secret":"s"},"oauth_authorize_url":"https://slack.com/oauth/v2/authorize?client_id=1.2"}"#)
        let r = try await SlackClient(token: nil, transport: stub, sleeper: RecordingSleeper())
            .appsManifestCreate(configToken: "xoxe.xoxp-cfg", manifestJSON: #"{"a":1}"#)
        #expect(r.appId == "A9")
        #expect(r.credentials.clientId == "1.2")
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer xoxe.xoxp-cfg")
        #expect(stub.formBody(0)["manifest"] == #"{"a":1}"#)
    }
}

@Suite struct RateLimiterTests {
    @Test func allowsTierBudgetThenWaitsForOldestToExpire() async {
        let clock = ManualClock()
        let limiter = RateLimiter(now: { clock.now })
        for _ in 0..<20 { #expect(await limiter.reserve("search.messages", tier: .tier2) == 0) }
        clock.advance(10)
        let wait = await limiter.reserve("search.messages", tier: .tier2)
        #expect(abs(wait - 50) < 0.001)
        #expect(await limiter.reserve("auth.test", tier: .tier4) == 0)   // other methods unaffected
    }

    @Test func pauseDelaysNextCall() async {
        let clock = ManualClock()
        let limiter = RateLimiter(now: { clock.now })
        await limiter.pause("conversations.history", retryAfter: 30)
        #expect(await limiter.reserve("conversations.history", tier: .tier3) == 30)
    }
}
```

- [ ] **Step 3: Run them and watch them fail**

Run: `swift test --filter "SlackClientTests|RateLimiterTests"`
Expected: FAIL to compile with "cannot find type 'HTTPTransport' in scope".

- [ ] **Step 4: Implement the transport seam**

`Sources/SplarkKit/Support/HTTPTransport.swift`:

```swift
import Foundation

/// The one seam between Splark and the network, so every client can be tested with canned responses.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

public protocol Sleeper: Sendable {
    func sleep(seconds: Double) async throws
}

public struct TaskSleeper: Sleeper {
    public init() {}
    public func sleep(seconds: Double) async throws {
        if seconds > 0 { try await Task.sleep(for: .milliseconds(Int(seconds * 1000))) }
    }
}

extension URLRequest {
    /// POST with an application/x-www-form-urlencoded body, keys sorted for stable tests.
    static func form(_ url: URL, _ params: [String: String], bearer: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if let bearer, !bearer.isEmpty { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = Data(formEncode(params).utf8)
        return request
    }

    static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
    }
}
```

- [ ] **Step 5: Implement the rate limiter**

`Sources/SplarkKit/Slack/RateLimiter.swift`:

```swift
import Foundation

/// Slack's per-method rate-limit tiers (calls per minute).
public enum SlackTier: Sendable, Equatable {
    case tier1, tier2, tier3, tier4
    case perMinute(Int)

    public var callsPerMinute: Int {
        switch self {
        case .tier1: 1
        case .tier2: 20
        case .tier3: 50
        case .tier4: 100
        case .perMinute(let n): n
        }
    }
}

/// Sliding one-minute window per method. `reserve` returns how long to wait before calling.
public actor RateLimiter {
    private var calls: [String: [Date]] = [:]
    private var pausedUntil: [String: Date] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) { self.now = now }

    public func reserve(_ method: String, tier: SlackTier) -> TimeInterval {
        let current = now()
        var window = (calls[method] ?? []).filter { current.timeIntervalSince($0) < 60 }
        var start = max(current, pausedUntil[method] ?? current)
        if window.count >= tier.callsPerMinute, let oldest = window.first {
            start = max(start, oldest.addingTimeInterval(60))
        }
        window.append(start)
        calls[method] = window
        return start.timeIntervalSince(current)
    }

    /// Called on HTTP 429: no calls to `method` until `retryAfter` seconds from now.
    public func pause(_ method: String, retryAfter: TimeInterval) {
        pausedUntil[method] = now().addingTimeInterval(retryAfter)
    }
}
```

- [ ] **Step 6: Implement the client**

`Sources/SplarkKit/Slack/SlackClient.swift`:

```swift
import Foundation

public enum SlackError: Error, Equatable, Sendable {
    case api(String)                         // {"ok": false, "error": "..."}
    case rateLimited(retryAfter: TimeInterval)
    case http(Int)
    case decoding(String)
}

private struct SlackEnvelope: Decodable { let ok: Bool; let error: String? }

/// Typed access to the Slack Web API: form-encoded POSTs, Bearer token, per-method rate limiting,
/// `Retry-After` handling (two retries), and `ok: false` mapped to `SlackError.api`.
public struct SlackClient: Sendable {
    public let token: String?
    private let transport: HTTPTransport
    private let limiter: RateLimiter
    private let sleeper: Sleeper
    private let baseURL: URL

    public init(token: String?, transport: HTTPTransport = URLSessionTransport(), limiter: RateLimiter = RateLimiter(),
                sleeper: Sleeper = TaskSleeper(), baseURL: URL = URL(string: "https://slack.com/api/")!) {
        self.token = token
        self.transport = transport
        self.limiter = limiter
        self.sleeper = sleeper
        self.baseURL = baseURL
    }

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    public func call<Response: Decodable & Sendable>(_ method: String, tier: SlackTier, params: [String: String] = [:],
                                                    bearer: String? = nil, as: Response.Type = Response.self) async throws -> Response {
        let url = baseURL.appendingPathComponent(method)
        var attempt = 0
        while true {
            try await sleeper.sleep(seconds: await limiter.reserve(method, tier: tier))
            let (data, response) = try await transport.send(.form(url, params, bearer: bearer ?? token))
            if response.statusCode == 429 {
                let retryAfter = TimeInterval(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 30
                await limiter.pause(method, retryAfter: retryAfter)
                attempt += 1
                if attempt > 2 { throw SlackError.rateLimited(retryAfter: retryAfter) }
                continue
            }
            guard response.statusCode == 200 else { throw SlackError.http(response.statusCode) }
            let envelope: SlackEnvelope
            do { envelope = try Self.decoder.decode(SlackEnvelope.self, from: data) }
            catch { throw SlackError.decoding("\(method): \(error)") }
            guard envelope.ok else { throw SlackError.api(envelope.error ?? "unknown_error") }
            do { return try Self.decoder.decode(Response.self, from: data) }
            catch { throw SlackError.decoding("\(method): \(error)") }
        }
    }
}
```

- [ ] **Step 7: Implement the models and methods**

`Sources/SplarkKit/Slack/SlackModels.swift`:

```swift
import Foundation

public struct SlackAuthTest: Decodable, Sendable, Equatable {
    public let userId: String
    public let user: String?
    public let teamId: String
    public let team: String?
    public let url: String?
}

public struct SlackConversation: Decodable, Sendable, Equatable {
    public let id: String
    public let name: String?
    public let user: String?          // the other person, for IMs
    public let isIm: Bool?
    public let isMpim: Bool?
    public let isPrivate: Bool?
    public let isChannel: Bool?
    public let isArchived: Bool?
    public let lastRead: String?      // conversations.info only
    public let unreadCountDisplay: Int?  // conversations.info, DMs only

    public enum Kind: String, Sendable { case im, mpim, privateChannel, publicChannel }
    public var kind: Kind {
        if isIm == true { return .im }
        if isMpim == true { return .mpim }
        if isPrivate == true { return .privateChannel }
        return .publicChannel
    }
}

public struct SlackResponseMetadata: Decodable, Sendable, Equatable { public let nextCursor: String? }

public struct SlackConversationList: Decodable, Sendable { public let channels: [SlackConversation]; public let responseMetadata: SlackResponseMetadata? }
public struct SlackConversationInfo: Decodable, Sendable { public let channel: SlackConversation }

public struct SlackMessage: Decodable, Sendable, Equatable {
    public let ts: String
    public let user: String?
    public let botId: String?
    public let username: String?
    public let subtype: String?
    public let text: String?
    public let threadTs: String?
    public let replyCount: Int?
    public let latestReply: String?
    public let replyUsers: [String]?
}

public struct SlackHistory: Decodable, Sendable {
    public let messages: [SlackMessage]
    public let hasMore: Bool?
    public let responseMetadata: SlackResponseMetadata?
}

public struct SlackSearchResult: Decodable, Sendable {
    public struct Matches: Decodable, Sendable { public let total: Int?; public let matches: [Match] }
    public struct Match: Decodable, Sendable, Equatable {
        public struct Channel: Decodable, Sendable, Equatable { public let id: String; public let name: String? }
        public let channel: Channel
        public let ts: String
        public let user: String?
        public let text: String?
        public let permalink: String?
    }
    public let messages: Matches
}

public struct SlackManifestCreate: Decodable, Sendable {
    public struct Credentials: Decodable, Sendable { public let clientId: String; public let clientSecret: String? }
    public let appId: String
    public let credentials: Credentials
    public let oauthAuthorizeUrl: String?
}

public struct SlackOAuthAccess: Decodable, Sendable {
    public struct AuthedUser: Decodable, Sendable {
        public let id: String
        public let scope: String?
        public let accessToken: String?
        public let tokenType: String?
        public let refreshToken: String?
        public let expiresIn: Int?
    }
    public struct Team: Decodable, Sendable { public let id: String; public let name: String? }
    public let appId: String?
    public let authedUser: AuthedUser
    public let team: Team?
}
```

`Sources/SplarkKit/Slack/SlackClient+Methods.swift`:

```swift
import Foundation

/// The Slack methods Plan 1 needs (spec §6.2). Plan 2 adds the rest.
extension SlackClient {
    public func authTest() async throws -> SlackAuthTest {
        try await call("auth.test", tier: .tier4)
    }

    /// One page of the conversations the user is in.
    public func usersConversations(cursor: String? = nil) async throws -> SlackConversationList {
        var p = ["types": "public_channel,private_channel,mpim,im", "exclude_archived": "true", "limit": "200"]
        if let cursor { p["cursor"] = cursor }
        return try await call("users.conversations", tier: .tier3, params: p)
    }

    /// All pages of `usersConversations`.
    public func allConversations() async throws -> [SlackConversation] {
        var all: [SlackConversation] = []
        var cursor: String?
        repeat {
            let page = try await usersConversations(cursor: cursor)
            all += page.channels
            cursor = page.responseMetadata?.nextCursor
        } while !(cursor ?? "").isEmpty
        return all
    }

    public func conversationsInfo(_ channel: String) async throws -> SlackConversation {
        let r: SlackConversationInfo = try await call("conversations.info", tier: .tier3, params: ["channel": channel])
        return r.channel
    }

    /// Messages newer than `oldest` (exclusive), newest first, as Slack returns them.
    public func conversationsHistory(_ channel: String, oldest: String?, limit: Int) async throws -> SlackHistory {
        var p = ["channel": channel, "limit": String(limit)]
        if let oldest { p["oldest"] = oldest }
        return try await call("conversations.history", tier: .tier3, params: p)
    }

    public func searchMessages(_ query: String, count: Int = 20) async throws -> SlackSearchResult {
        try await call("search.messages", tier: .tier2, params: ["query": query, "sort": "timestamp", "sort_dir": "desc", "count": String(count)])
    }

    /// Creates an app from a manifest with an app configuration token (`xoxe.xoxp-…`).
    public func appsManifestCreate(configToken: String, manifestJSON: String) async throws -> SlackManifestCreate {
        try await call("apps.manifest.create", tier: .tier1, params: ["manifest": manifestJSON], bearer: configToken)
    }

    /// PKCE code exchange: no client secret, no bearer token.
    public func oauthV2Access(clientId: String, code: String, redirectURI: String, codeVerifier: String) async throws -> SlackOAuthAccess {
        try await call("oauth.v2.access", tier: .tier4,
                       params: ["client_id": clientId, "code": code, "redirect_uri": redirectURI, "code_verifier": codeVerifier],
                       bearer: "")
    }
}
```

- [ ] **Step 8: Run the tests and watch them pass**

Run: `swift test --filter "SlackClientTests|RateLimiterTests"`
Expected: PASS, 11 tests.

- [ ] **Step 9: Commit**

```bash
git add Sources/SplarkKit/Support Sources/SplarkKit/Slack Tests/SplarkKitTests/TestSupport.swift Tests/SplarkKitTests/SlackClientTests.swift
git commit -m "Add the Slack Web API client with per-method rate limits

Form-encoded POSTs with a Bearer token, ok:false mapped to typed
errors, 429 handled via Retry-After (30 s if absent, two retries),
5xx pages surfaced as HTTP errors, cursor pagination, and the PKCE
code exchange without a client secret."
```

---

### Task 8: The private Slack app manifest and authorize URL

**Files:**
- Create: `Sources/SplarkKit/Slack/SlackAppManifest.swift`
- Test: `Tests/SplarkKitTests/SlackAppManifestTests.swift`

**Interfaces:**
- Consumes: `PKCE` (Task 5).
- Produces: `enum SlackAppManifest`, with:
  - `userScopes` (16 entries), `redirectPorts` (`53682…53691`) and `callbackPath` (`"/slack/callback"`);
  - `redirectURI(port:)`, `json(redirectPort: UInt16?) -> String`, `createFromManifestURL() -> URL` and `authorizeURL(clientId:redirectPort:state:pkce:) -> URL`.

- [ ] **Step 1: Write the failing tests**

`Tests/SplarkKitTests/SlackAppManifestTests.swift`:

```swift
import Foundation
import Testing
@testable import SplarkKit

@Suite struct SlackAppManifestTests {
    private func object(_ json: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func pkceManifestHasRedirectScopesAndNoRotation() throws {
        let m = try object(SlackAppManifest.json(redirectPort: 53682))
        let oauth = try #require(m["oauth_config"] as? [String: Any])
        #expect(oauth["redirect_urls"] as? [String] == ["http://localhost:53682/slack/callback"])
        #expect(oauth["pkce_enabled"] as? Bool == true)
        let scopes = try #require((oauth["scopes"] as? [String: Any])?["user"] as? [String])
        #expect(scopes.count == 16)
        #expect(scopes.contains("search:read") && scopes.contains("mpim:write"))
        let settings = try #require(m["settings"] as? [String: Any])
        #expect(settings["token_rotation_enabled"] as? Bool == false)
        #expect((m["display_information"] as? [String: Any])?["name"] as? String == "Splark")
    }

    @Test func manualManifestHasNoRedirectOrPKCE() throws {
        let oauth = try #require(try object(SlackAppManifest.json(redirectPort: nil))["oauth_config"] as? [String: Any])
        #expect(oauth["redirect_urls"] == nil)
        #expect(oauth["pkce_enabled"] == nil)
    }

    @Test func authorizeURLCarriesPKCEAndUserScopes() throws {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = SlackAppManifest.authorizeURL(clientId: "1.2", redirectPort: 53683, state: "st", pkce: pkce)
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(url.host == "slack.com" && url.path == "/oauth/v2/authorize")
        #expect(items["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["redirect_uri"] == "http://localhost:53683/slack/callback")
        #expect(items["user_scope"]?.split(separator: ",").count == 16)
        #expect(items["scope"] == nil)
    }

    @Test func createFromManifestURLEmbedsManualManifest() throws {
        let url = SlackAppManifest.createFromManifestURL()
        let manifest = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "manifest_json" }?.value
        #expect(manifest == SlackAppManifest.json(redirectPort: nil))
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter SlackAppManifestTests`
Expected: FAIL to compile with "cannot find 'SlackAppManifest' in scope".

- [ ] **Step 3: Implement**

`Sources/SplarkKit/Slack/SlackAppManifest.swift`:

```swift
import Foundation

/// The private per-user Slack app (spec §6.1).
public enum SlackAppManifest {
    public static let userScopes = [
        "channels:history", "groups:history", "im:history", "mpim:history",
        "channels:read", "groups:read", "im:read", "mpim:read",
        "users:read", "search:read",
        "chat:write", "reactions:write",
        "channels:write", "groups:write", "im:write", "mpim:write",
    ]

    /// Redirect ports tried in order; the first free one is used and stored with the workspace.
    public static let redirectPorts: [UInt16] = Array(53682...53691)
    public static let callbackPath = "/slack/callback"

    public static func redirectURI(port: UInt16) -> String { "http://localhost:\(port)\(callbackPath)" }

    /// JSON for `apps.manifest.create`. `redirectPort == nil` gives the manual "create from manifest" variant.
    public static func json(redirectPort: UInt16?) -> String {
        var oauth: [String: Any] = ["scopes": ["user": userScopes]]
        if let redirectPort {
            oauth["redirect_urls"] = [redirectURI(port: redirectPort)]
            oauth["pkce_enabled"] = true
        }
        let manifest: [String: Any] = [
            "display_information": [
                "name": "Splark",
                "description": "Your private Splark connection. Created by the Splark menu-bar app for your account only.",
            ],
            "oauth_config": oauth,
            "settings": ["org_deploy_enabled": false, "socket_mode_enabled": false, "token_rotation_enabled": false],
        ]
        let data = try! JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// `https://api.slack.com/apps?new_app=1&manifest_json=…` for the manual fallback.
    public static func createFromManifestURL() -> URL {
        var c = URLComponents(string: "https://api.slack.com/apps")!
        c.queryItems = [URLQueryItem(name: "new_app", value: "1"), URLQueryItem(name: "manifest_json", value: json(redirectPort: nil))]
        return c.url!
    }

    public static func authorizeURL(clientId: String, redirectPort: UInt16, state: String, pkce: PKCE) -> URL {
        var c = URLComponents(string: "https://slack.com/oauth/v2/authorize")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "user_scope", value: userScopes.joined(separator: ",")),
            URLQueryItem(name: "redirect_uri", value: redirectURI(port: redirectPort)),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return c.url!
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test --filter SlackAppManifestTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SplarkKit/Slack/SlackAppManifest.swift Tests/SplarkKitTests/SlackAppManifestTests.swift
git commit -m "Describe the private Slack app and its PKCE authorize URL

The manifest carries the 16 user scopes, a localhost redirect, PKCE
on and token rotation off. A redirect-less variant backs the manual
create-from-manifest fallback."
```

---

### Task 9: Slack spike: connect a real workspace and probe it (human in the loop)

The controller (the main session) runs this task, not a subagent, because it needs the human to generate a token and click Allow.

**Files:**
- Create: `Sources/splark-dev/SlackCommands.swift`
- Modify: `Sources/splark-dev/main.swift` (replace the whole file), `docs/spikes.md` (append)

**Interfaces:**
- Consumes: `SlackClient` and its methods (Task 7), `SlackAppManifest` (Task 8), `LoopbackServer` and `PKCE` (Task 5), `KeychainStore` (Task 6).
- Produces:
  - The dev-tool globals `store` (`KeychainStore(service: "dev.splark.dev")`), `slackConnectCommand()` and `slackProbeCommand()`.
  - Keychain items `slack.<TEAM_ID>` (the user token) and `slack.last` (the last team ID), under the service `dev.splark.dev`.

- [ ] **Step 1: Add the Slack commands**

`Sources/splark-dev/SlackCommands.swift`:

```swift
import Foundation
import SplarkKit

/// Dev-tool secrets live under their own Keychain service, separate from the app's "dev.splark.Splark".
let store = KeychainStore(service: "dev.splark.dev")

func slackConnectCommand() async throws {
    if let userToken = option("--user-token") {
        let me = try await SlackClient(token: userToken).authTest()
        try store.write(userToken, for: "slack.\(me.teamId)")
        try store.write(me.teamId, for: "slack.last")
        print("Stored user token \(mask(userToken)) for \(me.team ?? me.teamId) as \(me.user ?? me.userId).")
        return
    }
    guard let configToken = option("--config-token") else { fail("pass --config-token xoxe.xoxp-… (or --user-token xoxp-…)") }
    var server: LoopbackServer?
    var port: UInt16 = 0
    for candidate in SlackAppManifest.redirectPorts {
        if let s = try? LoopbackServer(port: candidate, path: SlackAppManifest.callbackPath) { server = s; port = candidate; break }
    }
    guard let server else { fail("no free port in \(SlackAppManifest.redirectPorts)") }
    let slack = SlackClient(token: nil)
    print("1/3 Creating your private Slack app (redirect port \(port))…")
    let created = try await slack.appsManifestCreate(configToken: configToken, manifestJSON: SlackAppManifest.json(redirectPort: port))
    print("    app \(created.appId), client \(created.credentials.clientId)")
    let pkce = PKCE.random(), state = PKCE.randomURLSafeString(byteCount: 16)
    let authorize = SlackAppManifest.authorizeURL(clientId: created.credentials.clientId, redirectPort: port, state: state, pkce: pkce)
    print("2/3 Opening Slack. Click Allow… (\(authorize.absoluteString.prefix(80))…)")
    openInBrowser(authorize)
    let callback = try await server.waitForCallback()
    guard callback.query["state"] == state else { fail("state mismatch") }
    if let error = callback.query["error"] { fail("Slack returned \(error)") }
    guard let code = callback.query["code"] else { fail("no code in callback: \(callback.query)") }
    print("3/3 Exchanging the code (PKCE, no client secret)…")
    let access = try await slack.oauthV2Access(clientId: created.credentials.clientId, code: code,
                                               redirectURI: SlackAppManifest.redirectURI(port: port), codeVerifier: pkce.verifier)
    guard let token = access.authedUser.accessToken, let team = access.team else { fail("no user token in response") }
    try store.write(token, for: "slack.\(team.id)")
    try store.write(team.id, for: "slack.last")
    print("""
    Connected \(team.name ?? team.id) as \(access.authedUser.id).
      token: \(mask(token)) (type \(access.authedUser.tokenType ?? "?"))
      refresh token: \(access.authedUser.refreshToken == nil ? "none" : "present") · expires_in: \(access.authedUser.expiresIn.map(String.init) ?? "none")
      scopes: \(access.authedUser.scope ?? "?")
    """)
}

func slackProbeCommand() async throws {
    guard let team = try option("--team") ?? store.read("slack.last"), let token = try store.read("slack.\(team)") else {
        fail("no stored Slack token; run slack-connect first")
    }
    let slack = SlackClient(token: token)
    let me = try await slack.authTest()
    print("auth.test: \(me.user ?? me.userId) @ \(me.team ?? me.teamId)")

    let started = Date()
    let all = try await slack.allConversations()
    let byKind = Dictionary(grouping: all, by: \.kind).mapValues(\.count)
    print("users.conversations: \(all.count) in \(String(format: "%.1f", Date().timeIntervalSince(started))) s · \(byKind)")

    let sample = Array(all.filter { $0.kind == .im }.prefix(5)) + Array(all.filter { $0.kind != .im }.prefix(5))
    for conversation in sample {
        let info = try await slack.conversationsInfo(conversation.id)
        let unread = try await slack.conversationsHistory(conversation.id, oldest: info.lastRead, limit: 40).messages.count
        print("  \(conversation.kind) \(info.name ?? conversation.id): last_read=\(info.lastRead ?? "nil") unread_count_display=\(info.unreadCountDisplay.map(String.init) ?? "nil") unread_fetched=\(unread)")
    }

    if let busy = all.first(where: { $0.kind == .publicChannel }) {
        let page = try await slack.conversationsHistory(busy.id, oldest: nil, limit: 100)
        print("clamp check on \(busy.name ?? busy.id): asked 100, got \(page.messages.count), has_more=\(page.hasMore ?? false)")
        let t = Date()
        for _ in 0..<3 { _ = try await slack.conversationsHistory(busy.id, oldest: nil, limit: 5) }
        print("3 more history calls took \(String(format: "%.1f", Date().timeIntervalSince(t))) s (≈60 s+ means the 1/min clamp applies)")
    }

    for query in ["<@\(me.userId)>", "@\(me.user ?? me.userId)"] {
        let result = try await slack.searchMessages(query, count: 5)
        print("search.messages \(query): total=\(result.messages.total ?? -1) sample=\(result.messages.matches.map { $0.channel.name ?? $0.channel.id })")
    }
}
```

`Sources/splark-dev/main.swift`:

```swift
import Foundation
import SplarkKit

// splark-dev: developer commands that exercise SplarkKit against real accounts (spec §13 spikes).

let usage = """
usage: splark-dev <command>
  badge [--seconds N]                 watch Slack's Dock badge
  slack-connect --config-token T      create your private Slack app and connect it (or --user-token xoxp-…)
  slack-probe [--team T…]             run the Slack spike checks against the connected workspace
  slack-manifest-url                  print the manual "create from manifest" link (fallback)
"""

do {
    switch args.first {
    case "badge": await badgeCommand()
    case "slack-connect": try await slackConnectCommand()
    case "slack-probe": try await slackProbeCommand()
    case "slack-manifest-url": print(SlackAppManifest.createFromManifestURL())
    default: print(usage)
    }
} catch {
    fail("\(error)")
}
```

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 2: Spike 1. Create and authorise the private app (needs the human)**

1. Ask the human to open https://api.slack.com/apps. Under **Your App Configuration Tokens** at the bottom, they click **Generate Token**, pick the workspace, and copy the **Access Token** (`xoxe.xoxp-…`).
2. Run: `swift run splark-dev slack-connect --config-token '<pasted token>'`
3. The browser opens Slack's authorize page. Ask the human to click **Allow**.
4. Expected output: `Connected <workspace> as U…`, with `refresh token: none · expires_in: none` and the 16 scopes.
5. **If `apps.manifest.create` or the authorise step fails:** record the error text. Then try the manual fallback:
   1. Run `swift run splark-dev slack-manifest-url` and open the printed link.
   2. Create the app, then click **Install to Workspace**.
   3. Run `swift run splark-dev slack-connect --user-token xoxp-…` with the **User OAuth Token** from *OAuth & Permissions*.

- [ ] **Step 3: Spikes 4 and 5. Probe the workspace**

Run: `swift run splark-dev slack-probe`

Expected:
- `auth.test` succeeds.
- `users.conversations` counts conversations by kind.
- Sample DMs show `last_read` and `unread_count_display`; sample channels show `last_read`.
- The clamp check reports `asked 100, got N` with N above 15 if the channel has more than 15 messages, and the three extra history calls take well under 60 s.
- The two `search.messages` lines report totals.

- [ ] **Step 4: Record the results**

Append to `docs/spikes.md`:

```markdown
## 1. Private Slack app with PKCE

- apps.manifest.create with pkce_enabled + localhost redirect: (worked / error text)
- Authorize + oauth.v2.access without client secret: (worked / error text)
- Token: (xoxp…, rotation: refresh token present? expires_in?)
- **Decision:** (one of: "config-token flow works as specified" / "manual-token fallback becomes the main path" / other, with reason)

## 4. Mention sweep

- `search.messages "<@U…>"` total: (n) · `"@name"` total: (n)
- **Decision:** (which query Plan 2 uses, or drop the sweep)

## 5. Internal-app rate limits

- History asked 100, got: (n), has_more: (bool)
- 3 rapid history calls took: (s)
- users.conversations: (count) conversations in (s)
- **Decision:** (one of: "normal Tier 3 limits — spec schedule stands" / "clamped — redesign needed")
```

- [ ] **Step 5: Commit**

```bash
git add Sources/splark-dev docs/spikes.md
git commit -m "Prove the private Slack app flow against a real workspace

splark-dev slack-connect creates the per-user app from a config
token and completes PKCE in the browser; slack-probe checks read
state, history limits and mention search. Results in docs/spikes.md."
```

---

### Task 10: Sign in with ChatGPT and the Responses API client

**Files:**
- Create: `Sources/SplarkKit/ChatGPT/ChatGPTAuth.swift`, `Sources/SplarkKit/ChatGPT/OpenAIResponses.swift`
- Test: `Tests/SplarkKitTests/ChatGPTTests.swift`

**Interfaces:**
- Consumes: `HTTPTransport`, `URLRequest.form` (Task 7); `PKCE` (Task 5); the `StubTransport` test double (Task 7).
- Produces:
  - **Credentials:** `struct ChatGPTCredentials: Codable`, with `clientId`, `hostId`, `accessToken`, `refreshToken`, `idToken`, `expiresAt`, `scopes`, `email` and `subject`, plus `canUsePlan` and `needsRefresh(now:)`.
  - **Auth:** `enum ChatGPTAuthError { stateMismatch, missingCode, http(Int, String), decoding(String) }`. `struct ChatGPTAuth(transport:now:)`, with:
    - `static authorizeURL(clientId:hostId:port:state:nonce:pkce:loginHint:)` and `static redirectURI(port:)`;
    - `exchange(callback:expectedState:pkce:port:hostId:priorClientId:)` and `refresh(_:)`;
    - `static claims(fromJWT:)` and `static let secretKey = "chatgpt"`.
  - **Responses:** `struct ResponseStreamParser`, with `feed(_:)`, `text`, `completed` and `failure`. `enum OpenAIError { http(Int, String), stream(String), incomplete }`. `struct OpenAIClient`, with `listModels(accessToken:)`, `respond(accessToken:model:instructions:input:schemaName:schema:)` and `static responsesBody(...)`.

- [ ] **Step 1: Write the failing tests**

`Tests/SplarkKitTests/ChatGPTTests.swift`:

```swift
import Foundation
import Testing
@testable import SplarkKit

@Suite struct ChatGPTAuthTests {
    private func query(_ url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    @Test func firstSignInUsesDynamicClientAndAgentName() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = ChatGPTAuth.authorizeURL(clientId: nil, hostId: "host-1", port: 50111, state: "s", nonce: "n", pkce: pkce)
        let q = query(url)
        #expect(url.absoluteString.hasPrefix("https://auth.openai.com/api/accounts/authorize?"))
        #expect(q["client_id"] == "dynamic_agent_client")
        #expect(q["agent_name_hint"] == "Splark")
        #expect(q["redirect_uri"] == "http://127.0.0.1:50111/callback")
        #expect(q["scope"] == "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct")
        #expect(q["resource"] == "https://api.openai.com/v1")
        #expect(q["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(q["ext_agent_host_id"] == "host-1")
    }

    @Test func reauthorizationUsesIssuedClientAndOmitsAgentName() {
        let q = query(ChatGPTAuth.authorizeURL(clientId: "oaiapp_123", hostId: "h", port: 1, state: "s", nonce: "n", pkce: .random()))
        #expect(q["client_id"] == "oaiapp_123")
        #expect(q["agent_name_hint"] == nil)
    }

    @Test func exchangeChecksStateAndReadsIssuedClientId() async throws {
        let idToken = "x." + Data(#"{"sub":"user-1","email":"ivan@lumen.dev"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "") + ".y"
        let stub = StubTransport(json: #"{"access_token":"at","refresh_token":"rt","id_token":"\#(idToken)","expires_in":3600,"scope":"openid chatgpt.tokens.use.direct"}"#)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let auth = ChatGPTAuth(transport: stub, now: { start })
        let pkce = PKCE(verifier: "v")
        await #expect(throws: ChatGPTAuthError.stateMismatch) {
            try await auth.exchange(callback: ["code": "c", "state": "wrong"], expectedState: "s", pkce: pkce, port: 9, hostId: "h", priorClientId: nil)
        }
        let creds = try await auth.exchange(callback: ["code": "c", "state": "s", "client_id": "oaiapp_9"], expectedState: "s", pkce: pkce, port: 9, hostId: "h", priorClientId: nil)
        #expect(creds.clientId == "oaiapp_9")
        #expect(creds.email == "ivan@lumen.dev" && creds.subject == "user-1")
        #expect(creds.canUsePlan)
        #expect(creds.expiresAt == start.addingTimeInterval(3600))
        #expect(stub.formBody(0)["client_id"] == "oaiapp_9")
        #expect(stub.formBody(0)["code_verifier"] == "v")
        #expect(stub.formBody(0)["redirect_uri"] == "http://127.0.0.1:9/callback")
    }

    @Test func cancelledSignInNeverCallsTheTokenEndpoint() async {
        let stub = StubTransport(json: #"{"access_token":"should-not-be-used"}"#)
        let auth = ChatGPTAuth(transport: stub)
        await #expect(throws: ChatGPTAuthError.missingCode) {
            try await auth.exchange(callback: ["error": "access_denied", "state": "s"], expectedState: "s", pkce: .random(), port: 1, hostId: "h", priorClientId: nil)
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func refreshKeepsOldRefreshTokenWhenNoneReturned() async throws {
        let stub = StubTransport(json: #"{"access_token":"at2","expires_in":60}"#)
        let start = Date(timeIntervalSince1970: 0)
        let old = ChatGPTCredentials(clientId: "oaiapp_1", hostId: "h", accessToken: "at1", refreshToken: "rt1", idToken: nil,
                                     expiresAt: start, scopes: ["chatgpt.tokens.use.direct"], email: nil, subject: nil)
        let new = try await ChatGPTAuth(transport: stub, now: { start }).refresh(old)
        #expect(new.accessToken == "at2" && new.refreshToken == "rt1")
        #expect(new.needsRefresh(now: start))   // expires in 60 s < 5 min
        #expect(stub.formBody(0)["grant_type"] == "refresh_token")
    }
}

@Suite struct OpenAIResponsesTests {
    @Test func parserAccumulatesDeltasAcrossArbitraryChunks() {
        let stream = """
        event: response.created
        data: {"type":"response.created"}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"{\\"items\\":"}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"[]}"}

        event: response.completed
        data: {"type":"response.completed","response":{"status":"completed"}}

        """
        var parser = ResponseStreamParser()
        var index = stream.startIndex
        while index < stream.endIndex {
            let next = stream.index(index, offsetBy: 7, limitedBy: stream.endIndex) ?? stream.endIndex
            parser.feed(String(stream[index..<next]))
            index = next
        }
        #expect(parser.text == #"{"items":[]}"#)
        #expect(parser.completed && parser.failure == nil)
    }

    @Test func parserCapturesFailure() {
        var parser = ResponseStreamParser()
        parser.feed(#"data: {"type":"response.failed","response":{"error":{"message":"usage limit reached"}}}"# + "\n")
        #expect(parser.failure == "usage limit reached")
    }

    @Test func bodyAlwaysStreamsWithStorageOff() throws {
        let data = OpenAIClient.responsesBody(model: "m", instructions: "i", input: "x", schemaName: "triage", schema: ["type": "object"])
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["stream"] as? Bool == true && body["store"] as? Bool == false)
        #expect(body["instructions"] as? String == "i")
        #expect(body["temperature"] == nil && body["max_output_tokens"] == nil)
        let format = try #require(((body["text"] as? [String: Any])?["format"]) as? [String: Any])
        #expect(format["type"] as? String == "json_schema" && format["strict"] as? Bool == true)
    }

    @Test func listModelsSortsIds() async throws {
        let stub = StubTransport(json: #"{"object":"list","data":[{"id":"gpt-b"},{"id":"gpt-a"}]}"#)
        #expect(try await OpenAIClient(transport: stub).listModels(accessToken: "t") == ["gpt-a", "gpt-b"])
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer t")
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter "ChatGPTAuthTests|OpenAIResponsesTests"`
Expected: FAIL to compile with "cannot find 'ChatGPTAuth' in scope".

- [ ] **Step 3: Implement sign-in**

`Sources/SplarkKit/ChatGPT/ChatGPTAuth.swift`:

```swift
import Foundation

/// Stored after "Sign in with ChatGPT" (spec §7.1). Persisted as JSON in the SecretStore under `ChatGPTAuth.secretKey`.
public struct ChatGPTCredentials: Codable, Sendable, Equatable {
    public var clientId: String          // "oaiapp_…" once issued
    public var hostId: String            // ext_agent_host_id, stable per Mac
    public var accessToken: String
    public var refreshToken: String?
    public var idToken: String?
    public var expiresAt: Date
    public var scopes: [String]
    public var email: String?
    public var subject: String?

    public var canUsePlan: Bool { scopes.contains("chatgpt.tokens.use.direct") }
    public func needsRefresh(now: Date) -> Bool { expiresAt.timeIntervalSince(now) < 300 }
}

public enum ChatGPTAuthError: Error, Equatable { case stateMismatch, missingCode, http(Int, String), decoding(String) }

public struct ChatGPTAuth: Sendable {
    public static let authorizeEndpoint = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    public static let tokenEndpoint = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    public static let dynamicClientId = "dynamic_agent_client"
    public static let agentName = "Splark"
    public static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    public static let resource = "https://api.openai.com/v1"
    public static let secretKey = "chatgpt"

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let transport: HTTPTransport
    private let now: @Sendable () -> Date
    public init(transport: HTTPTransport = URLSessionTransport(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.now = now
    }

    public static func redirectURI(port: UInt16) -> String { "http://127.0.0.1:\(port)/callback" }

    /// `clientId == nil` means first sign-in (dynamic registration).
    public static func authorizeURL(clientId: String?, hostId: String, port: UInt16, state: String, nonce: String, pkce: PKCE, loginHint: String? = nil) -> URL {
        var items = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId ?? dynamicClientId),
            URLQueryItem(name: "ext_agent_host_id", value: hostId),
            URLQueryItem(name: "redirect_uri", value: redirectURI(port: port)),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        if clientId == nil { items.append(URLQueryItem(name: "agent_name_hint", value: agentName)) }
        if let loginHint { items.append(URLQueryItem(name: "login_hint", value: loginHint)) }
        var c = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = items
        return c.url!
    }

    struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?
        let expiresIn: Double?
        let scope: String?
    }

    /// Exchanges the callback for credentials. The callback may carry the newly issued `client_id`.
    public func exchange(callback: [String: String], expectedState: String, pkce: PKCE, port: UInt16, hostId: String, priorClientId: String?) async throws -> ChatGPTCredentials {
        guard callback["state"] == expectedState else { throw ChatGPTAuthError.stateMismatch }
        guard let code = callback["code"], !code.isEmpty else { throw ChatGPTAuthError.missingCode }
        let clientId = callback["client_id"] ?? priorClientId ?? Self.dynamicClientId
        let token = try await tokenRequest([
            "grant_type": "authorization_code", "code": code, "client_id": clientId,
            "code_verifier": pkce.verifier, "redirect_uri": Self.redirectURI(port: port), "resource": Self.resource,
        ])
        let claims = token.idToken.flatMap(Self.claims(fromJWT:)) ?? [:]
        return ChatGPTCredentials(
            clientId: clientId, hostId: hostId, accessToken: token.accessToken, refreshToken: token.refreshToken,
            idToken: token.idToken, expiresAt: now().addingTimeInterval(token.expiresIn ?? 3600),
            scopes: (token.scope ?? "").split(separator: " ").map(String.init),
            email: claims["email"] as? String, subject: claims["sub"] as? String)
    }

    public func refresh(_ credentials: ChatGPTCredentials) async throws -> ChatGPTCredentials {
        guard let refreshToken = credentials.refreshToken else { throw ChatGPTAuthError.missingCode }
        let token = try await tokenRequest([
            "grant_type": "refresh_token", "refresh_token": refreshToken,
            "client_id": credentials.clientId, "resource": Self.resource,
        ])
        var updated = credentials
        updated.accessToken = token.accessToken
        updated.refreshToken = token.refreshToken ?? refreshToken
        updated.idToken = token.idToken ?? credentials.idToken
        updated.expiresAt = now().addingTimeInterval(token.expiresIn ?? 3600)
        if let scope = token.scope { updated.scopes = scope.split(separator: " ").map(String.init) }
        return updated
    }

    private func tokenRequest(_ params: [String: String]) async throws -> TokenResponse {
        let (data, response) = try await transport.send(.form(Self.tokenEndpoint, params))
        guard response.statusCode == 200 else { throw ChatGPTAuthError.http(response.statusCode, String(decoding: data, as: UTF8.self)) }
        do { return try Self.decoder.decode(TokenResponse.self, from: data) }
        catch { throw ChatGPTAuthError.decoding("\(error)") }
    }

    /// Reads (does not verify) the JWT payload; used only for display (email) and identity (sub).
    public static func claims(fromJWT jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
```

- [ ] **Step 4: Implement the Responses client**

`Sources/SplarkKit/ChatGPT/OpenAIResponses.swift`:

```swift
import Foundation

/// Accumulates a streamed Responses API reply (server-sent events).
public struct ResponseStreamParser: Sendable {
    public private(set) var text = ""
    public private(set) var completed = false
    public private(set) var failure: String?
    private var buffer = ""

    public init() {}

    /// Feed raw bytes as they arrive (any chunking).
    public mutating func feed(_ chunk: String) {
        buffer += chunk
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            buffer.removeSubrange(..<range.upperBound)
            handle(line: line)
        }
    }

    private mutating func handle(line: String) {
        guard line.hasPrefix("data:") else { return }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", let data = payload.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }
        switch type {
        case "response.output_text.delta": text += event["delta"] as? String ?? ""
        case "response.completed": completed = true
        case "response.failed", "error":
            let error = (event["response"] as? [String: Any])?["error"] as? [String: Any] ?? event["error"] as? [String: Any] ?? event
            failure = (error["message"] as? String) ?? "\(error)"
        default: break
        }
    }
}

public enum OpenAIError: Error, Equatable { case http(Int, String), stream(String), incomplete }

/// Minimal client for the endpoints Splark uses with ChatGPT-plan tokens (spec §7.2).
public struct OpenAIClient: Sendable {
    public static let baseURL = URL(string: "https://api.openai.com/v1/")!
    private let transport: HTTPTransport
    private let streamer: @Sendable (URLRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse)

    public init(transport: HTTPTransport = URLSessionTransport(),
                streamer: @escaping @Sendable (URLRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) = { request in
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    return (bytes, response as! HTTPURLResponse)
                }) {
        self.transport = transport
        self.streamer = streamer
    }

    public func listModels(accessToken: String) async throws -> [String] {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("models"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else { throw OpenAIError.http(response.statusCode, String(decoding: data, as: UTF8.self)) }
        struct List: Decodable { struct Model: Decodable { let id: String }; let data: [Model] }
        return try JSONDecoder().decode(List.self, from: data).data.map(\.id).sorted()
    }

    /// The request body: always `stream: true`, `store: false`, instructions (never a system message).
    public static func responsesBody(model: String, instructions: String, input: String, schemaName: String?, schema: [String: Any]?) -> Data {
        var body: [String: Any] = ["model": model, "instructions": instructions, "input": input, "stream": true, "store": false]
        if let schemaName, let schema {
            body["text"] = ["format": ["type": "json_schema", "name": schemaName, "schema": schema, "strict": true]]
        }
        return try! JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    public func respond(accessToken: String, model: String, instructions: String, input: String,
                        schemaName: String? = nil, schema: [String: Any]? = nil) async throws -> String {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("responses"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = Self.responsesBody(model: model, instructions: instructions, input: input, schemaName: schemaName, schema: schema)
        let (bytes, response) = try await streamer(request)
        var parser = ResponseStreamParser()
        var raw = ""
        for try await line in bytes.lines {
            raw += line + "\n"
            parser.feed(line + "\n")
        }
        guard response.statusCode == 200 else { throw OpenAIError.http(response.statusCode, String(raw.prefix(2000))) }
        if let failure = parser.failure { throw OpenAIError.stream(failure) }
        guard parser.completed else { throw OpenAIError.incomplete }
        return parser.text
    }
}
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `swift test --filter "ChatGPTAuthTests|OpenAIResponsesTests"`
Expected: PASS, 9 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/SplarkKit/ChatGPT Tests/SplarkKitTests/ChatGPTTests.swift
git commit -m "Add Sign in with ChatGPT and a streaming Responses client

Dynamic client registration on first sign-in, PKCE, state check,
refresh that keeps the old refresh token, and a Responses client
that always streams with storage off and parses SSE across chunks."
```

---

### Task 11: ChatGPT spike: sign in and send one structured request (human in the loop)

The controller runs this task, not a subagent: the human signs in in the browser.

**Files:**
- Create: `Sources/splark-dev/ChatGPTCommands.swift`
- Modify: `Sources/splark-dev/main.swift` (replace the whole file), `docs/spikes.md` (append)

**Interfaces:**
- Consumes: `ChatGPTAuth`, `ChatGPTCredentials`, `OpenAIClient` (Task 10); `LoopbackServer`, `PKCE` (Task 5); `store` (Task 9).
- Produces: `chatgptLoginCommand()` and `chatgptProbeCommand()`; the Keychain item `chatgpt` (credentials JSON) under the service `dev.splark.dev`.

- [ ] **Step 1: Add the ChatGPT commands**

`Sources/splark-dev/ChatGPTCommands.swift`:

```swift
import Foundation
import SplarkKit

func chatgptLoginCommand() async throws {
    var prior: ChatGPTCredentials?
    if let json = try store.read(ChatGPTAuth.secretKey) { prior = try? JSONDecoder().decode(ChatGPTCredentials.self, from: Data(json.utf8)) }
    let hostId = prior?.hostId ?? UUID().uuidString
    let server = try LoopbackServer(port: 0, path: "/callback", ipv4Only: true)
    let pkce = PKCE.random(), state = PKCE.randomURLSafeString(byteCount: 16), nonce = PKCE.randomURLSafeString(byteCount: 16)
    let url = ChatGPTAuth.authorizeURL(clientId: prior?.clientId, hostId: hostId, port: server.port, state: state, nonce: nonce, pkce: pkce, loginHint: prior?.email)
    print("Opening ChatGPT sign-in (port \(server.port))…")
    openInBrowser(url)
    let callback = try await server.waitForCallback()
    print("callback keys: \(callback.query.keys.sorted())")
    if let error = callback.query["error"] { fail("OpenAI returned \(error): \(callback.query["error_description"] ?? "")") }
    let creds = try await ChatGPTAuth().exchange(callback: callback.query, expectedState: state, pkce: pkce, port: server.port, hostId: hostId, priorClientId: prior?.clientId)
    let json = String(decoding: try JSONEncoder().encode(creds), as: UTF8.self)
    try store.write(json, for: ChatGPTAuth.secretKey)
    print("""
    Signed in as \(creds.email ?? "?") (sub \(creds.subject ?? "?")).
      client_id: \(creds.clientId)
      can use ChatGPT plan: \(creds.canUsePlan) · scopes: \(creds.scopes.joined(separator: " "))
      access token expires: \(creds.expiresAt.formatted()) · refresh token: \(creds.refreshToken == nil ? "none" : "present")
    """)
}

func chatgptProbeCommand() async throws {
    guard let json = try store.read(ChatGPTAuth.secretKey) else { fail("not signed in; run chatgpt-login first") }
    var creds = try JSONDecoder().decode(ChatGPTCredentials.self, from: Data(json.utf8))
    if creds.needsRefresh(now: Date()) {
        creds = try await ChatGPTAuth().refresh(creds)
        try store.write(String(decoding: try JSONEncoder().encode(creds), as: UTF8.self), for: ChatGPTAuth.secretKey)
        print("refreshed access token")
    }
    let client = OpenAIClient()
    let models = try await client.listModels(accessToken: creds.accessToken)
    print("models (\(models.count)): \(models.joined(separator: ", "))")
    guard let model = option("--model") ?? models.first(where: { $0.contains("nano") }) ?? models.first(where: { $0.contains("mini") }) ?? models.first else { fail("no models") }
    let schema: [String: Any] = [
        "type": "object", "additionalProperties": false, "required": ["level", "lead"],
        "properties": ["level": ["type": "string", "enum": ["action", "question", "fyi"]], "lead": ["type": "string"]],
    ]
    let input = "DM from Marta Ruiz: can you approve the rollback now? checkout is failing for EU cards"
    let instructions = "Classify the Slack message for the reader. Reply with JSON only."
    for (label, useSchema) in [("json_schema", true), ("plain", false)] {
        let t = Date()
        do {
            let text = try await client.respond(accessToken: creds.accessToken, model: model, instructions: instructions, input: input,
                                                schemaName: useSchema ? "triage" : nil, schema: useSchema ? schema : nil)
            print("\(label) with \(model) in \(String(format: "%.1f", Date().timeIntervalSince(t))) s: \(text)")
        } catch {
            print("\(label) with \(model) FAILED: \(error)")
        }
    }
}
```

`Sources/splark-dev/main.swift`:

```swift
import Foundation
import SplarkKit

// splark-dev: developer commands that exercise SplarkKit against real accounts (spec §13 spikes).

let usage = """
usage: splark-dev <command>
  badge [--seconds N]                 watch Slack's Dock badge
  slack-connect --config-token T      create your private Slack app and connect it (or --user-token xoxp-…)
  slack-probe [--team T…]             run the Slack spike checks against the connected workspace
  slack-manifest-url                  print the manual "create from manifest" link (fallback)
  chatgpt-login                       Sign in with ChatGPT
  chatgpt-probe [--model M]           list models and send a tiny structured request
"""

do {
    switch args.first {
    case "badge": await badgeCommand()
    case "slack-connect": try await slackConnectCommand()
    case "slack-probe": try await slackProbeCommand()
    case "slack-manifest-url": print(SlackAppManifest.createFromManifestURL())
    case "chatgpt-login": try await chatgptLoginCommand()
    case "chatgpt-probe": try await chatgptProbeCommand()
    default: print(usage)
    }
} catch {
    fail("\(error)")
}
```

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 2: Spike 3. Sign in (needs the human)**

1. Run: `swift run splark-dev chatgpt-login`
2. Ask the human to sign in and approve Splark in the browser.
3. Expected: `callback keys: [...]` (record whether `client_id` is among them), `Signed in as …`, `client_id: oaiapp_…`, `can use ChatGPT plan: true`, and `refresh token: present`.
4. If the authorize page shows an error, record its exact text and the query parameters that were sent.

- [ ] **Step 3: Probe models and structured output**

Run: `swift run splark-dev chatgpt-probe`
Expected:
- The model list prints.
- The `json_schema` line returns JSON with `level` (most likely `action`) and `lead`.
- The `plain` line returns JSON too.
- If `json_schema` fails, record the error; Plan 2 then uses JSON-only prompting (spec §7.2).

- [ ] **Step 4: Record the results**

Append to `docs/spikes.md`:

```markdown
## 3. Sign in with ChatGPT

- Dynamic registration (`client_id=dynamic_agent_client`): (worked / error text)
- Callback query keys: (list) · issued client_id came from: (callback / token response / not issued)
- Granted scopes include chatgpt.tokens.use.direct: (yes/no) · plan: (Plus/Pro)
- Models available: (list)
- json_schema output: (worked in N s / error text) · plain JSON: (worked in N s / error text)
- **Decision:** (default model for triage; whether Plan 2 uses json_schema or JSON-only prompting)
```

- [ ] **Step 5: Commit**

```bash
git add Sources/splark-dev docs/spikes.md
git commit -m "Prove Sign in with ChatGPT and structured output

splark-dev chatgpt-login signs in via dynamic client registration and
PKCE; chatgpt-probe lists models and sends one triage-shaped request
with and without a JSON schema. Results in docs/spikes.md."
```

---

### Task 12: Wrap-up: README, push, CI

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add a development section to the README**

Insert before `## Credits`:

~~~markdown
## Development

Requirements: macOS 14+, Xcode 16 or newer (Swift 6).

```bash
swift test                          # all unit tests
./scripts/build-app.sh debug        # builds build/Splark.app (ad-hoc signed)
open build/Splark.app
swift run splark-dev                # developer commands: badge, slack-connect, slack-probe, chatgpt-login, chatgpt-probe
```

`splark-dev` keeps its tokens in the Keychain under the service `dev.splark.dev`, separate from the app. What the integration spikes found is in [`docs/spikes.md`](docs/spikes.md).
~~~

- [ ] **Step 2: Run everything one last time**

Run: `swift test && ./scripts/build-app.sh release`
Expected: all tests pass (about 45), and the script prints `build/Splark.app`.

- [ ] **Step 3: Commit and push**

```bash
git add README.md
git commit -m "Document how to build, test and run the dev tool"
git log -1 --format=%ae   # must print ivliag@gmail.com
git push origin main
```

- [ ] **Step 4: Check CI**

Run: `gh run watch --repo ivliag/splark --exit-status $(gh run list --repo ivliag/splark --limit 1 --json databaseId --jq '.[0].databaseId')`
Expected: the `CI` workflow succeeds. If the runner's Swift is older than 6.0, record the error and pin a newer runner image (`macos-26` or `macos-15` with `sudo xcode-select -s` to the newest Xcode).

- [ ] **Step 5: Hand off to Plan 2**

Summarise `docs/spikes.md` for the human in five lines (one per spike), with each decision. Those decisions are the inputs for writing Plan 2 (engine).
