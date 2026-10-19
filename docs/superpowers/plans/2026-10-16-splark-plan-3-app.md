# Splark Plan 3: The App — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app people install. The spark in the menu bar, the panel under it, first-run setup, Settings, the app icon, and a release zip on GitHub. All of it sits on Plan 2's engine.

**Architecture:**
- **A new library, `SplarkUI`,** holds every view and controller, so tests reach them. The `Splark` app target keeps only `main.swift` and a small `AppDelegate`.
- **Pure parts are separate and fully unit-tested:**
  - the presenter (every word the UI shows);
  - the models (`PanelModel`, `SetupModel`, `SettingsModel`), behind small service protocols with fakes in tests.
- **Views are SwiftUI hosted in AppKit windows:**
  - the panel in a non-activating `NSPanel` on Liquid Glass;
  - setup and Settings in a window that fits its content.
- **Checking the UI:** the shell can't take screenshots, so the UI is checked by rendering every state offscreen (`ImageRenderer`) to PNGs, in tests and with `splark-dev render-ui`.
- **`AppController`** wires the engine to all of it.

**Tech Stack:** Swift 6 (strict concurrency), macOS 14+, SwiftUI, AppKit (`NSStatusItem`, `NSPanel`, `NSGlassEffectView` on macOS 26), Observation, ServiceManagement (`SMAppService`), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-16-splark-design.md`, mainly §4 (the experience), §8 (privacy), §9 (errors) and §12 (distribution). `design/prototype/panel.html` and `setup.html` are the visual source of truth. Read them before starting; render them with headless Chrome to see them.

**This is plan 3 of 3:**
1. **Foundation and spikes:** done (PR #1).
2. **Engine:** done (PRs #2 and #3).
3. **App UI and packaging** (this plan).

**How this plan was made:**
- **Scratch first:** every line of code in it was written test-first and compiled in a scratch copy of the repo. Each task ended as a commit that builds with no warnings and passes `swift test`.
- **Generated, then checked:** this document was generated from those commits. It was then checked by rebuilding the repo from this document alone. Each task's tests failed before its implementation step and passed after it, and the result matched the scratch copy file for file.
- **Reviewed:** a fresh reviewer read the scratch code before this plan was final, and its findings are fixed in the tasks they belong to.
- **Seen:** every panel, setup and Settings state was rendered and compared with the prototypes.
- **Test counts** in the steps are cumulative.

## Decisions this plan makes where the spec is silent

Ivan: these are the calls to check. Those that change what the spec says (1, 2, 7, 8, 9, 10 and 14) are in the spec update on this branch.

1. **The panel takes the keyboard when it opens, not only when the reply field is focused.**
   - **Why:** Esc and typing a reply work straight away.
   - **The cost is small:** the panel doesn't activate Splark, so the app you were in stays frontmost.
2. **⌃-click opens the menu too,** as well as right-click and ⌥-click. Trackpads often have no right click.
3. **The icon follows Apple's icon grid:** 824 of 1024 px, inset 100 px, like other Mac apps. The `.icns` is rendered at build time by `build-app.sh` rather than committed, so it always matches `PixelArt`.
4. **Setup can continue after a ChatGPT plan that can't be used.** It says why ("Splark will still rank what's unread, without summaries"), as spec §9 asks.
5. **"My workspace needs an admin to approve apps" is a link** under "Waiting for you to click Allow". Slack doesn't tell Splark that approval is pending, so the user says so.
6. **Setup's two switches are applied on Done,** not as they change.
7. **Settings is one window with four tabs** in its title bar (no prototype exists; it uses setup's look).
   - Remove and Reset ask inline, not with alerts. That keeps the look, and lets the states render offscreen.
8. **"+ Add workspace" in Settings opens setup with only the Slack step,** ending in Done.
9. **A pasted token that stops working gets "Paste new token"** in Settings, because there is no app to Allow again. A token for a different workspace is refused, and says so.
10. **"Whether the badge signal is available"** (spec §4.5) is one line under the workspace list. Slack's Dock badge belongs to the app, not to a workspace.
11. **An app waiting for an admin shows as "Slack workspace".** Its name isn't known until Allow.
12. **Previews are `render-ui` galleries,** not Xcode `#Preview` blocks: PNGs of every state, in light and dark, from the same fixtures.
13. **The release workflow drafts the release.** Ivan publishes it after going through `docs/qa.md`.
14. **The README describes "Open Anyway"** in System Settings for macOS 15 and later. Apple removed the right-click → Open bypass there. Right-click → Open stays for macOS 14.
15. **The app has a hidden main menu,** so ⌘V, ⌘C, ⌘A, ⌘Z and ⌘W work in setup and Settings. Without it, an app with no Dock icon can't paste.

## Global Constraints

- **Platform:**
  - `// swift-tools-version: 6.0`, macOS 14, Swift 6 language mode, strict concurrency, no warnings.
  - No dependencies outside Apple frameworks.
  - Liquid Glass sits behind `#if compiler(>=6.2)` and `if #available(macOS 26, *)`; macOS 14–15 get the `.popover` material.
- **Targets:**
  - `SplarkKit`: the engine.
  - `SplarkUI`: every view and controller.
  - `Splark`: `main.swift` and `AppDelegate` only.
  - `splark-dev`: developer commands.
- **Look (spec §4.1):**
  - Monochrome, from `Palette` (Task 4), light and dark.
  - SF Pro with the prototype's weights. The 5×7 pixel font is only for initials and digits in tiles.
  - Copy as in `panel.html` and `setup.html`. Every status line comes from `Presenter`.
- **Sizes:**
  - The panel: 372 pt wide, at most 70% of the screen's visible height, 6 pt under the spark, 8 pt inside the screen edges, corner radius 18.
  - Setup: 560 pt wide and at least 520 tall.
  - Settings: 520 pt wide.
  - Both windows follow their content's height and keep their top edge.
- **Storage:**
  - The app's Keychain service is `dev.splark.Splark`, and its state is `~/Library/Application Support/Splark/state.json`.
  - `splark-dev` keeps its own (`dev.splark.dev`, `dev-state.json`).
- **Privacy:**
  - No message text is logged, printed or written to disk.
  - `SPLARK_DEBUG_PANEL` uses fixtures and reports geometry only.
  - Test fixtures never look like real tokens (`xoxe.xoxp-not-a-real-token`), because GitHub's push protection blocks those.
- **Tests:**
  - Swift Testing.
  - Views are checked by offscreen snapshots. `ImageRenderer` can't draw AppKit-backed controls, so views draw look-alikes when `\.isSnapshot` is set.
  - Tests that wait for something poll with `eventually`; they never sleep a fixed time and then check.
  - Some tests open real windows briefly; they need a logged-in session (GitHub's macOS runners have one).
- **Commits:** as `Ivan Liagushkin <ivliag@gmail.com>` (already in the repo's local git config). Check with `git log -1 --format=%ae` before pushing.

## Review Focus

The inputs the spec implies that a person will actually hit. A fresh review of the scratch code found each of these broken; each is now pinned by a test in the task that owns the code:

1. **A second display:** the spark is on an external monitor's menu bar. The panel must open on that screen, within that screen's height. *Task 9:* `opensOnTheScreenTheSparkIsOn`, `theHeightLimitFollowsTheScreenAtEachOpening`.
2. **A slow network while replying:** the user presses Enter again because nothing seems to happen. Exactly one message must reach Slack. *Task 7:* `aSecondSendWhileTheFirstIsOnItsWaySendsNothing`.
3. **A window closed while Slack's Allow page is open,** or "needs an admin" clicked: the redirect port must be freed, or the next Allow fails with a misleading "another app is using port 53682".
   - *Task 10:* `cancellingStopsWaitingForAllow`, `needingApprovalStopsWaitingForAllowToo`, `closingTheWindowStopsWaitingForAllow`.
   - *Task 11:* `cancellingStopsWaitingForAllowWithoutComplaint`, `aSecondReconnectWaitsItsTurn`.
4. **A Keychain that won't let go** (locked, or refusing an app whose signature changed) during Reset or Remove: Splark must still finish, not stop syncing until relaunch.
   - *Task 1:* `resetCarriesOnPastAKeychainItemThatWontGo`, `removingAWorkspaceWhoseTokenWontGoStillRemovesIt`.
   - *Task 11:* `aResetThatHitsAKeychainErrorStillStartsOver`, `aRemovedWorkspaceWhoseTokenWontGoSaysSo`.
5. **The same failure twice,** such as a mark read retried while offline: both must show a toast. *Task 1:* `theSameFailureTwiceIsReportedTwice`.

## Known gaps, left for later

The review's minor findings that this plan doesn't fix. The live run in Task 14 may promote some of them.

- **A Keychain prompt** denied or left unanswered at launch (after an update):
  - *Denied:* this looks like "needs reconnecting" rather than "Splark couldn't read its Keychain".
  - *Unanswered:* the spark appears only once the prompt is answered.
- **A row being replied to** that the AI later ranks as a comment moves into the folded "Just comments" group mid-typing. The draft is kept.
- **The setup and Settings windows** grow with their content and aren't capped at the screen. A dozen workspaces on a small screen would overflow.
- **Accessibility:**
  - switches announce only "On"/"Off";
  - icon-only buttons have tooltips but no labels;
  - hover-only controls may be missing for VoiceOver.
- **A save already in flight** when Reset runs could, in theory, write `state.json` again afterwards.

---

### Task 1: Give the UI what the engine doesn't have yet

The engine gaps Plan 2's final review left for Plan 3:
- Settings needs the workspace's channels for the exclusions picker, and needs to read and change exclusions. A channel you include again comes back straight away, not at the next inventory.
- It needs the ChatGPT account and the plan's models, and Remove for an app still waiting for approval.
- Reconnect needs the workspace's app registration.
- Signing out has to pause summaries at once and forget the models. Reset Splark has to forget everything.
- The badge must be readable for Settings.

The save loop also stops cleanly: before, a cancelled loop saved once more, so Reset left `state.json` behind.

**Robustness:**
- Reset and Remove finish even when a Keychain item won't delete (a locked keychain, or a refusal after an update), and then say so. Before, a failure left sync stopped until relaunch.
- Reset also forgets the old account's model, usage limit and retries, because another account may sign in next.
- Each `ActionFailure` is its own value. With Swift 6.2's `@Observable`, setting an equal value again doesn't notify, so the same failure twice would show only one toast.

**Files:**
- Modify: `Sources/SplarkKit/ChatGPT/LLMClient.swift`, `Sources/SplarkKit/Engine/SplarkEngine.swift`, `Sources/SplarkKit/Inbox/Actions.swift`, `Sources/SplarkKit/Inbox/InboxStore.swift`, `Sources/SplarkKit/State/StateStore.swift`, `Sources/SplarkKit/Sync/SyncEngine.swift`, `Sources/SplarkKit/Triage/Triage.swift`
- Test: `Tests/SplarkKitTests/ActionsTests.swift`, `Tests/SplarkKitTests/InboxStoreTests.swift`, `Tests/SplarkKitTests/LLMClientTests.swift`, `Tests/SplarkKitTests/SplarkEngineTests.swift`, `Tests/SplarkKitTests/StateStoreTests.swift`, `Tests/SplarkKitTests/SyncEngineTests.swift`, `Tests/SplarkKitTests/TriageTests.swift`

**Interfaces:**
- Consumes: `SplarkEngine`, `SyncEngine`, `Triage`, `StateStore`, `InboxStore` and `ChatGPTLLMClient` (Plan 2).
- Produces:
  - `struct ChannelOption: Sendable, Equatable, Identifiable { id, title ("#eng"), isPrivate }`.
  - `struct ChatGPTAccount: Sendable, Equatable { email: String?, canUsePlan: Bool }`.
  - On `SplarkEngine`:
    - `public private(set) var badge: SlackBadge?`;
    - `channels(teamId:) async -> [ChannelOption]` (sorted, excluded ones included; empty before the first inventory);
    - `excludedChannels(teamId:) -> Set<String>`;
    - `registration(for teamId:) -> SlackAppRegistration?` (nil for a pasted token);
    - `removePendingApp(_:) async`;
    - `chatGPTAccount() async -> ChatGPTAccount?`;
    - `availableModels() async throws -> [String]`;
    - `reset() async throws`.
  - `SyncEngine.everything` (every conversation, excluded or not); `setExcluded` re-includes from it at once.
  - `Triage.signedOut()` and `Triage.forgetAll()` (which also forgets usage limits and retries); `StateStore.delete() throws`; `InboxStore.clear()`; `ChatGPTLLMClient.forgetModels()`.
  - `ActionFailure.id`.
  - `reset()` and `disconnect(teamId:)` forget everything in memory and on disk first, then throw the first Keychain error, if any.
  - In the tests, `StubbornSecrets`, a `SecretStore` whose `delete` always fails.

- [ ] **Step 1: Write the failing tests**

In `Tests/SplarkKitTests/ActionsTests.swift`, replace:

```swift
import Foundation
import Testing
```

with:

```swift
import Foundation
import Observation
import Testing
```

In `Tests/SplarkKitTests/ActionsTests.swift`, replace:

```swift
        actions.markRead([item(inbox, "D1")])
        try await Task.sleep(for: .milliseconds(300))
        #expect(slack.calls.contains("conversations.mark D1"))
    }
```

with:

```swift
        actions.markRead([item(inbox, "D1")])
        #expect(await eventually { slack.calls.contains("conversations.mark D1") })
    }
```

In `Tests/SplarkKitTests/ActionsTests.swift`, replace:

```swift
        #expect(inbox.items.contains { $0.key.channelId == "D1" })
        #expect(actions.lastFailure == ActionFailure(key: item(inbox, "D1").key, message: "Couldn't mark it as read. Try again."))
    }
```

with:

```swift
        #expect(inbox.items.contains { $0.key.channelId == "D1" })
        #expect(actions.lastFailure?.key == item(inbox, "D1").key)
        #expect(actions.lastFailure?.message == "Couldn't mark it as read. Try again.")
    }

    /// The same failure twice in a row reaches the toast twice: setting an equal value again wouldn't tell observers.
    @Test func theSameFailureTwiceIsReportedTwice() async {
        let (actions, inbox, _) = await setUp()
        slack.fail("conversations.mark", with: SlackError.api("not_in_channel"))
        let reported = LockedBox(0)
        for _ in 0..<2 {
            withObservationTracking { _ = actions.lastFailure } onChange: { reported.withLock { $0 += 1 } }
            actions.markRead([item(inbox, "D1")])
            await actions.commitPendingReads()
        }
        #expect(reported.value == 2)
    }
```

In `Tests/SplarkKitTests/InboxStoreTests.swift`, replace:

```swift

    @Test func aConversationCanHoldTwoItems() {
```

with:

```swift

    @Test func clearEmptiesEverything() {
        let s = store([dm, chatter])
        s.clear()
        #expect(s.items.isEmpty && s.summary.headline == "All caught up")
    }

    @Test func aConversationCanHoldTwoItems() {
```

In `Tests/SplarkKitTests/LLMClientTests.swift`, replace:

```swift

    @Test func otherFailuresAreUnavailable() async {
```

with:

```swift

    @Test func forgettingModelsFetchesThemAgain() async throws {
        let models = StubTransport(json: planModels, planModels)
        let llm = ChatGPTLLMClient(session: ChatGPTSession(store: storeWith(signedIn(at: start)), now: { start }),
                                   openAI: OpenAIClient(transport: models, streamer: fakeResponses([], log: RequestLog())), now: { start })
        _ = try await llm.models()
        _ = try await llm.models()
        await llm.forgetModels()
        _ = try await llm.models()
        #expect(models.requests.count == 2)
    }

    @Test func otherFailuresAreUnavailable() async {
```

Append to `Tests/SplarkKitTests/SplarkEngineTests.swift`:

```swift

/// A Keychain that won't delete: locked, or refusing an app whose signature changed.
final class StubbornSecrets: SecretStore, @unchecked Sendable {
    let inner: InMemorySecretStore
    init(_ inner: InMemorySecretStore) { self.inner = inner }
    func read(_ key: String) throws -> String? { try inner.read(key) }
    func write(_ value: String, for key: String) throws { try inner.write(value, for: key) }
    func delete(_ key: String) throws { throw SecretStoreError.keychain(errSecAuthFailed) }
}

@MainActor @Suite struct SplarkEngineForTheUITests {
    let clock = ManualClock()
    let slack = FakeSlack()
    let secrets = InMemorySecretStore()
    let stateStore = StateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("splark-\(UUID().uuidString)/state.json"))
    let credentials = SlackCredentials(teamId: "T1", userId: "U1", accessToken: "xoxe.xoxp-not-a-real-token", refreshToken: "r", expiresAt: nil, clientId: "1.2")
    let lumenWithPort = Workspace(teamId: "T1", name: "Lumen", userId: "U1", userName: "ivan", url: "https://lumen.slack.com/", redirectPort: 53682, appId: "A9")

    init() {
        slack.addChannel("C1", kind: .publicChannel, name: "eng")
        slack.addChannel("G1", kind: .privateChannel, name: "leads")
        slack.addChannel("D1", kind: .im, user: "U2")
    }

    func engine(llm: LLMClient? = FakeLLM.everything(.fyi), workspace: Workspace? = nil, signedIn: ChatGPTCredentials? = nil,
                stubborn: Bool = false) throws -> SplarkEngine {
        var state = SavedState()
        state.workspaces = [workspace ?? lumenWithPort]
        try stateStore.save(state)
        try credentials.save(to: secrets)
        if let signedIn { try secrets.write(String(decoding: try JSONEncoder().encode(signedIn), as: UTF8.self), for: ChatGPTAuth.secretKey) }
        let slack = self.slack, clock = self.clock
        let secrets: SecretStore = stubborn ? StubbornSecrets(self.secrets) : self.secrets
        return SplarkEngine(environment: EngineEnvironment(
            secrets: secrets, state: stateStore, slack: { _ in slack }, chatGPT: ChatGPTSession(store: secrets, now: { clock.now }), llm: llm,
            badges: nil, sync: SyncEngine.Config(), triage: Triage.Config(), now: { clock.now }, open: { _ in true }))
    }

    @Test func listsAWorkspacesChannelsForTheExclusionsPicker() async throws {
        let splark = try engine()
        splark.start()
        #expect(await eventually { await splark.channels(teamId: "T1").count == 2 })
        #expect(await splark.channels(teamId: "T1") == [
            ChannelOption(id: "C1", title: "#eng", isPrivate: false),
            ChannelOption(id: "G1", title: "#leads", isPrivate: true),
        ])
        await splark.setExcluded(["C1"], teamId: "T1")
        #expect(await splark.channels(teamId: "T1").map(\.id) == ["C1", "G1"])   // excluded channels stay listed
        #expect(splark.excludedChannels(teamId: "T1") == ["C1"])
        await splark.stop()
    }

    @Test func remembersTheRegistrationToReconnectAWorkspace() throws {
        let splark = try engine()
        #expect(splark.registration(for: "T1") == SlackAppRegistration(appId: "A9", clientId: "1.2", redirectPort: 53682))
        let pasted = try engine(workspace: lumen)                                  // a pasted token has no app to re-authorise
        #expect(pasted.registration(for: "T1") == nil)
    }

    @Test func pendingAppsCanBeRemoved() async throws {
        let splark = try engine()
        let app = SlackAppRegistration(appId: "A7", clientId: "7.7", redirectPort: 53683)
        await splark.addPendingApp(app)
        #expect(splark.pendingApps == [app])
        await splark.removePendingApp(app)
        #expect(splark.pendingApps.isEmpty && stateStore.load().pendingApps.isEmpty)
    }

    @Test func showsTheChatGPTAccountAndForgetsItOnSignOut() async throws {
        let start = clock.now
        let creds = ChatGPTCredentials(clientId: "oaiapp_1", hostId: "urn:uuid:0", accessToken: "a", refreshToken: "r", idToken: nil,
                                       expiresAt: start.addingTimeInterval(3600), scopes: ["chatgpt.tokens.use.direct"], email: "ivan@lumen.dev", subject: "s")
        let splark = try engine(llm: nil, signedIn: creds)
        #expect(await splark.chatGPTAccount() == ChatGPTAccount(email: "ivan@lumen.dev", canUsePlan: true))
        try await splark.signOutOfChatGPT()
        #expect(await splark.chatGPTAccount() == nil)
        #expect(splark.triageState == .paused(.signedOut))
    }

    @Test func knowsWhetherSlacksBadgeCanBeRead() async throws {
        let splark = try engine()
        #expect(splark.badge == nil)
        await splark.badgeChanged(.dot)
        #expect(splark.badge == .dot)
    }

    @Test func resetForgetsEverything() async throws {
        let splark = try engine()
        splark.start()
        #expect(await eventually { !splark.inbox.items.isEmpty || splark.syncStatus["T1"]?.progress.isComplete == true })
        try await splark.reset()
        #expect(splark.workspaces.isEmpty && splark.inbox.items.isEmpty && !splark.isRunning)
        #expect(try secrets.read("slack.T1") == nil)
        #expect(!FileManager.default.fileExists(atPath: stateStore.url.path))
    }

    /// A Keychain item that won't go doesn't leave Splark half reset: everything else is forgotten, and the error says why.
    @Test func resetCarriesOnPastAKeychainItemThatWontGo() async throws {
        let splark = try engine(stubborn: true)
        splark.start()
        await #expect(throws: SecretStoreError.keychain(errSecAuthFailed)) { try await splark.reset() }
        #expect(splark.workspaces.isEmpty && splark.inbox.items.isEmpty && !splark.isRunning)
        #expect(!FileManager.default.fileExists(atPath: stateStore.url.path))
    }

    @Test func removingAWorkspaceWhoseTokenWontGoStillRemovesIt() async throws {
        let splark = try engine(stubborn: true)
        splark.start()
        await #expect(throws: SecretStoreError.keychain(errSecAuthFailed)) { try await splark.disconnect(teamId: "T1") }
        #expect(splark.workspaces.isEmpty && stateStore.load().workspaces.isEmpty)
        await splark.stop()
    }
}
```

In `Tests/SplarkKitTests/StateStoreTests.swift`, replace:

```swift

    @Test func onlyTheUserCanReadIt() throws {
```

with:

```swift

    @Test func deleteRemovesTheFile() throws {
        let store = tempStore()
        try store.save(sample)
        try store.delete()
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
        try store.delete()   // already gone: fine
    }

    @Test func onlyTheUserCanReadIt() throws {
```

Append to `Tests/SplarkKitTests/SyncEngineTests.swift`:

```swift

@Suite struct SyncEngineInventoryTests {
    let clock = ManualClock()

    @Test func aChannelComesBackAtOnceWhenNoLongerExcluded() async {
        let slack = FakeSlack()
        slack.addChannel("C1", kind: .publicChannel, name: "eng", lastRead: ts(-100))
        slack.addChannel("C2", kind: .publicChannel, name: "random", lastRead: ts(-100))
        slack.post("C2", slackMessage(ts(-50), user: "U2", text: "hi"))
        let engine = makeEngine(slack, clock, excluded: ["C2"])
        _ = await engine.runUntilIdle()
        #expect(await engine.conversations.map(\.id) == ["C1", "C2"])   // everything the user is in, excluded or not
        _ = await engine.setExcluded([])
        #expect(await engine.runUntilIdle().upserted.keys.map(\.channelId) == ["C2"])   // no wait for the next inventory
    }
}
```

In `Tests/SplarkKitTests/TriageTests.swift`, replace:

```swift

    @Test func signedOutWaitsForSignIn() async {
```

with:

```swift

    /// After Reset another ChatGPT account may sign in: the old one's usage limit doesn't carry over.
    @Test func forgetAllForgetsAUsageLimit() async {
        let until = clock.now.addingTimeInterval(3600)
        let llm = FakeLLM { _ in throw LLMError.usageLimited(until: until) }
        let t = triage(llm)
        await t.update(update([channelSnapshot("C1")]))
        clock.advance(20)
        _ = await t.flushIfDue()
        #expect(await t.state == .paused(.usageLimit(until: until)))
        await t.forgetAll()
        #expect(await t.state == .idle)
    }

    @Test func signedOutWaitsForSignIn() async {
```

In `Tests/SplarkKitTests/TriageTests.swift`, replace:

```swift
    func answerSync(_ request: LLMRequest) throws -> String { try answer(request) }
}
```

with:

```swift
    func answerSync(_ request: LLMRequest) throws -> String { try answer(request) }
}

@Suite struct TriageSignOutTests {
    @Test func signingOutPausesAtOnce() async {
        let t = Triage(llm: FakeLLM.everything(.fyi), now: { Date(timeIntervalSince1970: 0) })
        await t.signedOut()
        #expect(await t.state == .paused(.signedOut))
        await t.resume()
        #expect(await t.state == .idle)
    }

    @Test func forgetAllDropsEverythingWaiting() async {
        let t = Triage(llm: FakeLLM.everything(.fyi), now: { Date(timeIntervalSince1970: 0) })
        await t.update(update([channelSnapshot("C1")]))
        await t.forgetAll()
        #expect(await t.waitingCount == 0)
        #expect(await t.nextFlush == nil)
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift build --build-tests`
Expected: the build fails: `value of type 'SplarkEngine' has no member 'channels'`, `… has no member 'reset'`, `cannot find 'ChannelOption' in scope`, …

- [ ] **Step 3: Implement**

In `Sources/SplarkKit/ChatGPT/LLMClient.swift`, replace:

```swift

    /// The plan's models, fetched once.
```

with:

```swift

    /// After signing out: another account may offer other models.
    public func forgetModels() {
        available = nil
        schemaRefused = []
    }

    /// The plan's models, fetched once.
```

In `Sources/SplarkKit/Engine/SplarkEngine.swift`, replace:

```swift
            now: { Date() }, open: { NSWorkspace.shared.open($0) })
    }
```

with:

```swift
            now: { Date() }, open: { NSWorkspace.shared.open($0) })
    }
}

/// A channel for the exclusions picker (spec §4.5).
public struct ChannelOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String   // "#eng"
    public let isPrivate: Bool

    public init(id: String, title: String, isPrivate: Bool) {
        self.id = id
        self.title = title
        self.isPrivate = isPrivate
    }
}

/// The signed-in ChatGPT account, for setup and Settings.
public struct ChatGPTAccount: Sendable, Equatable {
    public let email: String?
    public let canUsePlan: Bool

    public init(email: String?, canUsePlan: Bool) {
        self.email = email
        self.canUsePlan = canUsePlan
    }
```

In `Sources/SplarkKit/Engine/SplarkEngine.swift`, replace:

```swift
    public private(set) var isRunning = false
    public var workspaces: [Workspace] { state.workspaces }
```

with:

```swift
    public private(set) var isRunning = false
    public private(set) var badge: SlackBadge?   // nil: Slack isn't running, or its badge can't be read
    public var workspaces: [Workspace] { state.workspaces }
```

In `Sources/SplarkKit/Engine/SplarkEngine.swift`, replace:

```swift
        saveLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.save()
```

with:

```swift
        saveLoop = Task { [weak self] in
            // A cancelled sleep throws: stop here, rather than save once more after stop() (or reset()) is done.
            while (try? await Task.sleep(for: .seconds(60))) != nil {
                await self?.save()
```

In `Sources/SplarkKit/Engine/SplarkEngine.swift`, replace:

```swift
    public func badgeChanged(_ badge: SlackBadge?) async {
        for running in registry.running.values {
```

with:

```swift
    public func badgeChanged(_ badge: SlackBadge?) async {
        self.badge = badge
        for running in registry.running.values {
```

In `Sources/SplarkKit/Engine/SplarkEngine.swift`, replace:

```swift

    /// Settings → Remove: forgets the token and everything Splark kept about the workspace.
    public func disconnect(teamId: String) async throws {
        await halt(teamId)
        try environment.secrets.delete(SlackCredentials.key(teamId: teamId))
        state.workspaces.removeAll { $0.teamId == teamId }
```

with:

```swift

    public func removePendingApp(_ app: SlackAppRegistration) async {
        state.pendingApps.removeAll { $0 == app }
        await save()
    }

    /// What "Reconnect" re-authorises: the workspace's private app. Nil for a pasted token, which has no app.
    public func registration(for teamId: String) -> SlackAppRegistration? {
        guard let workspace = state.workspaces.first(where: { $0.teamId == teamId }), let port = workspace.redirectPort,
              let clientId = (try? SlackCredentials.load(teamId: teamId, from: environment.secrets)).flatMap({ $0 })?.clientId else { return nil }
        return SlackAppRegistration(appId: workspace.appId, clientId: clientId, redirectPort: port)
    }

    /// Every channel the user is in (excluded ones too), sorted by name. Empty until the first inventory.
    public func channels(teamId: String) async -> [ChannelOption] {
        guard let running = registry.running[teamId] else { return [] }
        return await running.engine.conversations
            .filter { $0.kind == .publicChannel || $0.kind == .privateChannel }
            .map { ChannelOption(id: $0.id, title: "#" + ($0.name ?? $0.id), isPrivate: $0.kind == .privateChannel) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func excludedChannels(teamId: String) -> Set<String> { Set(state.excludedChannels[teamId] ?? []) }

    /// Settings → Remove: forgets the token and everything Splark kept about the workspace.
    /// The workspace goes even when its Keychain item won't; the error then says so.
    public func disconnect(teamId: String) async throws {
        await halt(teamId)
        state.workspaces.removeAll { $0.teamId == teamId }
```

In `Sources/SplarkKit/Engine/SplarkEngine.swift`, replace:

```swift
        inbox.setWorkspaces(state.workspaces)
        await save()
    }

```

with:

```swift
        inbox.setWorkspaces(state.workspaces)
        await save()
        try environment.secrets.delete(SlackCredentials.key(teamId: teamId))
    }

```

In `Sources/SplarkKit/Engine/SplarkEngine.swift`, replace:

```swift
        try await environment.chatGPT.signOut()
    }
```

with:

```swift
        try await environment.chatGPT.signOut()
        await chatGPTClient?.forgetModels()
        await triage.signedOut()
        triageState = await triage.state
    }

    public func chatGPTAccount() async -> ChatGPTAccount? {
        await environment.chatGPT.credentials.map { ChatGPTAccount(email: $0.email, canUsePlan: $0.canUsePlan) }
    }

    /// The plan's models, for Settings' model picker. Empty when summaries come from another LLM client.
    public func availableModels() async throws -> [String] {
        try await chatGPTClient?.models() ?? []
    }

    /// Settings → Reset Splark: stops, then forgets every token, setting and summary. The app shows setup again.
    /// Everything in memory is forgotten even if a Keychain item or the file won't go; the first such error is thrown after.
    public func reset() async throws {
        await stop()
        var failure: Error?
        func attempt(_ body: () throws -> Void) {
            do { try body() } catch { failure = failure ?? error }
        }
        for workspace in state.workspaces { attempt { try environment.secrets.delete(SlackCredentials.key(teamId: workspace.teamId)) } }
        do { try await environment.chatGPT.signOut() } catch { failure = failure ?? error }
        attempt { try environment.secrets.delete(ChatGPTSession.hostKey) }
        attempt { try environment.state.delete() }
        await triage.forgetAll()
        await chatGPTClient?.setModel(nil)
        await chatGPTClient?.forgetModels()
        state = SavedState()
        syncStatus = [:]
        inbox.clear()
        inbox.setWorkspaces([])
        if let failure { throw failure }
    }
```

In `Sources/SplarkKit/Inbox/Actions.swift`, replace:

```swift

/// Shown as a toast (spec §9).
public struct ActionFailure: Sendable, Equatable {
    public let key: ItemKey
```

with:

```swift

/// Shown as a toast (spec §9). Each failure is its own value, so the same one twice still reaches the toast.
public struct ActionFailure: Sendable, Equatable {
    public let id = UUID()
    public let key: ItemKey
```

In `Sources/SplarkKit/Inbox/InboxStore.swift`, replace:

```swift

    // MARK: Optimistic states for Actions
```

with:

```swift

    /// Reset Splark: nothing left to show.
    public func clear() {
        snapshots = [:]
        results = [:]
        hidden = [:]
        repliedAt = [:]
        reactions = [:]
        rebuild()
    }

    // MARK: Optimistic states for Actions
```

In `Sources/SplarkKit/State/StateStore.swift`, replace:

```swift

    /// Atomic, and readable only by the user.
```

with:

```swift

    /// Reset Splark. A missing file is fine.
    public func delete() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Atomic, and readable only by the user.
```

In `Sources/SplarkKit/Sync/SyncEngine.swift`, replace:

```swift
    private var schedule: SyncSchedule
    private var inventory: [String: SlackConversation] = [:]
    private var inventoryDue = Date.distantPast
```

with:

```swift
    private var schedule: SyncSchedule
    private var everything: [String: SlackConversation] = [:]   // every conversation the user is in, excluded or not
    private var inventory: [String: SlackConversation] = [:]    // the ones Splark syncs
    private var inventoryDue = Date.distantPast
```

In `Sources/SplarkKit/Sync/SyncEngine.swift`, replace:

```swift

    public func setExcluded(_ ids: Set<String>) -> SyncUpdate {
        excluded = ids
        inventory = inventory.filter { !ids.contains($0.key) }
        schedule.setInventory(inventory.mapValues(\.kind), now: now())
```

with:

```swift

    /// Every conversation the user is in, excluded ones included (for the exclusions picker).
    public var conversations: [SlackConversation] { everything.values.sorted { $0.id < $1.id } }

    /// Takes effect at once both ways: a channel no longer excluded is due straight away.
    public func setExcluded(_ ids: Set<String>) -> SyncUpdate {
        excluded = ids
        inventory = everything.filter { !ids.contains($0.key) }
        schedule.setInventory(inventory.mapValues(\.kind), now: now())
```

In `Sources/SplarkKit/Sync/SyncEngine.swift`, replace:

```swift
    private func takeInventory(now: Date) async throws -> SyncUpdate {
        let all = try await slack.allConversations().filter { !excluded.contains($0.id) && $0.isArchived != true }
        inventory = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        schedule.setInventory(inventory.mapValues(\.kind), now: now)
```

with:

```swift
    private func takeInventory(now: Date) async throws -> SyncUpdate {
        let all = try await slack.allConversations().filter { $0.isArchived != true }
        everything = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        inventory = everything.filter { !excluded.contains($0.key) }
        schedule.setInventory(inventory.mapValues(\.kind), now: now)
```

In `Sources/SplarkKit/Triage/Triage.swift`, replace:

```swift
    public func setPaused(_ paused: Bool) { userPaused = paused }

```

with:

```swift
    public func setPaused(_ paused: Bool) { userPaused = paused }

    /// Signed out of ChatGPT: hold everything until `resume()`.
    public func signedOut() { accountPause = .signedOut }

    /// Reset Splark: forget every conversation, summary and anything waiting, and the old account's limits and retries.
    public func forgetAll() {
        snapshots = [:]
        cache = [:]
        dirty = []
        firstDirty = nil
        lastDirty = nil
        requestTimes = []
        usageLimitedUntil = nil
        retryAt = nil
        failures = 0
    }

```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test`
Expected: PASS, `✔ Test run with 247 tests`. `swift build --build-tests` prints no warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/SplarkKit/ChatGPT/LLMClient.swift Sources/SplarkKit/Engine/SplarkEngine.swift Sources/SplarkKit/Inbox/Actions.swift Sources/SplarkKit/Inbox/InboxStore.swift Sources/SplarkKit/State/StateStore.swift Sources/SplarkKit/Sync/SyncEngine.swift Sources/SplarkKit/Triage/Triage.swift Tests/SplarkKitTests/ActionsTests.swift Tests/SplarkKitTests/InboxStoreTests.swift Tests/SplarkKitTests/LLMClientTests.swift Tests/SplarkKitTests/SplarkEngineTests.swift Tests/SplarkKitTests/StateStoreTests.swift Tests/SplarkKitTests/SyncEngineTests.swift Tests/SplarkKitTests/TriageTests.swift
git commit -m "Give the UI what it needs from the engine" -m "Channels and exclusions for the picker, the ChatGPT account and models,
app registrations for Reconnect, Remove for pending apps, Reset, and a
sign-out that pauses summaries at once."
```

---

### Task 2: Fix what Plan 2's review deferred

The rest of Plan 2's deferred minors, each with a test:
- A thread with more than 200 unread replies kept only the first page: replies are now read 200 at a time, up to 5 pages.
- An edit to an unread message showed only after a new message: each conversation's fingerprint (timestamp, text and file count of every unread message) now decides whether it changed.
- A never-opened DM said "and more" whenever older history existed. Now it does so only when Slack's unread count is above the history limit.
- A channel stuck on `missing_scope` kept "Catching up… N−1 of N" showing. Now it counts as checked.
- The word limits didn't trim text without spaces (CJK): `TriagePrompt.clamp` also caps characters: lead 80, rest 200, reason 100.
- No test sent `token_expired` to several calls at once. Now one does.

**Files:**
- Modify: `Sources/SplarkKit/Sync/SyncEngine.swift`, `Sources/SplarkKit/Triage/TriagePrompt.swift`
- Test: `Tests/SplarkKitTests/FakeSlack.swift`, `Tests/SplarkKitTests/SlackCredentialsTests.swift`, `Tests/SplarkKitTests/SyncEngineTests.swift`, `Tests/SplarkKitTests/TriagePromptTests.swift`

**Interfaces:**
- Consumes: `SyncEngine`, `TriagePrompt`, `SlackTokenManager` (Plan 2).
- Produces:
  - `SyncEngine.Config.repliesPageSize = 200`.
  - `TriagePrompt.clamp(_:words:characters:) -> String`, with `leadCharacters = 80`, `restCharacters = 200` and `reasonCharacters = 100`.
  - In the tests, `FakeSlack.edit(_:ts:text:)`. `FakeSlack` now returns history and replies sorted, as Slack does.

- [ ] **Step 1: Write the failing tests**

In `Tests/SplarkKitTests/FakeSlack.swift`, replace:

```swift
        lock.withLock { threads["\(channel)/\(thread)", default: []].append(message) }
    }
```

with:

```swift
        lock.withLock { threads["\(channel)/\(thread)", default: []].append(message) }
    }

    /// Changes a top-level message's text, as an edit in Slack would.
    func edit(_ channel: String, _ ts: String, text: String) {
        lock.withLock {
            guard let i = channels[channel]?.messages.firstIndex(where: { $0.ts == ts }), let m = channels[channel]?.messages[i] else { return }
            channels[channel]?.messages[i] = SlackMessage(ts: m.ts, user: m.user, botId: m.botId, username: m.username, subtype: m.subtype, text: text,
                                                          threadTs: m.threadTs, replyCount: m.replyCount, latestReply: m.latestReply,
                                                          replyUsers: m.replyUsers, files: m.files, botProfile: m.botProfile)
        }
    }
```

In `Tests/SplarkKitTests/FakeSlack.swift`, replace:

```swift
            guard let c = channels[channel] else { throw SlackError.api("channel_not_found") }
            let matching = c.messages.filter { m in
                (oldest.map { SlackTS.isAfter(m.ts, $0) } ?? true)
```

with:

```swift
            guard let c = channels[channel] else { throw SlackError.api("channel_not_found") }
            let matching = c.messages.sorted { SlackTS.isAfter($1.ts, $0.ts) }.filter { m in
                (oldest.map { SlackTS.isAfter(m.ts, $0) } ?? true)
```

In `Tests/SplarkKitTests/FakeSlack.swift`, replace:

```swift
            guard let parent = channels[channel]?.messages.first(where: { $0.ts == ts }) else { throw SlackError.api("thread_not_found") }
            let replies = (threads["\(channel)/\(ts)"] ?? []).filter { r in oldest.map { SlackTS.isAfter(r.ts, $0) } ?? true }
            return SlackHistory(messages: [parent] + replies.prefix(limit), hasMore: replies.count > limit, responseMetadata: nil)
```

with:

```swift
            guard let parent = channels[channel]?.messages.first(where: { $0.ts == ts }) else { throw SlackError.api("thread_not_found") }
            let replies = (threads["\(channel)/\(ts)"] ?? []).sorted { SlackTS.isAfter($1.ts, $0.ts) }   // oldest first, as Slack does
                .filter { r in oldest.map { SlackTS.isAfter(r.ts, $0) } ?? true }
            return SlackHistory(messages: [parent] + replies.prefix(limit), hasMore: replies.count > limit, responseMetadata: nil)
```

In `Tests/SplarkKitTests/SlackCredentialsTests.swift`, replace:

```swift

    @Test func clientGivesUpWhenTheFreshTokenIsAlsoRejected() async {
```

with:

```swift

    @Test func manyCallsRejectedTogetherShareOneRefresh() async throws {
        /// Answers token_expired to the old token and ok to the new one, whatever the order of calls.
        final class ExpiringSlack: HTTPTransport, @unchecked Sendable {
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
                let old = request.value(forHTTPHeaderField: "Authorization") == "Bearer xoxe.xoxp-a1"
                let body = old ? #"{"ok":false,"error":"token_expired"}"# : #"{"ok":true,"user_id":"U1","team_id":"T1"}"#
                return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
        let calls = Calls()
        let manager = SlackTokenManager(credentials: creds(expiresIn: 7200), store: connected(creds(expiresIn: 7200)), refresher: { _, r in
            calls.add(r)
            try await Task.sleep(for: .milliseconds(30))
            return refresh("xoxe.xoxp-a2", "xoxe-1-r2")
        }, now: { start })
        let client = SlackClient(tokens: manager, transport: ExpiringSlack(), sleeper: RecordingSleeper())
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { _ = try await client.authTest() } }
            try await group.waitForAll()
        }
        #expect(calls.all.count == 1)
    }

    @Test func clientGivesUpWhenTheFreshTokenIsAlsoRejected() async {
```

In `Tests/SplarkKitTests/SyncEngineTests.swift`, replace:

```swift
        #expect(update.upserted[ItemKey(teamId: "T1", channelId: "D1")]?.kind == .dm)
        #expect(!slack.calls.contains("conversations.history D2"))
```

with:

```swift
        #expect(update.upserted[ItemKey(teamId: "T1", channelId: "D1")]?.kind == .dm)
        #expect(update.upserted[ItemKey(teamId: "T1", channelId: "D1")]?.moreUnread == false)   // older history isn't more unread
        #expect(!slack.calls.contains("conversations.history D2"))
```

In `Tests/SplarkKitTests/SyncEngineTests.swift`, replace:

```swift
        #expect(slack.calls.filter { $0 == "conversations.history C1" }.count == 1)   // no second call for context
    }
```

with:

```swift
        #expect(slack.calls.filter { $0 == "conversations.history C1" }.count == 1)   // no second call for context
    }

    @Test func anEditedMessageShowsItsNewText() async {
        let slack = channelWithSevenMessages(lastRead: ts(-500))
        let engine = makeEngine(slack, clock)
        _ = await engine.runUntilIdle()
        slack.edit("C1", ts(-300), text: "m6, edited")
        clock.advance(61)
        #expect(await engine.runUntilIdle().upserted[c1]?.unread.map(\.text) == ["m5", "m6, edited"])
    }
```

In `Tests/SplarkKitTests/SyncEngineTests.swift`, replace:

```swift
        #expect(await engine.status.missingScope)
        slack.fail("conversations.info C1", with: URLError(.notConnectedToInternet))
```

with:

```swift
        #expect(await engine.status.missingScope)
        #expect(await engine.status.progress.isComplete)   // the refused channel doesn't keep "Catching up…" showing
        slack.fail("conversations.info C1", with: URLError(.notConnectedToInternet))
```

In `Tests/SplarkKitTests/SyncEngineTests.swift`, replace:

```swift

    @Test func threadsWithNoItemYetAreClearedByATrustedClearBadge() async {
```

with:

```swift

    @Test func aThreadWithHundredsOfUnreadRepliesReachesTheNewest() async throws {
        let slack = slackWithAThread(lastRead: ts(-3500))
        for i in 0..<450 { slack.reply("C1", thread: parent, slackMessage(ts(-1900 + i), user: "U2", text: "r\(i)", threadTs: parent)) }
        let item = try #require(await makeEngine(slack, clock).runUntilIdle().upserted[thread])
        #expect(item.newestTs == ts(-60))
        #expect(!item.moreUnread)
    }

    @Test func threadsWithNoItemYetAreClearedByATrustedClearBadge() async {
```

In `Tests/SplarkKitTests/TriagePromptTests.swift`, replace:

```swift

    @Test func theSchemaIsStrict() throws {
```

with:

```swift

    @Test func textWithoutSpacesIsTrimmedToo() throws {
        let long = String(repeating: "承認してください", count: 40)   // Japanese: no spaces, so word limits never trim it
        let output = #"{"items":[{"conversation_id":"c1","level":"action","lead":"\#(long)","rest":"\#(long)","reason":"\#(long)","anchor_ts":""}]}"#
        let item = try #require(try TriagePrompt.parse(output, ids: ["c1": dm.key], snapshots: [dm.key: dm])[dm.key]?.first)
        #expect(item.lead.count <= 81 && item.rest.count <= 201 && item.reason.count <= 101)
        let heuristic = TriagePrompt.heuristic(snapshot("D1", kind: .dm, title: "Marta", unread: [(ts(-1), "Marta", long, false)]))
        #expect(heuristic.lead.count <= 81 && heuristic.rest.count <= 201)
    }

    @Test func theSchemaIsStrict() throws {
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift build --build-tests && swift test --filter 'SyncEngineTests|TriagePromptTests'`
Expected: the build succeeds and the tests fail. The new tests run against the old code: `anEditedMessageShowsItsNewText`, `aThreadWithHundredsOfUnreadRepliesReachesTheNewest` and `textWithoutSpacesIsTrimmedToo` fail, among others.

- [ ] **Step 3: Implement**

In `Sources/SplarkKit/Sync/SyncEngine.swift`, replace:

```swift
        public var historyLimit = 40
        public var contextCount = 3
```

with:

```swift
        public var historyLimit = 40
        public var repliesPageSize = 200                       // up to 5 pages: a thread's newest 1,000 replies
        public var contextCount = 3
```

In `Sources/SplarkKit/Sync/SyncEngine.swift`, replace:

```swift
    private var readThrough: [String: String] = [:]   // marked read in Splark; Slack's last_read may lag behind
    private var sweepDue = Date.distantPast
```

with:

```swift
    private var readThrough: [String: String] = [:]   // marked read in Splark; Slack's last_read may lag behind
    private var fingerprints: [ItemKey: [String]] = [:]   // the unread messages as last sent, so an edit counts as a change
    private var sweepDue = Date.distantPast
```

In `Sources/SplarkKit/Sync/SyncEngine.swift`, replace:

```swift

        guard let first = unread.first, let newest = unread.last else { return removing(key) }
        if let existing = snapshots[key], existing.newestTs == newest.ts, existing.unread.count == unread.count { return SyncUpdate() }
        let context = try await slack.conversationsHistory(id, oldest: nil, latest: first.ts, inclusive: false, limit: config.contextCount)
            .messages.filter(isShown).sorted(by: oldestFirst)
        watchThreads(in: context, channelId: id, now: now)
        let built = await snapshot(key, kind: kind(of: conversation), conversation: conversation,
                                   unread: unread, context: context, moreUnread: page?.hasMore ?? false)
        return isWanted(key, newest: built.newestTs) ? upserting(built) : removing(key)
    }
```

with:

```swift

        guard let first = unread.first else { return removing(key) }
        if snapshots[key] != nil, fingerprints[key] == fingerprint(unread) { return SyncUpdate() }
        let context = try await slack.conversationsHistory(id, oldest: nil, latest: first.ts, inclusive: false, limit: config.contextCount)
            .messages.filter(isShown).sorted(by: oldestFirst)
        watchThreads(in: context, channelId: id, now: now)
        // A never-opened DM asked for exactly its unread count, so Slack's has_more only means older, read history.
        let moreUnread = neverOpenedDM ? (info.unreadCountDisplay ?? 0) > config.historyLimit : page?.hasMore ?? false
        let built = await snapshot(key, kind: kind(of: conversation), conversation: conversation,
                                   unread: unread, context: context, moreUnread: moreUnread)
        guard isWanted(key, newest: built.newestTs) else { return removing(key) }
        fingerprints[key] = fingerprint(unread)
        return upserting(built)
    }
```

In `Sources/SplarkKit/Sync/SyncEngine.swift`, replace:

```swift
        for _ in 0..<5 {
            let page = try await slack.conversationsReplies(watch.channelId, ts: watch.threadTs, oldest: oldest, limit: config.historyLimit)
            parent = parent ?? page.messages.first { $0.ts == watch.threadTs }
```

with:

```swift
        for _ in 0..<5 {
            let page = try await slack.conversationsReplies(watch.channelId, ts: watch.threadTs, oldest: oldest, limit: config.repliesPageSize)
            parent = parent ?? page.messages.first { $0.ts == watch.threadTs }
```

In `Sources/SplarkKit/Sync/SyncEngine.swift`, replace:

```swift
        }
        if let existing = snapshots[key], existing.newestTs == newest.ts, existing.unread.count == unread.count { return SyncUpdate() }
        if parent == nil {
            parent = try await slack.conversationsReplies(watch.channelId, ts: watch.threadTs, oldest: nil, limit: 1).messages.first { $0.ts == watch.threadTs }
        }
        let context = [parent].compactMap { $0 } + replies.filter { SlackTS.isAfter(first.ts, $0.ts) }.suffix(2)
        let built = await snapshot(key, kind: .thread, conversation: inventory[watch.channelId], unread: unread, context: context, moreUnread: hasMore)
        return isWanted(key, newest: built.newestTs) ? upserting(built) : removing(key)
    }
```

with:

```swift
        }
        if snapshots[key] != nil, fingerprints[key] == fingerprint(unread) { return SyncUpdate() }
        if parent == nil {
            parent = try await slack.conversationsReplies(watch.channelId, ts: watch.threadTs, oldest: nil, limit: 1).messages.first { $0.ts == watch.threadTs }
        }
        let context = [parent].compactMap { $0 } + replies.filter { SlackTS.isAfter(first.ts, $0.ts) }.suffix(2)
        let built = await snapshot(key, kind: .thread, conversation: inventory[watch.channelId], unread: unread, context: context, moreUnread: hasMore)
        guard isWanted(key, newest: built.newestTs) else { return removing(key) }
        fingerprints[key] = fingerprint(unread)
        return upserting(built)
    }
```

In `Sources/SplarkKit/Sync/SyncEngine.swift`, replace:

```swift
            status.missingScope = true
            postpone(job, until: now.addingTimeInterval(config.inventoryInterval))
```

with:

```swift
            status.missingScope = true
            if case .conversation(let id) = job {   // counted as checked, so "Catching up…" can finish
                schedule.checked(id, now: now, lastActivity: nil, hasUnread: false)
            }
            postpone(job, until: now.addingTimeInterval(config.inventoryInterval))
```

In `Sources/SplarkKit/Sync/SyncEngine.swift`, replace:

```swift

    private func removing(_ key: ItemKey) -> SyncUpdate {
        var update = SyncUpdate()
```

with:

```swift

    private func fingerprint(_ messages: [SlackMessage]) -> [String] {
        messages.map { "\($0.ts)|\($0.text ?? "")|\($0.files?.count ?? 0)" }
    }

    private func removing(_ key: ItemKey) -> SyncUpdate {
        fingerprints[key] = nil
        var update = SyncUpdate()
```

In `Sources/SplarkKit/Triage/TriagePrompt.swift`, replace:

```swift
    static let leadWords = 10, restWords = 24, reasonWords = 12   // the spec's 8 / 20 / 10, with a little slack
    static let maxMessages = 20, maxMessageCharacters = 1000
```

with:

```swift
    static let leadWords = 10, restWords = 24, reasonWords = 12   // the spec's 8 / 20 / 10, with a little slack
    static let leadCharacters = 80, restCharacters = 200, reasonCharacters = 100   // for text without spaces (Chinese, Japanese)
    static let maxMessages = 20, maxMessageCharacters = 1000
```

In `Sources/SplarkKit/Triage/TriagePrompt.swift`, replace:

```swift
            guard let key = ids[raw.conversation_id], let snapshot = snapshots[key], let level = TriageLevel(rawValue: raw.level) else { continue }
            let lead = clamp(raw.lead, words: leadWords)
            guard !lead.isEmpty else { continue }
            let anchor = snapshot.unread.contains { $0.ts == raw.anchor_ts } ? raw.anchor_ts : snapshot.newestTs
            byKey[key, default: []].append(TriageItem(level: level, lead: lead, rest: clamp(raw.rest, words: restWords),
                                                      reason: clamp(raw.reason, words: reasonWords), anchorTs: anchor, byAI: true))
        }
```

with:

```swift
            guard let key = ids[raw.conversation_id], let snapshot = snapshots[key], let level = TriageLevel(rawValue: raw.level) else { continue }
            let lead = clamp(raw.lead, words: leadWords, characters: leadCharacters)
            guard !lead.isEmpty else { continue }
            let anchor = snapshot.unread.contains { $0.ts == raw.anchor_ts } ? raw.anchor_ts : snapshot.newestTs
            byKey[key, default: []].append(TriageItem(level: level, lead: lead, rest: clamp(raw.rest, words: restWords, characters: restCharacters),
                                                      reason: clamp(raw.reason, words: reasonWords, characters: reasonCharacters), anchorTs: anchor, byAI: true))
        }
```

In `Sources/SplarkKit/Triage/TriagePrompt.swift`, replace:

```swift
        let words = newest.text.split(whereSeparator: \.isWhitespace).map(String.init)
        let lead = words.isEmpty ? "New message from \(newest.author)" : words.prefix(8).joined(separator: " ")
        let rest = clamp(words.dropFirst(8).joined(separator: " "), words: 20)
        return TriageItem(level: snapshot.isDirect ? .question : .fyi, lead: lead, rest: rest,
                          reason: snapshot.isDirect ? "Sent to you" : "Channel activity", anchorTs: newest.ts, byAI: false)
    }

    static func clamp(_ text: String, words limit: Int) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.count > limit ? words.prefix(limit).joined(separator: " ") + "…" : words.joined(separator: " ")
    }
```

with:

```swift
        let words = newest.text.split(whereSeparator: \.isWhitespace).map(String.init)
        let lead = words.isEmpty ? "New message from \(newest.author)" : clamp(words.prefix(8).joined(separator: " "), words: 8, characters: leadCharacters)
        let rest = clamp(words.dropFirst(8).joined(separator: " "), words: 20, characters: restCharacters)
        return TriageItem(level: snapshot.isDirect ? .question : .fyi, lead: lead, rest: rest,
                          reason: snapshot.isDirect ? "Sent to you" : "Channel activity", anchorTs: newest.ts, byAI: false)
    }

    static func clamp(_ text: String, words limit: Int, characters: Int) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        let clamped = words.count > limit ? words.prefix(limit).joined(separator: " ") + "…" : words.joined(separator: " ")
        return clamped.count > characters ? String(clamped.prefix(characters)) + "…" : clamped
    }
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test`
Expected: PASS, `✔ Test run with 251 tests`. `swift build --build-tests` prints no warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/SplarkKit/Sync/SyncEngine.swift Sources/SplarkKit/Triage/TriagePrompt.swift Tests/SplarkKitTests/FakeSlack.swift Tests/SplarkKitTests/SlackCredentialsTests.swift Tests/SplarkKitTests/SyncEngineTests.swift Tests/SplarkKitTests/TriagePromptTests.swift
git commit -m "Fix what Plan 2's review deferred" -m "Long threads read in pages, edits noticed, never-opened DMs counted by
Slack's unread count, missing_scope counted as checked, character caps
for text without spaces, and token_expired sent to several calls at once."
```

---

### Task 3: The app icon and the pixel font

The "Graphite" icon from `design/prototype/icon-explorations.html`, drawn in code from the same ring algorithm. Its artwork follows Apple's icon grid: 824 of 1024 px, inset 100 px. `splark-dev make-icon` writes an `.icns` (via `iconutil`), and `build-app.sh` puts it in the bundle.

The 5×7 pixel font draws workspace initials and digits in pixel tiles.

**Files:**
- Create: `Sources/SplarkKit/AppIconArt.swift`, `Sources/SplarkKit/PixelFont.swift`, `Sources/splark-dev/MakeIconCommand.swift`, `scripts/make-icon.sh`
- Modify: `Sources/splark-dev/main.swift`, `scripts/build-app.sh`
- Test: `Tests/SplarkKitTests/PixelFontTests.swift`

**Interfaces:**
- Consumes: `PixelGrid`, `PixelArt` (Plan 1).
- Produces:
  - `enum PixelFont { static func glyph(_: Character) -> PixelGrid; static func text(_: String) -> PixelGrid }`: 5×7 glyphs for A–Z, 0–9, `+`, `?` and space, with one blank column between them. Lowercase draws as uppercase, and anything else as `?`.
  - `enum AppIconArt { enum Cell { off, core, glow }; static func cell(x:y:) -> Cell; static func cgImage(size: Int) -> CGImage }`.
    - The artwork has a #3a3a40 → #26262b gradient, a #e6e6ea core and a #9c9ca4 glow.
    - It is antialiased only below 128 px.
  - `splark-dev make-icon PATH.icns`, and `scripts/make-icon.sh [OUT]`.
  - `build-app.sh` builds `splark-dev` and writes `Contents/Resources/AppIcon.icns`, with `CFBundleIconFile`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SplarkKitTests/PixelFontTests.swift`:

```swift
import AppKit
import Testing
@testable import SplarkKit

@Suite struct PixelFontTests {
    @Test func glyphsMatchThePrototype() {
        #expect(PixelFont.glyph("L").rendered(level: .bright) == ["#....", "#....", "#....", "#....", "#....", "#....", "#####"])
        #expect(PixelFont.glyph("I").rendered(level: .bright) == ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"])
        #expect(PixelFont.glyph("2").rendered(level: .bright) == [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"])
    }

    @Test func coversLettersAndDigitsInSevenRows() {
        for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+?" {
            #expect(PixelFont.glyph(ch).height == 7, "\(ch)")
            #expect(PixelFont.glyph(ch).litPoints(level: .bright).count > 0, "\(ch)")
        }
        #expect(Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".map { PixelFont.glyph($0).rendered(level: .bright) }).count == 36)
    }

    @Test func lowercaseIsUppercaseAndUnknownIsAQuestionMark() {
        #expect(PixelFont.glyph("l") == PixelFont.glyph("L"))
        #expect(PixelFont.glyph("ж") == PixelFont.glyph("?"))
    }

    @Test func textSetsGlyphsSideBySideWithAGap() {
        let lc = PixelFont.text("LC")
        #expect(lc.width == 5 + 1 + 5 && lc.height == 7)
        #expect(lc.rendered(level: .bright)[6] == "#####..###.")
    }
}

@Suite struct AppIconArtTests {
    @Test func theSparkSitsAtTwiceItsSizeInTheMiddle() {
        #expect(AppIconArt.cell(x: 19, y: 19) == .core)
        #expect(AppIconArt.cell(x: 0, y: 0) == .off)
        var cores = 0
        for y in 0..<40 { for x in 0..<40 where AppIconArt.cell(x: x, y: y) == .core { cores += 1 } }
        #expect(cores == 45 * 4)
    }

    @Test func glowRingsAreDitheredAsInThePrototype() {
        // (9, 19) is the spark's left tip; one cell further left is in the 50% ring, on even x+y only.
        #expect(AppIconArt.cell(x: 9, y: 19) == .core)
        #expect(AppIconArt.cell(x: 8, y: 19) == .off)          // 8 + 19 is odd
        #expect(AppIconArt.cell(x: 7, y: 19) == .glow)         // distance 2, 7 + 19 even
        #expect(AppIconArt.cell(x: 6, y: 18) == .glow)         // distance ~3.2: the 25% ring, even x and even y
        #expect(AppIconArt.cell(x: 16, y: 6) == .glow)         // distance ~4.2: the sparse ring, x % 4 == 0 and y % 4 == 2
        #expect(AppIconArt.cell(x: 5, y: 18) == .off)          // distance ~4.1, but not on the sparse grid
        #expect(AppIconArt.cell(x: 4, y: 18) == .off)          // just over 5 cells out
    }

    @Test func rendersAtAnySizeInsideApplesIconGrid() throws {
        let image = AppIconArt.cgImage(size: 1024)
        #expect(image.width == 1024 && image.height == 1024)
        let rep = NSBitmapImageRep(cgImage: image)
        #expect((rep.colorAt(x: 40, y: 40)?.alphaComponent ?? 1) < 0.01)            // outside the tile: transparent
        // colorAt gives the stored sRGB components (converting them again would shift them).
        let center = try #require(rep.colorAt(x: 512, y: 512))
        #expect(abs(center.redComponent - 0xe6 / 255.0) < 0.02)                        // the spark's core colour
        let tile = try #require(rep.colorAt(x: 512, y: 140))                           // near the top: the gradient's lighter end
        #expect(tile.alphaComponent > 0.99 && abs(tile.redComponent - 0x3a / 255.0) < 0.04)
        #expect(AppIconArt.cgImage(size: 16).width == 16)
    }
}

```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift build --build-tests`
Expected: the build fails: `cannot find 'PixelFont' in scope`, `cannot find 'AppIconArt' in scope`

- [ ] **Step 3: Implement**

Create `Sources/SplarkKit/AppIconArt.swift`:

```swift
import CoreGraphics
import Foundation

/// The "Graphite" app icon (spec §4.1), drawn from the same pixel definitions as the menu-bar spark.
///
/// The design is a 100-unit square: a rounded rectangle (radius 22.4) with a vertical gradient from #3a3a40 to #26262b,
/// and over its inner 80 units a 40×40 grid: the soft spark at twice its size in #e6e6ea, and around it three dithered
/// glow rings in #9c9ca4 (50% up to 2 cells out, 25% up to 3.6, sparse up to 5). Rendered inside Apple's macOS icon grid
/// (the tile is 824 of 1024), like other apps' icons.
public enum AppIconArt {
    public enum Cell: Sendable, Equatable { case off, core, glow }

    static let gridSize = 40, sparkOffset = 9

    private static func isSpark(_ x: Int, _ y: Int) -> Bool {
        guard x >= sparkOffset, y >= sparkOffset, x < sparkOffset + 22, y < sparkOffset + 22 else { return false }
        return PixelArt.spark[(x - sparkOffset) / 2, (y - sparkOffset) / 2]
    }

    /// One cell of the 40×40 grid, exactly as the prototype draws it.
    public static func cell(x: Int, y: Int) -> Cell {
        var distance = 99.0
        outer: for dy in -5...5 {
            for dx in -5...5 where isSpark(x + dx, y + dy) {
                distance = min(distance, hypot(Double(dx), Double(dy)))
                if distance == 0 { break outer }
            }
        }
        switch distance {
        case 0: return .core
        case ...2: return (x + y) % 2 == 0 ? .glow : .off
        case ...3.6: return x % 2 == 0 && y % 2 == 0 ? .glow : .off
        case ...5: return x % 4 == 0 && y % 4 == 2 ? .glow : .off
        default: return .off
        }
    }

    /// The icon as a `size`×`size` bitmap with a transparent margin.
    public static func cgImage(size: Int) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // 100 design units across the 824/1024 tile, centred; flip so y runs downwards, as in the design.
        let unit = CGFloat(size) * 824 / 1024 / 100
        let inset = CGFloat(size) * 100 / 1024
        context.translateBy(x: inset, y: CGFloat(size) - inset)
        context.scaleBy(x: unit, y: -unit)

        let tile = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 100, height: 100), cornerWidth: 22.4, cornerHeight: 22.4, transform: nil)
        context.addPath(tile)
        context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(0x3a3a40), rgb(0x26262b)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 100), options: [])

        context.setShouldAntialias(size < 128)   // crisp pixels where a cell is 2 device pixels or more; soft below that
        for y in 0..<gridSize {
            for x in 0..<gridSize {
                let kind = cell(x: x, y: y)
                guard kind != .off else { continue }
                context.setFillColor(kind == .core ? rgb(0xe6e6ea) : rgb(0x9c9ca4))
                context.fill(CGRect(x: 10 + CGFloat(x) * 2, y: 10 + CGFloat(y) * 2, width: 2, height: 2))
            }
        }
        return context.makeImage()!
    }

    private static func rgb(_ hex: Int) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}
```

Create `Sources/SplarkKit/PixelFont.swift`:

```swift
/// The 5×7 pixel font for initials and digits in setup and Settings (spec §4.1). "I" and "1" are 3 wide.
public enum PixelFont {
    static let glyphs: [Character: [String]] = [
        "A": [".111.", "1...1", "1...1", "11111", "1...1", "1...1", "1...1"],
        "B": ["1111.", "1...1", "1...1", "1111.", "1...1", "1...1", "1111."],
        "C": [".111.", "1...1", "1....", "1....", "1....", "1...1", ".111."],
        "D": ["1111.", "1...1", "1...1", "1...1", "1...1", "1...1", "1111."],
        "E": ["11111", "1....", "1....", "1111.", "1....", "1....", "11111"],
        "F": ["11111", "1....", "1....", "1111.", "1....", "1....", "1...."],
        "G": [".111.", "1...1", "1....", "1.111", "1...1", "1...1", ".1111"],
        "H": ["1...1", "1...1", "1...1", "11111", "1...1", "1...1", "1...1"],
        "I": ["111", ".1.", ".1.", ".1.", ".1.", ".1.", "111"],
        "J": ["..111", "...1.", "...1.", "...1.", "...1.", "1..1.", ".11.."],
        "K": ["1...1", "1..1.", "1.1..", "11...", "1.1..", "1..1.", "1...1"],
        "L": ["1....", "1....", "1....", "1....", "1....", "1....", "11111"],
        "M": ["1...1", "11.11", "1.1.1", "1.1.1", "1...1", "1...1", "1...1"],
        "N": ["1...1", "11..1", "1.1.1", "1..11", "1...1", "1...1", "1...1"],
        "O": [".111.", "1...1", "1...1", "1...1", "1...1", "1...1", ".111."],
        "P": ["1111.", "1...1", "1...1", "1111.", "1....", "1....", "1...."],
        "Q": [".111.", "1...1", "1...1", "1...1", "1.1.1", "1..1.", ".11.1"],
        "R": ["1111.", "1...1", "1...1", "1111.", "1.1..", "1..1.", "1...1"],
        "S": [".1111", "1....", "1....", ".111.", "....1", "....1", "1111."],
        "T": ["11111", "..1..", "..1..", "..1..", "..1..", "..1..", "..1.."],
        "U": ["1...1", "1...1", "1...1", "1...1", "1...1", "1...1", ".111."],
        "V": ["1...1", "1...1", "1...1", "1...1", "1...1", ".1.1.", "..1.."],
        "W": ["1...1", "1...1", "1...1", "1.1.1", "1.1.1", "1.1.1", ".1.1."],
        "X": ["1...1", "1...1", ".1.1.", "..1..", ".1.1.", "1...1", "1...1"],
        "Y": ["1...1", "1...1", ".1.1.", "..1..", "..1..", "..1..", "..1.."],
        "Z": ["11111", "....1", "...1.", "..1..", ".1...", "1....", "11111"],
        "0": [".111.", "1...1", "1..11", "1.1.1", "11..1", "1...1", ".111."],
        "1": [".1.", "11.", ".1.", ".1.", ".1.", ".1.", "111"],
        "2": [".111.", "1...1", "....1", "...1.", "..1..", ".1...", "11111"],
        "3": ["11111", "...1.", "..1..", "...1.", "....1", "1...1", ".111."],
        "4": ["...1.", "..11.", ".1.1.", "1..1.", "11111", "...1.", "...1."],
        "5": ["11111", "1....", "1111.", "....1", "....1", "1...1", ".111."],
        "6": ["..11.", ".1...", "1....", "1111.", "1...1", "1...1", ".111."],
        "7": ["11111", "....1", "...1.", "..1..", ".1...", ".1...", ".1..."],
        "8": [".111.", "1...1", "1...1", ".111.", "1...1", "1...1", ".111."],
        "9": [".111.", "1...1", "1...1", ".1111", "....1", "...1.", ".11.."],
        "+": [".....", "..1..", "..1..", "11111", "..1..", "..1..", "....."],
        "?": [".111.", "1...1", "....1", "...1.", "..1..", ".....", "..1.."],
        " ": ["...", "...", "...", "...", "...", "...", "..."],
    ]

    /// Lowercase is drawn as uppercase; anything else the font lacks as "?".
    public static func glyph(_ character: Character) -> PixelGrid {
        let rows = glyphs[Character(character.uppercased())] ?? glyphs["?"]!
        return PixelGrid(rows: rows.map { $0.replacingOccurrences(of: "1", with: "#") })
    }

    /// The glyphs side by side, one blank column between them.
    public static func text(_ string: String) -> PixelGrid {
        let grids = string.map(glyph)
        guard !grids.isEmpty else { return PixelGrid(rows: ["."]) }
        let rows = (0..<7).map { y in
            grids.map { grid in String((0..<grid.width).map { grid[$0, y] ? "#" : "." }) }.joined(separator: ".")
        }
        return PixelGrid(rows: rows)
    }
}
```

Create `Sources/splark-dev/MakeIconCommand.swift`:

```swift
import AppKit
import SplarkKit

/// Renders the app icon at every size macOS asks for and packs them into an .icns (spec §12).
func makeIconCommand() throws {
    guard args.count >= 2 else { fail("usage: splark-dev make-icon OUT.icns") }
    let out = URL(fileURLWithPath: args[1])
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Splark-\(UUID().uuidString).iconset")
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: iconset) }
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            guard let png = NSBitmapImageRep(cgImage: AppIconArt.cgImage(size: points * scale)).representation(using: .png, properties: [:]) else {
                fail("couldn't encode \(name)")
            }
            try png.write(to: iconset.appendingPathComponent(name))
        }
    }
    try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    _ = try ProcessRunner(timeout: 30).run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", out.path])
    guard FileManager.default.fileExists(atPath: out.path) else { fail("iconutil didn't write \(out.path)") }
    print(out.path)
}
```

In `Sources/splark-dev/main.swift`, replace:

```swift
  triage-eval [--model M]             score the triage evaluation set against your ChatGPT plan
"""
```

with:

```swift
  triage-eval [--model M]             score the triage evaluation set against your ChatGPT plan
  make-icon OUT.icns                  render the app icon at every size and pack it with iconutil
"""
```

In `Sources/splark-dev/main.swift`, replace:

```swift
    case "triage-eval": try await triageEvalCommand()
    default: print(usage)
```

with:

```swift
    case "triage-eval": try await triageEvalCommand()
    case "make-icon": try makeIconCommand()
    default: print(usage)
```

In `scripts/build-app.sh`, replace:

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
```

with:

```bash
#!/usr/bin/env bash
# Builds Splark.app into build/ from the SwiftPM "Splark" product, with its icon rendered from PixelArt, and ad-hoc signs it.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG" --product Splark
swift build -c "$CONFIG" --product splark-dev
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/Splark.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Splark" "$APP/Contents/MacOS/Splark"
cp Support/Info.plist "$APP/Contents/Info.plist"
"$BIN_DIR/splark-dev" make-icon "$APP/Contents/Resources/AppIcon.icns" > /dev/null
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
codesign --force --options runtime --sign - "$APP"
```

Create `scripts/make-icon.sh`:

```bash
#!/usr/bin/env bash
# Renders the app icon from PixelArt into an .icns (default build/AppIcon.icns). build-app.sh runs this for you.
set -euo pipefail
cd "$(dirname "$0")/.."
swift run -c release splark-dev make-icon "${1:-build/AppIcon.icns}"
```

Make it executable: `chmod +x scripts/make-icon.sh`

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test`
Expected: PASS, `✔ Test run with 258 tests`. `swift build --build-tests` prints no warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/SplarkKit/AppIconArt.swift Sources/SplarkKit/PixelFont.swift Sources/splark-dev/MakeIconCommand.swift Sources/splark-dev/main.swift Tests/SplarkKitTests/PixelFontTests.swift scripts/build-app.sh scripts/make-icon.sh
git commit -m "Draw the app icon and the pixel font from PixelArt" -m "The Graphite icon on Apple's grid, rendered into the bundle's icns at
build time, and a 5x7 pixel font for initials and digits."
```

- [ ] **Step 6: Look at the icon**

Run: `./scripts/make-icon.sh /tmp/AppIcon.icns && sips -s format png --resampleWidth 512 /tmp/AppIcon.icns --out /tmp/icon.png`
Expected: Read `/tmp/icon.png`. A dark graphite rounded square, inset from the canvas edge, with a light pixel spark and a grey glow, like the "Graphite" option in `icon-explorations.html`.

---

### Task 4: SplarkUI: the palette, pixel views and offscreen snapshots

A new library target, `SplarkUI`, holds every view and controller, so tests can reach them. The `Splark` app target keeps only `main.swift` and `AppDelegate`.
- **Palette:** the spec §4.1 palette, for light and dark.
- **Pixel views:** the spark and pixel text as SwiftUI views.
- **Snapshots:** `Snapshot.png` renders any view offscreen with `ImageRenderer`. It is how tests and `splark-dev render-ui` see the UI, since the shell can't take screenshots.

`ImageRenderer` can't draw AppKit-backed controls (text fields, switches, menus, scroll views). Views read `\.isSnapshot` and draw look-alikes when it's set.

**Files:**
- Create: `Sources/SplarkUI/PixelViews.swift`, `Sources/SplarkUI/Snapshot.swift`, `Sources/SplarkUI/Theme.swift`
- Modify: `Package.swift`
- Test: `Tests/SplarkUITests/ThemeTests.swift`

**Interfaces:**
- Consumes: `PixelArt`, `PixelGrid`, `SparkLevel`, `PixelFont` (Task 3).
- Produces:
  - In `Package.swift`: the library `SplarkUI` (depends on `SplarkKit`), and its test target `SplarkUITests`. `Splark` and `splark-dev` depend on both libraries.
  - `struct Ink: ShapeStyle` (`Ink(0x232327)`, `Ink(0, opacity: 0)`, `.color`).
  - `struct Palette` (`Palette(scheme)`). Its colours: text, secondary, tertiary, spark, rowHover, separator, chip, chipHover, inputBackground, panelBackground, panelBorder, knock, toastBackground, window, windowBorder, button, buttonText, tile, tileText, field, fieldBorder.
  - `enum Theme`:
    - `panelWidth = 372`, `panelCorner = 18`, `panelMaxScreenFraction = 0.7`;
    - `leadWeight`;
    - `font(_ size:_ weight:) -> Font`.
  - `PixelGridView(grid:level:scale:)`, `SparkView(level:scale:)`, `PixelText(_:scale:)` and `CyclingSpark()` (a spark cycling through its levels).
  - `EnvironmentValues.isSnapshot` and `Snapshot.png(_:scheme:scale:) -> Data?`.

- [ ] **Step 1: Write the failing tests**

This step also changes `Package.swift`, so that the new tests are built at all.

In `Package.swift`, replace:

```swift
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
```

with:

```swift
        .library(name: "SplarkKit", targets: ["SplarkKit"]),
        .library(name: "SplarkUI", targets: ["SplarkUI"]),
        .executable(name: "Splark", targets: ["Splark"]),
        .executable(name: "splark-dev", targets: ["splark-dev"]),
    ],
    targets: [
        .target(name: "SplarkKit"),
        .target(name: "SplarkUI", dependencies: ["SplarkKit"]),
        .executableTarget(name: "Splark", dependencies: ["SplarkKit", "SplarkUI"]),
        .executableTarget(name: "splark-dev", dependencies: ["SplarkKit", "SplarkUI"]),
        .testTarget(name: "SplarkKitTests", dependencies: ["SplarkKit"]),
        .testTarget(name: "SplarkUITests", dependencies: ["SplarkUI", "SplarkKit"]),
    ]
```

Create `Tests/SplarkUITests/ThemeTests.swift`:

```swift
import AppKit
import SwiftUI
import Testing
@testable import SplarkKit
@testable import SplarkUI

/// Reads one pixel of a PNG rendered by `Snapshot`, as stored (0–255).
func pixel(_ png: Data, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    let rep = NSBitmapImageRep(data: png)!
    let c = rep.colorAt(x: x, y: y)!
    return (Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()), Int((c.alphaComponent * 255).rounded()))
}

@MainActor @Suite struct ThemeTests {
    @Test func thePaletteIsTheSpecs() {
        #expect(Palette(.light).text.hex == 0x3a3a3e && Palette(.dark).text.hex == 0xdcdce0)
        #expect(Palette(.light).secondary.hex == 0x7d7d83 && Palette(.dark).secondary.hex == 0x98989e)
        #expect(Palette(.light).tertiary.hex == 0xadadb3 && Palette(.dark).tertiary.hex == 0x696970)
        #expect(Palette(.light).spark.hex == 0x6a6a70 && Palette(.dark).spark.hex == 0xb4b4ba)
    }

    @Test func thePanelIsThePrototypesSize() {
        #expect(Theme.panelWidth == 372 && Theme.panelCorner == 18)
    }

    @Test func sparkViewDrawsCrispPixelsAtTheGivenScale() throws {
        let png = try #require(Snapshot.png(SparkView(level: .bright, scale: 2).foregroundStyle(.black), scheme: .light, scale: 1))
        let rep = try #require(NSBitmapImageRep(data: png))
        #expect(rep.pixelsWide == 22 && rep.pixelsHigh == 22)
        #expect(pixel(png, x: 11, y: 11).a == 255)        // the centre is lit
        #expect(pixel(png, x: 0, y: 0).a == 0)            // the corner isn't
        #expect(pixel(png, x: 10, y: 1).a == 255 && pixel(png, x: 9, y: 1).a == 0)   // the tip is exactly two pixels wide
    }

    @Test func pixelTextIsSevenRowsHigh() throws {
        let png = try #require(Snapshot.png(PixelText("LC", scale: 2).foregroundStyle(.black), scheme: .light, scale: 1))
        let rep = try #require(NSBitmapImageRep(data: png))
        #expect(rep.pixelsWide == (5 + 1 + 5) * 2 && rep.pixelsHigh == 14)
    }

    @Test func snapshotsRenderInDarkMode() throws {
        let png = try #require(Snapshot.png(Rectangle().fill(Palette(.dark).text).frame(width: 4, height: 4), scheme: .dark, scale: 1))
        #expect(pixel(png, x: 2, y: 2).r == 0xdc)
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift build --build-tests`
Expected: the build fails: `Source files for target SplarkUI should be located under 'Sources/SplarkUI'`. The target is declared, but its sources don't exist yet.

- [ ] **Step 3: Implement**

Create `Sources/SplarkUI/PixelViews.swift`:

```swift
import SplarkKit
import SwiftUI

/// A 1-bit pixel grid, drawn crisply: one grid pixel is `scale` points. Its colour is the foreground style.
public struct PixelGridView: View {
    let grid: PixelGrid
    let level: SparkLevel
    let scale: CGFloat

    public init(grid: PixelGrid, level: SparkLevel = .bright, scale: CGFloat = 1) {
        self.grid = grid
        self.level = level
        self.scale = scale
    }

    public var body: some View {
        Canvas { context, _ in
            var path = Path()
            for point in grid.litPoints(level: level) {
                path.addRect(CGRect(x: CGFloat(point.x) * scale, y: CGFloat(point.y) * scale, width: scale, height: scale))
            }
            context.fill(path, with: .foreground)
        }
        .frame(width: CGFloat(grid.width) * scale, height: CGFloat(grid.height) * scale)
        .accessibilityHidden(true)
    }
}

/// The soft spark at a level (spec §4.1).
public struct SparkView: View {
    let level: SparkLevel
    let scale: CGFloat

    public init(level: SparkLevel, scale: CGFloat = 1) {
        self.level = level
        self.scale = scale
    }

    public var body: some View { PixelGridView(grid: PixelArt.spark, level: level, scale: scale) }
}

/// Text in the 5×7 pixel font: workspace initials, step numbers.
public struct PixelText: View {
    let text: String
    let scale: CGFloat

    public init(_ text: String, scale: CGFloat = 2) {
        self.text = text
        self.scale = scale
    }

    public var body: some View { PixelGridView(grid: PixelFont.text(text), scale: scale) }
}

/// The spark cycling through its three levels while Splark works (spec §4.3: "with a cycling spark").
public struct CyclingSpark: View {
    public init() {}

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
            SparkView(level: [SparkLevel.dimmed, .brighter, .bright][step])
        }
    }
}
```

Create `Sources/SplarkUI/Snapshot.swift`:

```swift
import AppKit
import SwiftUI

/// Renders a SwiftUI view offscreen to PNG: for tests, `splark-dev render-ui` and the PR's screenshots.
@MainActor public enum Snapshot {
    public static func png<V: View>(_ view: V, scheme: ColorScheme, scale: CGFloat = 2) -> Data? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
```

Create `Sources/SplarkUI/Theme.swift`:

```swift
import AppKit
import SwiftUI

/// A colour from the prototypes: a hex RGB value and an opacity. Usable anywhere SwiftUI takes a `ShapeStyle`.
public struct Ink: ShapeStyle, Equatable, Sendable {
    public let hex: Int
    public let opacity: Double

    public init(_ hex: Int, opacity: Double = 1) {
        self.hex = hex
        self.opacity = opacity
    }

    public var color: Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: opacity)
    }

    public func resolve(in environment: EnvironmentValues) -> Color { color }
}

/// The prototypes' palette (spec §4.1), light and dark. Views take it from the colour scheme: `Palette(scheme)`.
public struct Palette: Equatable, Sendable {
    public let text, secondary, tertiary, spark: Ink
    public let rowHover, separator, chip, chipHover, inputBackground, panelBackground, panelBorder, knock, toastBackground: Ink

    public init(_ scheme: ColorScheme) {
        if scheme == .dark {
            text = Ink(0xdcdce0); secondary = Ink(0x98989e); tertiary = Ink(0x696970); spark = Ink(0xb4b4ba)
            rowHover = Ink(0xffffff, opacity: 0.05); separator = Ink(0xffffff, opacity: 0.08)
            chip = Ink(0xffffff, opacity: 0.08); chipHover = Ink(0xffffff, opacity: 0.15)
            inputBackground = Ink(0x000000, opacity: 0.28); panelBackground = Ink(0x26262a, opacity: 0.78)
            panelBorder = Ink(0xffffff, opacity: 0.12); knock = Ink(0x2c2c30)
        } else {
            text = Ink(0x3a3a3e); secondary = Ink(0x7d7d83); tertiary = Ink(0xadadb3); spark = Ink(0x6a6a70)
            rowHover = Ink(0x000000, opacity: 0.04); separator = Ink(0x000000, opacity: 0.07)
            chip = Ink(0x000000, opacity: 0.05); chipHover = Ink(0x000000, opacity: 0.09)
            inputBackground = Ink(0xffffff, opacity: 0.92); panelBackground = Ink(0xf8f8fa, opacity: 0.82)
            panelBorder = Ink(0x000000, opacity: 0.10); knock = Ink(0xf4f4f6)
        }
        toastBackground = Ink(0x1e1e20, opacity: 0.86)
    }
}

/// Sizes and type from the prototypes.
public enum Theme {
    public static let panelWidth: CGFloat = 372
    public static let panelCorner: CGFloat = 18
    public static let panelMaxScreenFraction: CGFloat = 0.7
    /// The CSS weight 590 of bold leads (spec §4.1), between medium and semibold.
    public static let leadWeight = NSFont.Weight(rawValue: 0.29)

    public static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> Font {
        Font(NSFont.systemFont(ofSize: size, weight: weight))
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test`
Expected: PASS, `✔ Test run with 263 tests`. `swift build --build-tests` prints no warnings.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/SplarkUI/PixelViews.swift Sources/SplarkUI/Snapshot.swift Sources/SplarkUI/Theme.swift Tests/SplarkUITests/ThemeTests.swift
git commit -m "Add SplarkUI: the palette, pixel views and offscreen snapshots" -m "A library for the app's views, so tests can reach them, with the spec's
monochrome palette, the pixel spark and font as views, and an offscreen
renderer for tests and render-ui."
```

---

### Task 5: Every word the UI shows, in one presenter

`Presenter` turns engine state into the words and levels the UI shows. It is pure functions, so every case is a unit test and the views stay thin:
- the panel's second header line, most important first;
- the menu-bar item: level, count and accessibility label;
- a workspace's status in Settings;
- relative times ("now", "4m", "1h", "3d").

**Files:**
- Create: `Sources/SplarkUI/Presenter.swift`
- Test: `Tests/SplarkUITests/PresenterTests.swift`

**Interfaces:**
- Consumes: `InboxItem`, `InboxSummary`, `SyncStatus`, `TriageState`, `Workspace` (Plan 2).
- Produces:
  - `struct HeaderStatus { text, working }`.
  - `struct StatusItemContent { level, count: String?, accessibility }`.
  - `struct WorkspaceStatusText { title, detail }`.
  - In `enum Presenter`:
    - `shortTime(_:now:)`, `clockTime(_:)` and `metaLine(_:now:)`;
    - `headerStatus(workspaces:sync:triage:now:) -> HeaderStatus?`;
    - `statusItem(_:showCount:) -> StatusItemContent`;
    - `workspaceStatus(_:sync:now:) -> WorkspaceStatusText`.
  - The header's copy, in priority order:
    - "Offline, showing last results";
    - "X needs reconnecting in Settings", or "X's token stopped working: paste a new one in Settings";
    - "Catching up… N of M conversations";
    - "Summarising N conversation(s)";
    - "Summaries paused", "Summaries paused: sign in again", "Summaries off: this ChatGPT plan can't be used", "Summaries paused: ChatGPT usage limit, back at HH:MM", "Summaries paused until HH:MM";
    - "Reconnect X to grant new permissions".
  - The test helpers `now`, `ago(_:)`, `lumen`, `community`, `item(…)` and `eventually(_:_:)`, which later tasks' tests use. `eventually` polls until a condition holds: tests that wait for something never sleep a fixed time and then check, because with window tests running alongside, the main actor is sometimes late.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SplarkUITests/PresenterTests.swift`:

```swift
import Foundation
import Testing
@testable import SplarkKit
@testable import SplarkUI

let now = Date(timeIntervalSince1970: 1_800_000_000)
func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }
let lumen = Workspace(teamId: "T1", name: "Lumen", userId: "U1", userName: "ivan", url: nil, redirectPort: 53682, appId: "A1")
let community = Workspace(teamId: "T2", name: "Lumen Community", userId: "U9", userName: "ivan", url: nil, redirectPort: nil, appId: nil)

/// Waits for `condition`, polling, for up to `timeout` of real time.
@MainActor func eventually(_ timeout: Duration = .seconds(3), _ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}

/// An inbox item, built the way the app builds them: a snapshot and a summary through `InboxStore`.
@MainActor func item(kind: SnapshotKind = .channel, title: String = "#incidents", team: String = "T1", newest: TimeInterval = 240,
                     replied: Bool = false, reactions: [Reaction] = []) -> InboxItem {
    let key = ItemKey(teamId: team, channelId: "C1", threadTs: kind == .thread ? "1.0" : nil)
    let ts = SlackTS.ts(ago(newest))
    let snapshot = ConversationSnapshot(key: key, kind: kind, title: title,
                                        unread: [SnapshotMessage(ts: ts, authorId: "U2", author: "Marta Ruiz", text: "can I roll back?", mentionsMe: false)],
                                        context: [], moreUnread: false)
    let store = InboxStore()
    store.setWorkspaces([lumen, community])
    var update = SyncUpdate()
    update.upsert(snapshot)
    store.apply(update)
    store.apply([TriageResult(key: key, newestTs: ts, items: [TriageItem(level: .action, lead: "Approve the rollback?", rest: "", reason: "", anchorTs: ts, byAI: true)])])
    if replied { store.markReplied(key) }
    for r in reactions { store.addReaction(r, to: store.items[0].id) }
    return store.items[0]
}

@MainActor @Suite struct PresenterTests {
    @Test(arguments: [
        (10.0, "now"), (59, "now"), (60, "1m"), (240, "4m"), (3599, "59m"), (3600, "1h"), (7200 + 1800, "2h"), (86399, "23h"),
        (86400, "1d"), (6 * 86400, "6d"),
    ] as [(TimeInterval, String)])
    func shortTimes(secondsAgo: TimeInterval, text: String) {
        #expect(Presenter.shortTime(ago(secondsAgo), now: now) == text)
    }

    @Test func aWeekOrMoreShowsTheDate() {
        let date = ago(10 * 86400)
        #expect(Presenter.shortTime(date, now: now) == date.formatted(.dateTime.day().month(.abbreviated)))
    }

    @Test func metaLines() {
        #expect(Presenter.metaLine(item(), now: now) == "4m · #incidents")
        #expect(Presenter.metaLine(item(kind: .thread, title: "#marketing", newest: 2400, reactions: [.eyes]), now: now) == "40m · thread in #marketing · 👀")
        #expect(Presenter.metaLine(item(kind: .dm, title: "Daniel Cho", newest: 1500, replied: true), now: now) == "25m · Daniel Cho · replied")
        #expect(Presenter.metaLine(item(title: "#help", team: "T2", newest: 7200), now: now) == "2h · #help · Lumen Community")
    }

    @Test func headerIsQuietWhenNothingIsHappening() {
        let done = SyncStatus(problem: nil, progress: .init(checked: 300, total: 300))
        #expect(Presenter.headerStatus(workspaces: [lumen], sync: ["T1": done], triage: .idle, now: now) == nil)
    }

    @Test func headerSaysWhatSplarkIsDoingMostImportantFirst() {
        let catching = SyncStatus(problem: nil, progress: .init(checked: 120, total: 300))
        let other = SyncStatus(problem: nil, progress: .init(checked: 5, total: 10))
        #expect(Presenter.headerStatus(workspaces: [lumen, community], sync: ["T1": catching, "T2": other], triage: .summarising(3), now: now)
                == HeaderStatus(text: "Catching up… 125 of 310 conversations", working: true))
        let done = SyncStatus(problem: nil, progress: .init(checked: 3, total: 3))
        #expect(Presenter.headerStatus(workspaces: [lumen], sync: ["T1": done], triage: .summarising(1), now: now)
                == HeaderStatus(text: "Summarising 1 conversation", working: true))
        let offline = SyncStatus(problem: .offline(retryAt: now), progress: .init(checked: 1, total: 3))
        #expect(Presenter.headerStatus(workspaces: [lumen], sync: ["T1": offline], triage: .summarising(2), now: now)
                == HeaderStatus(text: "Offline, showing last results", working: false))
    }

    @Test(arguments: [
        (TriagePause.byUser, "Summaries paused"),
        (.signedOut, "Summaries paused: sign in again"),
        (.notEligible, "Summaries off: this ChatGPT plan can't be used"),
    ])
    func summaryPauses(pause: TriagePause, text: String) {
        #expect(Presenter.headerStatus(workspaces: [], sync: [:], triage: .paused(pause), now: now) == HeaderStatus(text: text, working: false))
    }

    @Test func pausesUntilATimeSayWhen() {
        let at = Calendar.current.date(bySettingHour: 15, minute: 40, second: 0, of: now)!
        let clock = at.formatted(date: .omitted, time: .shortened)
        #expect(Presenter.headerStatus(workspaces: [], sync: [:], triage: .paused(.usageLimit(until: at)), now: now)?.text
                == "Summaries paused: ChatGPT usage limit, back at \(clock)")
        #expect(Presenter.headerStatus(workspaces: [], sync: [:], triage: .paused(.budget(until: at)), now: now)?.text == "Summaries paused until \(clock)")
    }

    @Test func workspaceProblemsReachTheHeader() {
        let revoked = SyncStatus(problem: .tokenRevoked)
        #expect(Presenter.headerStatus(workspaces: [lumen], sync: ["T1": revoked], triage: .idle, now: now)?.text == "Lumen needs reconnecting in Settings")
        let pasted = SyncStatus(problem: .reauthorize)
        #expect(Presenter.headerStatus(workspaces: [community], sync: ["T2": pasted], triage: .idle, now: now)?.text
                == "Lumen Community's token stopped working: paste a new one in Settings")
        var scope = SyncStatus()
        scope.missingScope = true
        scope.progress = .init(checked: 1, total: 1)
        #expect(Presenter.headerStatus(workspaces: [lumen], sync: ["T1": scope], triage: .idle, now: now)?.text == "Reconnect Lumen to grant new permissions")
    }

    @Test func theMenuBarShowsTheLevelAndHowManyNeedYou() {
        let three = InboxSummary(needYou: 3, spark: .bright, headline: "3 need you", comments: 1)
        #expect(Presenter.statusItem(three, showCount: true) == StatusItemContent(level: .bright, count: "3", accessibility: "Splark: 3 need you"))
        #expect(Presenter.statusItem(three, showCount: false).count == nil)
        let calm = InboxSummary(needYou: 0, spark: .dimmed, headline: "Nothing needs you", comments: 4)
        #expect(Presenter.statusItem(calm, showCount: true) == StatusItemContent(level: .dimmed, count: nil, accessibility: "Splark: Nothing needs you"))
    }

    @Test func workspaceStatusForSettings() {
        var synced = SyncStatus()
        synced.lastSuccess = ago(120)
        #expect(Presenter.workspaceStatus(lumen, sync: synced, now: now) == WorkspaceStatusText(title: "Connected", detail: "Synced 2m ago"))
        #expect(Presenter.workspaceStatus(lumen, sync: nil, now: now) == WorkspaceStatusText(title: "Connected", detail: "Not synced yet"))
        #expect(Presenter.workspaceStatus(lumen, sync: SyncStatus(problem: .tokenRevoked), now: now).title == "Token revoked")
        #expect(Presenter.workspaceStatus(lumen, sync: SyncStatus(problem: .reauthorize), now: now).title == "Reconnect needed")
        #expect(Presenter.workspaceStatus(community, sync: SyncStatus(problem: .reauthorize), now: now).title == "Token expired")
        #expect(Presenter.workspaceStatus(lumen, sync: SyncStatus(problem: .offline(retryAt: now)), now: now).title == "Offline")
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift build --build-tests`
Expected: the build fails: `cannot find 'Presenter' in scope`, `cannot find 'HeaderStatus' in scope`

- [ ] **Step 3: Implement**

Create `Sources/SplarkUI/Presenter.swift`:

```swift
import Foundation
import SplarkKit

/// The panel header's second line: what Splark is doing, or what's wrong (spec §4.3, §9).
public struct HeaderStatus: Equatable, Sendable {
    public let text: String
    public let working: Bool   // shows the cycling spark
}

/// What the menu-bar item shows (spec §4.2).
public struct StatusItemContent: Equatable, Sendable {
    public let level: SparkLevel
    public let count: String?
    public let accessibility: String
}

/// A workspace's line in Settings (spec §4.5).
public struct WorkspaceStatusText: Equatable, Sendable {
    public let title: String
    public let detail: String
}

/// The words the UI shows, as pure functions of the engine's state.
public enum Presenter {
    /// "now", "4m", "1h", "3d", then the date.
    public static func shortTime(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        case ..<(7 * 86400): return "\(Int(seconds / 86400))d"
        default: return date.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    /// A clock time in the user's format: "14:05" or "2:05 PM".
    public static func clockTime(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    /// "4m · #incidents", "40m · thread in #marketing · 👀", "2h · #help · Lumen Community", "25m · Daniel Cho · replied".
    public static func metaLine(_ item: InboxItem, now: Date) -> String {
        var parts = [shortTime(item.newest, now: now), item.source]
        if let workspace = item.workspaceLabel { parts.append(workspace) }
        if item.replied { parts.append("replied") }
        if !item.reactions.isEmpty { parts.append(item.reactions.map(\.emoji).joined(separator: " ")) }
        return parts.joined(separator: " · ")
    }

    /// The header's second line, most important first: offline, a workspace to reconnect, catching up, summaries,
    /// missing permissions. Nil when there is nothing to say.
    public static func headerStatus(workspaces: [Workspace], sync: [String: SyncStatus], triage: TriageState, now: Date) -> HeaderStatus? {
        let statuses = workspaces.compactMap { workspace in sync[workspace.teamId].map { (workspace, $0) } }
        if statuses.contains(where: { if case .offline? = $0.1.problem { true } else { false } }) {
            return HeaderStatus(text: "Offline, showing last results", working: false)
        }
        if let (workspace, status) = statuses.first(where: { $0.1.problem?.stopsSync == true }) {
            if status.problem == .reauthorize, workspace.redirectPort == nil {
                return HeaderStatus(text: "\(workspace.name)'s token stopped working: paste a new one in Settings", working: false)
            }
            return HeaderStatus(text: "\(workspace.name) needs reconnecting in Settings", working: false)
        }
        let checked = statuses.reduce(0) { $0 + $1.1.progress.checked }, total = statuses.reduce(0) { $0 + $1.1.progress.total }
        if total > 0, checked < total {
            return HeaderStatus(text: "Catching up… \(checked) of \(total) conversations", working: true)
        }
        switch triage {
        case .summarising(let count):
            return HeaderStatus(text: "Summarising \(count) conversation\(count == 1 ? "" : "s")", working: true)
        case .paused(.byUser): return HeaderStatus(text: "Summaries paused", working: false)
        case .paused(.signedOut): return HeaderStatus(text: "Summaries paused: sign in again", working: false)
        case .paused(.notEligible): return HeaderStatus(text: "Summaries off: this ChatGPT plan can't be used", working: false)
        case .paused(.usageLimit(let until)):
            return HeaderStatus(text: "Summaries paused: ChatGPT usage limit, back at \(clockTime(until))", working: false)
        case .paused(.budget(let until)): return HeaderStatus(text: "Summaries paused until \(clockTime(until))", working: false)
        case .idle: break
        }
        if let (workspace, _) = statuses.first(where: { $0.1.missingScope }) {
            return HeaderStatus(text: "Reconnect \(workspace.name) to grant new permissions", working: false)
        }
        return nil
    }

    public static func statusItem(_ summary: InboxSummary, showCount: Bool) -> StatusItemContent {
        StatusItemContent(level: summary.spark, count: showCount && summary.needYou > 0 ? String(summary.needYou) : nil,
                          accessibility: "Splark: \(summary.headline)")
    }

    public static func workspaceStatus(_ workspace: Workspace, sync: SyncStatus?, now: Date) -> WorkspaceStatusText {
        let detail = sync?.lastSuccess.map { "Synced \(shortTime($0, now: now) == "now" ? "just now" : shortTime($0, now: now) + " ago")" } ?? "Not synced yet"
        switch sync?.problem {
        case .tokenRevoked?: return WorkspaceStatusText(title: "Token revoked", detail: detail)
        case .reauthorize?: return WorkspaceStatusText(title: workspace.redirectPort == nil ? "Token expired" : "Reconnect needed", detail: detail)
        case .offline?: return WorkspaceStatusText(title: "Offline", detail: detail)
        case nil: return WorkspaceStatusText(title: sync?.missingScope == true ? "Needs new permissions" : "Connected", detail: detail)
        }
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test`
Expected: PASS, `✔ Test run with 273 tests`. `swift build --build-tests` prints no warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/SplarkUI/Presenter.swift Tests/SplarkUITests/PresenterTests.swift
git commit -m "Put the UI's words in one presenter" -m "The header's second line, the menu-bar item and the workspace statuses as
pure functions of the engine's state, most important first."
```

---

### Task 6: The spark in the menu bar

`StatusItemController` owns the `NSStatusItem` (spec §4.2):
- **Image:** the spark as a template image at the inbox's level.
- **Count:** after it, in monospaced digits.
- **Clicks:** a left click toggles the panel. A right click, ⌥-click or ⌃-click opens the menu: Refresh now (r), Settings… (,), Pause summaries (with a checkmark when paused), and Quit Splark (q).
- **How the menu opens:** it is attached for that one click only, so a left click keeps toggling the panel.

**Files:**
- Create: `Sources/SplarkUI/StatusItemController.swift`
- Test: `Tests/SplarkUITests/StatusItemControllerTests.swift`

**Interfaces:**
- Consumes: `StatusItemContent` (Task 5), `PixelArt.image(_:level:template:)`.
- Produces:
  - `StatusItemController.Handlers(toggle:refresh:settings:pauseSummaries:quit:)`.
  - `StatusItemController(handlers:)` for the real menu bar. The internal `init(button:handlers:)` is for tests.
  - Its members:
    - `buttonFrameOnScreen: NSRect?`;
    - `show(_ content: StatusItemContent)`;
    - `setSummariesPaused(_:)`;
    - `static action(for: NSEvent?) -> ClickAction` (`.togglePanel` or `.showMenu`);
    - `makeMenu(summariesPaused:) -> NSMenu`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SplarkUITests/StatusItemControllerTests.swift`:

```swift
import AppKit
import Testing
@testable import SplarkKit
@testable import SplarkUI

@MainActor final class Calls {
    var log: [String] = []
}

@MainActor @Suite struct StatusItemControllerTests {
    let calls = Calls()

    func controller() -> (StatusItemController, NSButton) {
        let button = NSButton()
        let calls = self.calls
        let handlers = StatusItemController.Handlers(
            toggle: { calls.log.append("toggle") }, refresh: { calls.log.append("refresh") }, settings: { calls.log.append("settings") },
            pauseSummaries: { calls.log.append("pause \($0)") }, quit: { calls.log.append("quit") })
        return (StatusItemController(button: button, handlers: handlers), button)
    }

    @Test func showsTheSparkAndHowManyNeedYou() throws {
        let (c, button) = controller()
        c.show(StatusItemContent(level: .bright, count: "3", accessibility: "Splark: 3 need you"))
        let image = try #require(button.image)
        #expect(image.isTemplate && image.size == NSSize(width: 11, height: 11))
        #expect(button.title == " 3")
        #expect(button.accessibilityLabel() == "Splark: 3 need you")
        c.show(StatusItemContent(level: .dimmed, count: nil, accessibility: "Splark: All caught up"))
        #expect(button.title == "")
    }

    @Test func theMenuHasTheSpecsItems() {
        let (c, _) = controller()
        let menu = c.makeMenu(summariesPaused: true)
        #expect(menu.items.map(\.title) == ["Refresh now", "Settings…", "Pause summaries", "", "Quit Splark"])
        #expect(menu.items.map(\.keyEquivalent) == ["r", ",", "", "", "q"])
        #expect(menu.items[2].state == .on)
        #expect(c.makeMenu(summariesPaused: false).items[2].state == .off)
    }

    @Test func menuItemsCallTheirHandlers() {
        let (c, _) = controller()
        let menu = c.makeMenu(summariesPaused: false)
        for i in [0, 1, 2, 4] {   // what a click on the item does (performActionForItem needs a running app)
            let item = menu.items[i]
            _ = (item.target as? NSObject)?.perform(item.action)
        }
        #expect(calls.log == ["refresh", "settings", "pause true", "quit"])
    }

    @Test func rightClickAndOptionClickOpenTheMenuOthersToggleThePanel() {
        func event(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        #expect(StatusItemController.action(for: event(.leftMouseUp)) == .togglePanel)
        #expect(StatusItemController.action(for: event(.rightMouseUp)) == .showMenu)
        #expect(StatusItemController.action(for: event(.leftMouseUp, .option)) == .showMenu)
        #expect(StatusItemController.action(for: event(.leftMouseUp, .control)) == .showMenu)
        #expect(StatusItemController.action(for: nil) == .togglePanel)
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift build --build-tests`
Expected: the build fails: `cannot find 'StatusItemController' in scope`

- [ ] **Step 3: Implement**

Create `Sources/SplarkUI/StatusItemController.swift`:

```swift
import AppKit
import SplarkKit

/// The menu-bar item (spec §4.2): the spark at the inbox's level, and how many items need you. A left click toggles
/// the panel; a right click, ⌥-click or ⌃-click opens the menu.
@MainActor public final class StatusItemController: NSObject {
    public struct Handlers {
        let toggle: () -> Void
        let refresh: () -> Void
        let settings: () -> Void
        let pauseSummaries: (Bool) -> Void
        let quit: () -> Void

        public init(toggle: @escaping () -> Void, refresh: @escaping () -> Void, settings: @escaping () -> Void,
                    pauseSummaries: @escaping (Bool) -> Void, quit: @escaping () -> Void) {
            self.toggle = toggle
            self.refresh = refresh
            self.settings = settings
            self.pauseSummaries = pauseSummaries
            self.quit = quit
        }
    }

    public enum ClickAction: Equatable { case togglePanel, showMenu }

    private let statusItem: NSStatusItem?
    private let button: NSButton
    private let handlers: Handlers
    private var summariesPaused = false

    /// The real menu-bar item.
    public convenience init(handlers: Handlers) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.init(statusItem: item, button: item.button!, handlers: handlers)
    }

    /// For tests: any button stands in for the menu bar's.
    convenience init(button: NSButton, handlers: Handlers) {
        self.init(statusItem: nil, button: button, handlers: handlers)
    }

    private init(statusItem: NSStatusItem?, button: NSButton, handlers: Handlers) {
        self.statusItem = statusItem
        self.button = button
        self.handlers = handlers
        super.init()
        button.imagePosition = .imageLeft
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// The button's frame on screen, for placing the panel under it.
    public var buttonFrameOnScreen: NSRect? {
        guard let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    public func show(_ content: StatusItemContent) {
        button.image = PixelArt.image(PixelArt.spark, level: content.level, template: true)
        button.title = content.count.map { " \($0)" } ?? ""
        button.setAccessibilityLabel(content.accessibility)
    }

    public func setSummariesPaused(_ paused: Bool) { summariesPaused = paused }

    public static func action(for event: NSEvent?) -> ClickAction {
        guard let event else { return .togglePanel }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.option) || event.modifierFlags.contains(.control) { return .showMenu }
        return .togglePanel
    }

    public func makeMenu(summariesPaused: Bool) -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ key: String, _ action: Selector) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
            return item
        }
        _ = add("Refresh now", "r", #selector(refresh))
        _ = add("Settings…", ",", #selector(settings))
        add("Pause summaries", "", #selector(togglePause)).state = summariesPaused ? .on : .off
        menu.addItem(.separator())
        _ = add("Quit Splark", "q", #selector(quit))
        return menu
    }

    @objc private func clicked() {
        switch Self.action(for: NSApp.currentEvent) {
        case .togglePanel: handlers.toggle()
        case .showMenu:
            // Attach the menu for this one click, so a left click keeps toggling the panel.
            statusItem?.menu = makeMenu(summariesPaused: summariesPaused)
            button.performClick(nil)
            statusItem?.menu = nil
        }
    }

    @objc private func refresh() { handlers.refresh() }
    @objc private func settings() { handlers.settings() }
    @objc private func togglePause() { handlers.pauseSummaries(!summariesPaused) }
    @objc private func quit() { handlers.quit() }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test`
Expected: PASS, `✔ Test run with 277 tests`. `swift build --build-tests` prints no warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/SplarkUI/StatusItemController.swift Tests/SplarkUITests/StatusItemControllerTests.swift
git commit -m "Show the spark in the menu bar, with its menu" -m "A template spark at the inbox's level with the count beside it; a left
click toggles the panel, a right, option or control click opens the menu."
```

---

### Task 7: The panel's behaviour

`PanelModel` is the panel minus its looks (spec §4.3):
- **Rows:** which row is open, and which reply field has focus.
- **Replies:** drafts are kept when sending fails, and an error toast says so.
- **Mark read:** the 4-second undo toast.
- **Esc:** collapses an open row first; with none open, it closes the panel.
- **Open in Slack:** closes the panel.
- **One reply per Enter:** while a reply is on its way, another Enter (or ↑) sends nothing. On a slow network a second press would post the message twice.
- **Reopening:** a closed panel reopens with its rows collapsed.

Views call it, and tests drive it through a fake `PanelActions`.

**Files:**
- Create: `Sources/SplarkUI/PanelModel.swift`
- Modify: `Sources/SplarkKit/Inbox/Actions.swift`
- Test: `Tests/SplarkUITests/PanelModelTests.swift`

**Interfaces:**
- Consumes: `Actions`, `InboxItem`, `Reaction`, `ActionFailure` (Plan 2).
- Produces:
  - `protocol PanelActions` (reply, react, markRead, undo, open), with `extension Actions: PanelActions {}`. `Actions.UndoToken` gains a public `init()`.
  - `PanelModel(actions:toastDuration:close:openSlack:openSettings:)`.
  - Its state: `expanded`, `focusedReply`, `commentsOpen`, `drafts[ItemKey]`, `sending: Set<ItemKey>` and `toast: Toast?` (`Toast { text, undo }`).
  - Its methods: `toggle`, `startReply`, `escape`, `send`, `react`, `markRead`, `markAllRead`, `undo`, `open`, `openSlackApp`, `showSettings`, `showFailure(_:)`, `dismissToast` and `panelClosed()`.
  - Toast copy: "Marked as read" (with Undo), "Marked N as read", "Couldn't send. Try again.", "Couldn't add the reaction. Try again."

- [ ] **Step 1: Write the failing tests**

Create `Tests/SplarkUITests/PanelModelTests.swift`:

```swift
import Foundation
import Testing
@testable import SplarkKit
@testable import SplarkUI

/// Records what the panel asked for; can be told to fail.
@MainActor final class FakeActions: PanelActions {
    var replies: [(String, String)] = []
    var reactions: [Reaction] = []
    var marked: [[String]] = []
    var undone: [Actions.UndoToken] = []
    var opened: [String] = []
    var failReply = false, failReact = false
    var holdReplies = false
    var replyCalls = 0
    private var replyGates: [CheckedContinuation<Void, Never>] = []
    let token = Actions.UndoToken()

    func reply(to item: InboxItem, text: String) async throws {
        replyCalls += 1
        if holdReplies { await withCheckedContinuation { replyGates.append($0) } }
        if failReply { throw ActionError.offline }
        replies.append((item.key.channelId, text))
    }
    func releaseReplies() {
        replyGates.forEach { $0.resume() }
        replyGates = []
    }
    func react(to item: InboxItem, with reaction: Reaction) async throws {
        if failReact { throw ActionError.slack("not_reactable") }
        reactions.append(reaction)
    }
    func markRead(_ items: [InboxItem]) -> Actions.UndoToken {
        marked.append(items.map(\.key.channelId))
        return token
    }
    func undo(_ token: Actions.UndoToken) { undone.append(token) }
    func open(_ item: InboxItem) async { opened.append(item.key.channelId) }
}

@MainActor @Suite struct PanelModelTests {
    let actions = FakeActions()
    let calls = Calls()

    func model(toast: Duration = .seconds(4)) -> PanelModel {
        let calls = self.calls
        return PanelModel(actions: actions, toastDuration: toast, close: { calls.log.append("close") },
                          openSlack: { calls.log.append("slack") }, openSettings: { calls.log.append("settings") })
    }

    @Test func clickingARowExpandsItAndClickingAgainCollapses() {
        let m = model(), row = item()
        m.toggle(row)
        #expect(m.expanded == row.id)
        m.toggle(row)
        #expect(m.expanded == nil)
    }

    @Test func escapeCollapsesFirstThenCloses() {
        let m = model()
        m.toggle(item())
        m.escape()
        #expect(m.expanded == nil && calls.log.isEmpty)
        m.escape()
        #expect(calls.log == ["close"])
    }

    @Test func sendingAReplyClearsItAndCollapses() async {
        let m = model(), row = item()
        m.startReply(row)
        #expect(m.expanded == row.id && m.focusedReply == row.id)
        m.drafts[row.key] = "  on it  "
        await m.send(row)
        #expect(actions.replies.map(\.1) == ["  on it  "])
        #expect(m.drafts[row.key] == nil && m.expanded == nil)
    }

    @Test func aBlankReplyIsNotSent() async {
        let m = model(), row = item()
        m.drafts[row.key] = "   "
        await m.send(row)
        #expect(actions.replies.isEmpty)
    }

    @Test func aFailedReplyKeepsTheTextAndSaysSo() async {
        actions.failReply = true
        let m = model(), row = item()
        m.toggle(row)
        m.drafts[row.key] = "on it"
        await m.send(row)
        #expect(m.drafts[row.key] == "on it" && m.expanded == row.id)
        #expect(m.toast == PanelModel.Toast(text: "Couldn't send. Try again.", undo: nil))
    }

    @Test func markReadOffersUndoForFourSeconds() async throws {
        let m = model(toast: .milliseconds(80)), row = item()
        m.toggle(row)
        m.markRead(row)
        #expect(actions.marked == [["C1"]] && m.expanded == nil)
        #expect(m.toast == PanelModel.Toast(text: "Marked as read", undo: actions.token))
        #expect(await eventually { m.toast == nil })
    }

    @Test func undoPutsItBack() {
        let m = model(), row = item()
        m.markRead(row)
        m.undo()
        #expect(actions.undone == [actions.token] && m.toast == nil)
    }

    @Test func markAllCommentsRead() {
        let m = model()
        m.commentsOpen = true
        m.markAllRead([item(), item()])
        #expect(actions.marked == [["C1", "C1"]])
        #expect(m.toast?.text == "Marked 2 as read" && !m.commentsOpen)
    }

    @Test func openingInSlackClosesThePanel() async {
        let m = model()
        await m.open(item())
        #expect(actions.opened == ["C1"] && calls.log == ["close"])
    }

    @Test func aFailedReactionSaysSo() async {
        actions.failReact = true
        let m = model()
        await m.react(item(), .eyes)
        #expect(m.toast?.text == "Couldn't add the reaction. Try again.")
    }

    @Test func failuresFromLaterReachTheToast() {
        let m = model()
        m.showFailure(ActionFailure(key: ItemKey(teamId: "T1", channelId: "C1"), message: "Couldn't mark it as read. Try again."))
        #expect(m.toast == PanelModel.Toast(text: "Couldn't mark it as read. Try again.", undo: nil))
    }

    @Test func headerButtons() {
        let m = model()
        m.openSlackApp()
        m.showSettings()
        #expect(calls.log == ["slack", "close", "settings", "close"])
    }

    /// Slack can be slow: a second Enter (or a click on ↑) while the first reply is on its way sends nothing.
    @Test func aSecondSendWhileTheFirstIsOnItsWaySendsNothing() async throws {
        actions.holdReplies = true
        let m = model(), row = item(kind: .dm, title: "Marta Ruiz")
        m.startReply(row)
        m.drafts[row.key] = "on it"
        let first = Task { await m.send(row) }
        #expect(await eventually { actions.replyCalls == 1 })
        #expect(m.sending.contains(row.key))
        let second = Task { await m.send(row) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(actions.replyCalls == 1)
        actions.releaseReplies()
        await first.value
        await second.value
        #expect(actions.replies.map(\.1) == ["on it"] && m.sending.isEmpty)
    }

    @Test func closingThePanelCollapsesTheOpenRow() {
        let m = model(), row = item()
        m.startReply(row)
        m.panelClosed()
        #expect(m.expanded == nil && m.focusedReply == nil)
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift build --build-tests`
Expected: the build fails: `cannot find 'PanelModel' in scope`, `cannot find type 'PanelActions' in scope`

- [ ] **Step 3: Implement**

In `Sources/SplarkKit/Inbox/Actions.swift`, replace:

```swift
public final class Actions {
    public struct UndoToken: Hashable, Sendable { let id = UUID() }

```

with:

```swift
public final class Actions {
    public struct UndoToken: Hashable, Sendable {
        let id = UUID()
        public init() {}
    }

```

Create `Sources/SplarkUI/PanelModel.swift`:

```swift
import Foundation
import Observation
import SplarkKit

/// What the panel asks of Slack. `Actions` is the real one; tests use a fake.
@MainActor public protocol PanelActions: AnyObject {
    func reply(to item: InboxItem, text: String) async throws
    func react(to item: InboxItem, with reaction: Reaction) async throws
    func markRead(_ items: [InboxItem]) -> Actions.UndoToken
    func undo(_ token: Actions.UndoToken)
    func open(_ item: InboxItem) async
}

extension Actions: PanelActions {}

/// The panel's behaviour, apart from its looks (spec §4.3): which row is open, reply drafts, toasts with undo,
/// and what Esc does.
@MainActor @Observable public final class PanelModel {
    public struct Toast: Equatable {
        public let text: String
        public let undo: Actions.UndoToken?
    }

    public private(set) var expanded: InboxItem.ID?
    public private(set) var focusedReply: InboxItem.ID?
    public var commentsOpen = false
    public var drafts: [ItemKey: String] = [:]   // kept when sending fails
    public private(set) var sending: Set<ItemKey> = []   // replies on their way to Slack
    public private(set) var toast: Toast?

    private let actions: PanelActions
    private let toastDuration: Duration
    private let close: () -> Void
    private let openSlack: () -> Void
    private let openSettings: () -> Void
    private var toastTask: Task<Void, Never>?

    public init(actions: PanelActions, toastDuration: Duration = .seconds(4), close: @escaping () -> Void,
                openSlack: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.actions = actions
        self.toastDuration = toastDuration
        self.close = close
        self.openSlack = openSlack
        self.openSettings = openSettings
    }

    /// A click on a row.
    public func toggle(_ item: InboxItem) {
        expanded = expanded == item.id ? nil : item.id
        focusedReply = nil
    }

    /// The toolbar's Reply: open the row with its reply field focused.
    public func startReply(_ item: InboxItem) {
        expanded = item.id
        focusedReply = item.id
    }

    /// Esc collapses an open row; with none open, it closes the panel.
    public func escape() {
        if expanded != nil {
            expanded = nil
            focusedReply = nil
        } else {
            close()
        }
    }

    /// The panel closed: an open row would only be in the way next time.
    public func panelClosed() {
        expanded = nil
        focusedReply = nil
    }

    /// Enter in the reply field. The draft stays if sending fails; a second Enter while it's on its way does nothing.
    public func send(_ item: InboxItem) async {
        guard let text = drafts[item.key], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !sending.contains(item.key) else { return }
        sending.insert(item.key)
        defer { sending.remove(item.key) }
        do {
            try await actions.reply(to: item, text: text)
            drafts[item.key] = nil
            if expanded == item.id { expanded = nil }
            focusedReply = nil
        } catch {
            show(Toast(text: "Couldn't send. Try again.", undo: nil))
        }
    }

    public func react(_ item: InboxItem, _ reaction: Reaction) async {
        do { try await actions.react(to: item, with: reaction) }
        catch { show(Toast(text: "Couldn't add the reaction. Try again.", undo: nil)) }
    }

    /// The ✓ button: gone at once, with 4 seconds to undo.
    public func markRead(_ item: InboxItem) {
        if expanded == item.id { expanded = nil }
        show(Toast(text: "Marked as read", undo: actions.markRead([item])))
    }

    /// "Just comments" → ✓✓.
    public func markAllRead(_ items: [InboxItem]) {
        guard !items.isEmpty else { return }
        commentsOpen = false
        show(Toast(text: "Marked \(items.count) as read", undo: actions.markRead(items)))
    }

    public func undo() {
        guard let token = toast?.undo else { return }
        actions.undo(token)
        dismissToast()
    }

    /// Open in Slack closes the panel (spec §4.3).
    public func open(_ item: InboxItem) async {
        await actions.open(item)
        close()
    }

    public func openSlackApp() {
        openSlack()
        close()
    }

    public func showSettings() {
        openSettings()
        close()
    }

    /// A failure reported later by `Actions` (a mark-read Slack refused).
    public func showFailure(_ failure: ActionFailure) { show(Toast(text: failure.message, undo: nil)) }

    public func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    private func show(_ toast: Toast) {
        self.toast = toast
        toastTask?.cancel()
        let duration = toastDuration
        toastTask = Task { [weak self] in
            guard (try? await Task.sleep(for: duration)) != nil else { return }
            self?.toast = nil
        }
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test`
Expected: PASS, `✔ Test run with 291 tests`. `swift build --build-tests` prints no warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/SplarkKit/Inbox/Actions.swift Sources/SplarkUI/PanelModel.swift Tests/SplarkUITests/PanelModelTests.swift
git commit -m "Give the panel its behaviour: rows, replies, undo and Esc" -m "Which row is open, reply drafts that survive a failed send, a 4-second
undo for mark read, and Esc that collapses before it closes."
```

---

### Task 8: Draw the panel

The panel's views, following `design/prototype/panel.html`:
- **Header:** the headline, with Open Slack and Settings on hover, and the second line with a cycling spark while working.
- **Rows:** a level spark with the reason as its tooltip, then the meta line, then the bold lead and the rest.
  - On hover, a toolbar (Reply, 👀 ✅ 👍, Open) and a ✓ circle.
  - Expanded: the messages, "and N earlier", the reply field, and the reactions.
- **Just comments:** folded at the bottom, with ✓✓.
- **Toast:** at the bottom of the panel.
- **Empty state:** a dimmed spark and "Nothing unread in Slack."

`Fixtures` builds the prototype's nine conversations through the real `InboxStore`. `PanelGallery` lists every state worth looking at. `splark-dev render-ui` renders them to PNGs in light and dark, for checking against the prototype.

**Files:**
- Create: `Sources/SplarkUI/Fixtures.swift`, `Sources/SplarkUI/Panel/InboxRowView.swift`, `Sources/SplarkUI/Panel/PanelControls.swift`, `Sources/SplarkUI/Panel/PanelView.swift`, `Sources/splark-dev/RenderUICommand.swift`
- Modify: `Sources/SplarkUI/Snapshot.swift`, `Sources/splark-dev/main.swift`
- Test: `Tests/SplarkUITests/PanelViewTests.swift`

**Interfaces:**
- Consumes: `PanelModel` (Task 7), `Presenter` (Task 5), `Theme` and `Snapshot` (Task 4).
- Produces:
  - `PanelView(inbox:status:model:now:layout:onSize:)`, where `Layout` is `.live(maxHeight:)` (scrolls, reports its size) or `.snapshot`.
  - `Fixtures.now`, `Fixtures.workspaces`, `Fixtures.inbox()` and `Fixtures.emptyInbox()`.
  - `PreviewActions` and `PanelGallery.states() -> [(name, AnyView)]`.
  - `splark-dev render-ui [--out DIR]`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SplarkUITests/PanelViewTests.swift`:

```swift
import AppKit
import SwiftUI
import Testing
@testable import SplarkKit
@testable import SplarkUI

@MainActor @Suite struct PanelViewTests {
    func height(_ view: some View) throws -> Int {
        let png = try #require(Snapshot.png(view, scheme: .light, scale: 1))
        let rep = try #require(NSBitmapImageRep(data: png))
        #expect(rep.pixelsWide == 372)
        return rep.pixelsHigh
    }

    func panel(_ inbox: InboxStore, _ configure: (PanelModel) -> Void = { _ in }) -> PanelView {
        let model = PanelModel(actions: PreviewActions(), close: {}, openSlack: {}, openSettings: {})
        configure(model)
        return PanelView(inbox: inbox, status: nil, model: model, now: Fixtures.now, layout: .snapshot)
    }

    @Test func everyStateInTheGalleryRendersInBothSchemes() {
        for (name, view) in PanelGallery.states() {
            for scheme in [ColorScheme.light, .dark] { #expect(Snapshot.png(view, scheme: scheme) != nil, "\(name)") }
        }
    }

    @Test func anOpenRowAndOpenCommentsMakeThePanelTaller() throws {
        let inbox = Fixtures.inbox()
        let closed = try height(panel(inbox))
        #expect(try height(panel(inbox) { $0.toggle(inbox.items[0]) }) > closed + 100)
        #expect(try height(panel(inbox) { $0.commentsOpen = true }) > closed + 150)
    }

    @Test func theEmptyPanelIsShort() throws {
        #expect(try height(panel(Fixtures.emptyInbox())) < 160)
    }

    @Test func theHeadlineFollowsTheInbox() {
        #expect(Fixtures.inbox().summary.headline == "5 need you")
        #expect(Fixtures.emptyInbox().summary.headline == "All caught up")
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift build --build-tests`
Expected: the build fails: `cannot find 'PanelView' in scope`, `cannot find 'PanelGallery' in scope`

- [ ] **Step 3: Implement**

Create `Sources/SplarkUI/Fixtures.swift`:

```swift
import Foundation
import SplarkKit
import SwiftUI

/// The prototype's own conversations (design/prototype/panel.html), built through the real `InboxStore`:
/// for SwiftUI previews, `splark-dev render-ui` and tests.
@MainActor public enum Fixtures {
    /// Thursday 15 October 2026, 14:32 local time: the prototype's clock.
    public static let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 14, minute: 32))!

    public static let workspaces = [
        Workspace(teamId: "T1", name: "Lumen", userId: "U1", userName: "ivan", url: "https://lumen.slack.com/", redirectPort: 53682, appId: "A1"),
        Workspace(teamId: "T2", name: "Lumen Community", userId: "U9", userName: "ivan", url: "https://lumen-community.slack.com/", redirectPort: 53683, appId: "A2"),
    ]

    private struct Conversation {
        let team: String, channel: String, kind: SnapshotKind, title: String
        let level: TriageLevel, lead: String, rest: String, reason: String
        let messages: [(author: String, text: String, clock: String)]
    }

    private static let conversations: [Conversation] = [
        Conversation(team: "T1", channel: "C1", kind: .channel, title: "#incidents", level: .action, lead: "Approve the rollback?",
                     rest: "Checkout is failing for EU cards since the 14:05 deploy; Marta needs your OK.",
                     reason: "Mentions you directly · production impact · waiting on you",
                     messages: [("Deploy Bot", "Deploy v4.12.0 finished (main → prod)", "14:05"),
                                ("Marta Ruiz", "Stripe is declining EU cards since the deploy, ~30% of checkouts failing", "14:24"),
                                ("Marta Ruiz", "@Ivan can I roll back? need your ok, you own billing", "14:28")]),
        Conversation(team: "T1", channel: "D1", kind: .dm, title: "Daniel Cho", level: .action, lead: "Send the signed SOW to Acme",
                     rest: "before 5pm today; legal approved it.", reason: "Direct request · deadline today",
                     messages: [("Daniel Cho", "legal signed off on the Acme SOW 🎉", "14:01"),
                                ("Daniel Cho", "can you send it to their procurement before 5? they close the PO today", "14:07")]),
        Conversation(team: "T1", channel: "C2", kind: .thread, title: "#marketing", level: .question, lead: "Is the pricing-page copy final?",
                     rest: "Priya wants to hand it to design.", reason: "Question in a thread you started",
                     messages: [("Priya Nair", "is the pricing page copy final or still in review? want to hand it to design", "13:52")]),
        Conversation(team: "T1", channel: "D2", kind: .dm, title: "Leo Park", level: .question, lead: "Move tomorrow's 1:1 to Thursday?",
                     rest: "Same time, Leo asks.", reason: "Direct question · needs a yes or no",
                     messages: [("Leo Park", "hey, could we move tomorrow's 1:1 to Thursday same time?", "13:30")]),
        Conversation(team: "T2", channel: "C9", kind: .channel, title: "#help", level: .question, lead: "Does Zapier support custom fields?",
                     rest: "A community member asks; Ines tagged you.", reason: "You were tagged as the person who knows",
                     messages: [("sam.k", "does the zapier integration support custom fields?", "12:20"),
                                ("Ines", "@Ivan you built that one, right?", "12:31")]),
        Conversation(team: "T1", channel: "C3", kind: .channel, title: "#eng", level: .fyi, lead: "CI is moving to the new runners,",
                     rest: "trying it next sprint.", reason: "An update, nothing asked",
                     messages: [("Tom", "new runners are ~2x faster on the integration suite", "13:02"),
                                ("Ana", "let's try next sprint, I'll write the migration ticket", "13:40")]),
        Conversation(team: "T1", channel: "C4", kind: .channel, title: "#general", level: .fyi, lead: "Offsite on Friday:", rest: "the bus leaves at 9:30.",
                     reason: "An announcement", messages: [("Office", "Offsite Friday! Bus leaves 9:30 sharp from the office 🚌", "11:30")]),
        Conversation(team: "T1", channel: "C5", kind: .channel, title: "#random", level: .fyi, lead: "Coffee machine chatter,", rest: "23 messages.",
                     reason: "Chatter", messages: [("Kai", "the new machine makes oat flat whites now ☕️", "14:12")]),
        Conversation(team: "T2", channel: "C8", kind: .channel, title: "#announcements", level: .fyi, lead: "v2.4 release notes", rest: "shared with the community.",
                     reason: "An announcement", messages: [("Ines", "v2.4 is out: bulk edit, faster sync, new Zapier triggers", "09:40")]),
    ]

    /// An inbox holding the prototype's nine conversations: five that need you, four comments.
    public static func inbox() -> InboxStore {
        let store = InboxStore()
        store.setWorkspaces(workspaces)
        var update = SyncUpdate()
        var results: [TriageResult] = []
        for c in conversations {
            let messages = c.messages.map { m in
                SnapshotMessage(ts: SlackTS.ts(at(m.clock)), authorId: nil, author: m.author, text: m.text, mentionsMe: m.text.contains("@Ivan"))
            }
            let key = ItemKey(teamId: c.team, channelId: c.channel, threadTs: c.kind == .thread ? "1739999999.000100" : nil)
            let snapshot = ConversationSnapshot(key: key, kind: c.kind, title: c.title, unread: messages, context: [], moreUnread: false)
            update.upsert(snapshot)
            results.append(TriageResult(key: key, newestTs: snapshot.newestTs,
                                        items: [TriageItem(level: c.level, lead: c.lead, rest: c.rest, reason: c.reason, anchorTs: snapshot.newestTs, byAI: true)]))
        }
        store.apply(update)
        store.apply(results)
        return store
    }

    public static func emptyInbox() -> InboxStore {
        let store = InboxStore()
        store.setWorkspaces(workspaces)
        return store
    }

    /// "14:28" on the fixture day.
    static func at(_ clock: String) -> Date {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now)!
    }
}

/// Actions that do nothing: for previews and renders.
@MainActor public final class PreviewActions: PanelActions {
    public init() {}
    public func reply(to item: InboxItem, text: String) async throws {}
    public func react(to item: InboxItem, with reaction: Reaction) async throws {}
    public func markRead(_ items: [InboxItem]) -> Actions.UndoToken { Actions.UndoToken() }
    public func undo(_ token: Actions.UndoToken) {}
    public func open(_ item: InboxItem) async {}
}

/// Every state of the panel worth looking at, as (file name, view), for `splark-dev render-ui` and the PR.
@MainActor public enum PanelGallery {
    public static func states() -> [(name: String, view: AnyView)] {
        let inbox = Fixtures.inbox()
        let items = inbox.items
        func model(expand: InboxItem? = nil, comments: Bool = false, toast: Bool = false) -> PanelModel {
            let m = PanelModel(actions: PreviewActions(), close: {}, openSlack: {}, openSettings: {})
            if let expand { m.toggle(expand) }
            m.commentsOpen = comments
            if toast { m.markRead(items[3]) }
            return m
        }
        let catching = HeaderStatus(text: "Catching up… 120 of 300 conversations", working: true)
        return [
            ("panel", AnyView(PanelView(inbox: inbox, status: nil, model: model(), now: Fixtures.now, layout: .snapshot))),
            ("panel-hover", AnyView(PanelView(inbox: inbox, status: nil, model: model(), now: Fixtures.now, forceHover: items[1].id))),
            ("panel-expanded", AnyView(PanelView(inbox: inbox, status: nil, model: model(expand: items[0]), now: Fixtures.now, layout: .snapshot))),
            ("panel-comments", AnyView(PanelView(inbox: inbox, status: catching, model: model(comments: true), now: Fixtures.now, layout: .snapshot))),
            ("panel-toast", AnyView(PanelView(inbox: inbox, status: nil, model: model(toast: true), now: Fixtures.now, layout: .snapshot))),
            ("panel-empty", AnyView(PanelView(inbox: Fixtures.emptyInbox(), status: nil, model: model(), now: Fixtures.now, layout: .snapshot))),
        ]
    }
}
```

Create `Sources/SplarkUI/Panel/InboxRowView.swift`:

```swift
import SplarkKit
import SwiftUI

/// One row of the panel (spec §4.3, the prototype's activity-log style): the spark at the item's level, a quiet
/// "time · source" line, then a bold lead and the rest. Hover swaps the meta line for a toolbar and shows ✓; a click opens
/// the messages, a reply field and reactions.
struct InboxRowView: View {
    let item: InboxItem
    let model: PanelModel
    let now: Date
    var forceHover = false   // for snapshots

    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    private var expanded: Bool { model.expanded == item.id }
    private var showToolbar: Bool { (hovering || forceHover) && !expanded }

    var body: some View {
        let palette = Palette(scheme)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                SparkView(level: item.level.spark)
                    .foregroundStyle(palette.spark)
                    .frame(width: 11, height: 16)
                    .help(item.reason)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Presenter.metaLine(item, now: now))
                        .font(Theme.font(11.5))
                        .foregroundStyle(palette.tertiary)
                        .lineLimit(1)
                        .frame(height: 16, alignment: .leading)
                        .opacity(showToolbar ? 0 : 1)
                        .overlay(alignment: .topLeading) { if showToolbar { toolbar.offset(x: -5, y: -4) } }
                    summary(palette)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ReadButton(help: "Mark as read in Slack", double: false) { model.markRead(item) }
                    .opacity(hovering || forceHover || expanded ? 1 : 0)
                    .padding(.top, 2)
            }
            if expanded { detail(palette).padding(.leading, 22).padding(.top, 9) }
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 9, trailing: 6))
        .background(RoundedRectangle(cornerRadius: 10).fill(hovering || forceHover || expanded ? palette.rowHover : Ink(0, opacity: 0)))
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(item) }
        .onHover { hovering = $0 }
    }

    private func summary(_ palette: Palette) -> some View {
        let quiet = item.level == .fyi
        let color = quiet ? palette.secondary : palette.text
        return (Text(item.lead).font(Theme.font(13, quiet ? NSFont.Weight(rawValue: 0.26) : Theme.leadWeight)).foregroundColor(color.color)
                + Text(item.rest.isEmpty ? "" : " " + item.rest).font(Theme.font(13)).foregroundColor(color.color))
            .lineSpacing(2.5)
            .lineLimit(expanded ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var toolbar: some View {
        HStack(spacing: 1) {
            ChipButton(help: "Reply", action: { model.startReply(item) }) { Image(systemName: "arrowshape.turn.up.left").font(.system(size: 11.5)) }
            reactions
            ChipButton(help: "Open in Slack", action: { Task { await model.open(item) } }) { Image(systemName: "arrow.up.forward.square").font(.system(size: 11.5)) }
        }
    }

    private var reactions: some View {
        ForEach(Reaction.allCases, id: \.self) { reaction in
            ChipButton(help: "React \(reaction.emoji)", action: { Task { await model.react(item, reaction) } }) {
                Text(reaction.emoji).font(.system(size: 13))
            }
        }
    }

    private func detail(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                if item.earlier > 0 || item.moreEarlier {
                    Text("and \(item.earlier)\(item.moreEarlier ? "+" : "") earlier").font(Theme.font(11)).foregroundStyle(palette.tertiary)
                }
                ForEach(Array(item.messages.enumerated()), id: \.offset) { _, message in
                    VStack(alignment: .leading, spacing: 1) {
                        (Text(message.author).font(Theme.font(11, .semibold)).foregroundColor(palette.secondary.color)
                         + Text(" · " + Presenter.clockTime(SlackTS.date(message.ts))).font(Theme.font(11)).foregroundColor(palette.tertiary.color))
                        Text(message.text).font(Theme.font(12)).foregroundStyle(palette.secondary).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.bottom, 9)
            ReplyField(item: item, model: model)
            HStack(spacing: 1) {
                reactions
                ChipButton(help: "Open in Slack", action: { Task { await model.open(item) } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.square").font(.system(size: 11.5))
                        Text("Open in Slack")
                    }
                }
                Spacer(minLength: 8)
                Text("↵ send · esc close").font(Theme.font(10.5)).foregroundStyle(palette.tertiary)
            }
            .padding(.leading, -5)
            .padding(.top, 6)
        }
    }
}

/// "Reply in thread" / "Message Marta Ruiz". Enter sends, Esc collapses; the text stays if sending fails.
struct ReplyField: View {
    let item: InboxItem
    let model: PanelModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isSnapshot) private var isSnapshot
    @FocusState private var focused: Bool

    var body: some View {
        let palette = Palette(scheme)
        let draft = Binding(get: { model.drafts[item.key] ?? "" }, set: { model.drafts[item.key] = $0 })
        let ready = !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.sending.contains(item.key)
        HStack(spacing: 6) {
            Group {
                if isSnapshot {
                    Text(draft.wrappedValue.isEmpty ? item.replyPlaceholder : draft.wrappedValue)
                        .foregroundStyle(draft.wrappedValue.isEmpty ? palette.tertiary : palette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("", text: draft, prompt: Text(item.replyPlaceholder).foregroundColor(palette.tertiary.color))
                        .textFieldStyle(.plain)
                        .foregroundStyle(palette.text)
                        .focused($focused)
                        .onSubmit { Task { await model.send(item) } }
                        .onKeyPress(.escape) {
                            model.escape()
                            return .handled
                        }
                }
            }
            .font(Theme.font(12.5))
            .padding(.vertical, 6)
            Button { Task { await model.send(item) } } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.knock)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(palette.secondary))
                    .opacity(ready ? 1 : 0.22)
            }
            .buttonStyle(.plain)
            .disabled(!ready)
            .help("Send")
        }
        .padding(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 3))
        .background(RoundedRectangle(cornerRadius: 9).fill(palette.inputBackground))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(palette.panelBorder, lineWidth: 0.5))
        .onAppear { if model.focusedReply == item.id { focused = true } }
        .onChange(of: model.focusedReply) { _, id in focused = id == item.id }
    }
}
```

Create `Sources/SplarkUI/Panel/PanelControls.swift`:

```swift
import SplarkKit
import SwiftUI

/// A small borderless button with the prototype's hover chip: the row toolbar's actions, "Open in Slack".
struct ChipButton<Label: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        let palette = Palette(scheme)
        Button(action: action) {
            label()
                .font(Theme.font(11.5, .medium))
                .foregroundStyle(hovering ? palette.text : palette.secondary)
                .frame(minWidth: 24, minHeight: 22)
                .padding(.horizontal, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? palette.chipHover : Ink(0, opacity: 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// The round ✓ that marks a conversation read (and ✓✓ for all comments).
struct ReadButton: View {
    let help: String
    let double: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        let palette = Palette(scheme)
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(lineWidth: 1.2)
                if double {
                    HStack(spacing: -3) {
                        Image(systemName: "checkmark")
                        Image(systemName: "checkmark")
                    }
                    .font(.system(size: 6.5, weight: .bold))
                } else {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                }
            }
            .frame(width: 17, height: 17)
            .foregroundStyle(hovering ? palette.text : palette.secondary)
            .frame(width: 26, height: 26)
            .background(Circle().fill(hovering ? palette.chip : Ink(0, opacity: 0)))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// The header's quiet icon buttons: Open Slack, Settings.
struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        let palette = Palette(scheme)
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(hovering ? palette.text : palette.tertiary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? palette.rowHover : Ink(0, opacity: 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}
```

Create `Sources/SplarkUI/Panel/PanelView.swift`:

```swift
import SplarkKit
import SwiftUI

/// The panel (spec §4.3): a header, the items that need you, "Just comments" folded at the bottom, an empty state, and a toast.
public struct PanelView: View {
    public enum Layout: Equatable {
        /// In the panel window: scrolls past `maxHeight`, and reports its size so the window can follow it.
        case live(maxHeight: CGFloat)
        /// For previews and offscreen snapshots: everything at its natural height, on a solid background.
        case snapshot
    }

    let inbox: InboxStore
    let status: HeaderStatus?
    let model: PanelModel
    let now: Date
    let layout: Layout
    let onSize: (CGSize) -> Void
    var forceHover: InboxItem.ID? = nil   // snapshots of the hover state

    @Environment(\.colorScheme) private var scheme
    @State private var hoveringPanel = false
    @State private var hoveringComments = false
    @State private var listHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0

    public init(inbox: InboxStore, status: HeaderStatus?, model: PanelModel, now: Date, layout: Layout, onSize: @escaping (CGSize) -> Void = { _ in }) {
        self.inbox = inbox
        self.status = status
        self.model = model
        self.now = now
        self.layout = layout
        self.onSize = onSize
    }

    init(inbox: InboxStore, status: HeaderStatus?, model: PanelModel, now: Date, forceHover: InboxItem.ID?) {
        self.init(inbox: inbox, status: status, model: model, now: now, layout: .snapshot)
        self.forceHover = forceHover
    }

    public var body: some View {
        let palette = Palette(scheme)
        VStack(spacing: 0) {
            header(palette)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            if inbox.items.isEmpty { empty(palette) } else { list(palette) }
        }
        .frame(width: Theme.panelWidth)
        .background(layout == .snapshot ? AnyShapeStyle(palette.panelBackground) : AnyShapeStyle(Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelCorner))
        .overlay(RoundedRectangle(cornerRadius: Theme.panelCorner).strokeBorder(palette.panelBorder, lineWidth: 0.5))
        .overlay(alignment: .bottom) { toast(palette) }
        .onHover { hoveringPanel = $0 }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
    }

    // MARK: Header

    private func header(_ palette: Palette) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(inbox.summary.headline).font(Theme.font(13, .semibold)).foregroundStyle(palette.text)
                if let status {
                    HStack(spacing: 6) {
                        if status.working { CyclingSpark().foregroundStyle(palette.tertiary) }
                        Text(status.text).lineLimit(1)
                    }
                    .font(Theme.font(11.5))
                    .foregroundStyle(palette.tertiary)
                }
            }
            Spacer()
            HStack(spacing: 0) {
                HeaderButton(symbol: "arrow.up.forward.app", help: "Open Slack") { model.openSlackApp() }
                HeaderButton(symbol: "gearshape", help: "Settings") { model.showSettings() }
            }
            .opacity(hoveringPanel ? 1 : 0)
        }
        .padding(EdgeInsets(top: 12, leading: 18, bottom: 4, trailing: 10))
        .frame(minHeight: 42)
    }

    // MARK: List

    @ViewBuilder private func list(_ palette: Palette) -> some View {
        let rows = VStack(spacing: 0) {
            ForEach(inbox.items.filter { $0.level != .fyi }) { item in
                InboxRowView(item: item, model: model, now: now, forceHover: forceHover == item.id)
            }
            comments(palette)
        }
        .padding(EdgeInsets(top: 2, leading: 6, bottom: 8, trailing: 6))

        switch layout {
        case .snapshot:
            rows
        case .live(let maxHeight):
            ScrollView {
                rows.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .scrollIndicators(.never)
            .frame(height: min(listHeight, max(0, maxHeight - headerHeight)))
        }
    }

    @ViewBuilder private func comments(_ palette: Palette) -> some View {
        let comments = inbox.items.filter { $0.level == .fyi }
        if !comments.isEmpty {
            VStack(spacing: 0) {
                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.horizontal, 0)
                HStack(spacing: 11) {
                    Color.clear.frame(width: 11, height: 1)
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .rotationEffect(.degrees(model.commentsOpen ? 90 : 0))
                        (Text("Just comments").font(Theme.font(11.5, .semibold)).foregroundColor(palette.secondary.color)
                         + Text(" · \(comments.count) conversation\(comments.count == 1 ? "" : "s")").font(Theme.font(11.5)))
                    }
                    .foregroundStyle(palette.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ReadButton(help: "Mark all as read in Slack", double: true) { model.markAllRead(comments) }
                        .opacity(hoveringComments ? 1 : 0)
                }
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 6, trailing: 6))
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { model.commentsOpen.toggle() } }
                .onHover { hoveringComments = $0 }
                if model.commentsOpen {
                    ForEach(comments) { item in InboxRowView(item: item, model: model, now: now, forceHover: forceHover == item.id) }
                }
            }
            .padding(.top, 4)
        }
    }

    private func empty(_ palette: Palette) -> some View {
        VStack(spacing: 10) {
            SparkView(level: .dimmed).foregroundStyle(palette.spark)
            Text("Nothing unread in Slack.").font(Theme.font(13)).foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(EdgeInsets(top: 28, leading: 20, bottom: 30, trailing: 20))
    }

    // MARK: Toast

    @ViewBuilder private func toast(_ palette: Palette) -> some View {
        if let toast = model.toast {
            HStack(spacing: 10) {
                Text(toast.text)
                if toast.undo != nil {
                    Button("Undo") { model.undo() }
                        .buttonStyle(.plain)
                        .fontWeight(.semibold)
                }
            }
            .font(Theme.font(12.5))
            .foregroundStyle(.white)
            .padding(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
            .background(RoundedRectangle(cornerRadius: 10).fill(palette.toastBackground))
            .padding(.bottom, 26)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}
```

In `Sources/SplarkUI/Snapshot.swift`, replace:

```swift
import SwiftUI

/// Renders a SwiftUI view offscreen to PNG: for tests, `splark-dev render-ui` and the PR's screenshots.
@MainActor public enum Snapshot {
    public static func png<V: View>(_ view: V, scheme: ColorScheme, scale: CGFloat = 2) -> Data? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = scale
```

with:

```swift
import SwiftUI

extension EnvironmentValues {
    /// True while rendering offscreen: AppKit-backed controls (text fields) draw a look-alike instead.
    @Entry public var isSnapshot = false
}

/// Renders a SwiftUI view offscreen to PNG: for tests, `splark-dev render-ui` and the PR's screenshots.
@MainActor public enum Snapshot {
    public static func png<V: View>(_ view: V, scheme: ColorScheme, scale: CGFloat = 2) -> Data? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme).environment(\.isSnapshot, true))
        renderer.scale = scale
```

Create `Sources/splark-dev/RenderUICommand.swift`:

```swift
import AppKit
import SplarkUI
import SwiftUI

/// Renders every UI state with fixture data to PNGs, light and dark, on a desktop-like backdrop.
@MainActor func renderUICommand() throws {
    let out = URL(fileURLWithPath: option("--out") ?? ".context/ui")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (name, view) in PanelGallery.states() {
        for scheme in [ColorScheme.light, .dark] {
            let backdrop = scheme == .light ? Color(white: 0.91) : Color(white: 0.07)
            guard let png = Snapshot.png(view.padding(24).background(backdrop), scheme: scheme) else { fail("couldn't render \(name)") }
            let file = out.appendingPathComponent("\(name)-\(scheme == .light ? "light" : "dark").png")
            try png.write(to: file)
            print(file.path)
        }
    }
}
```

In `Sources/splark-dev/main.swift`, replace:

```swift
  make-icon OUT.icns                  render the app icon at every size and pack it with iconutil
"""
```

with:

```swift
  make-icon OUT.icns                  render the app icon at every size and pack it with iconutil
  render-ui [--out DIR]               render every UI state with fixture data to PNGs (light and dark)
"""
```

In `Sources/splark-dev/main.swift`, replace:

```swift
    case "make-icon": try makeIconCommand()
    default: print(usage)
```

with:

```swift
    case "make-icon": try makeIconCommand()
    case "render-ui": try renderUICommand()
    default: print(usage)
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test`
Expected: PASS, `✔ Test run with 295 tests`. `swift build --build-tests` prints no warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/SplarkUI/Fixtures.swift Sources/SplarkUI/Panel/InboxRowView.swift Sources/SplarkUI/Panel/PanelControls.swift Sources/SplarkUI/Panel/PanelView.swift Sources/SplarkUI/Snapshot.swift Sources/splark-dev/RenderUICommand.swift Sources/splark-dev/main.swift Tests/SplarkUITests/PanelViewTests.swift
git commit -m "Draw the panel: rows, comments, toasts and the empty state" -m "The prototype's activity-log panel in SwiftUI, with fixtures built through
the real InboxStore, and render-ui to see every state in light and dark."
```

- [ ] **Step 6: Compare with the prototype**

Run: `swift run splark-dev render-ui --out /tmp/ui`
Expected: 12 PNGs. Read `panel-light.png`, `panel-expanded-dark.png` and `panel-empty-light.png`, and compare them with `design/prototype/panel.html` rendered by headless Chrome:
```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --screenshot=/tmp/proto.png --window-size=1200,1600 "file://$PWD/design/prototype/panel.html"
```
The rows, type, spacing and sparks should match. Fix any difference in the views before committing again.

---

### Task 9: The panel's window

`PanelController` puts the panel in a borderless, non-activating `NSPanel` under the spark (spec §4.3):
- **Position:** centred under the spark, 6 pt below it, kept 8 pt inside the screen. With no spark (as in tests), top right.
- **Which screen:** the one the spark is on. With "Displays have separate Spaces", every display has its own menu bar.
- **Height:** as tall as its content, up to 70% of that screen. The limit is worked out again each time the panel opens, so undocking doesn't leave it too tall.
- **Background:** Liquid Glass (`NSGlassEffectView`) on macOS 26, and the `.popover` material on 14–15.
- **Keyboard:** it becomes key when shown, so Esc and the reply field work, while the app you were in stays active.
- **Closing:** on a click in another app, when another app comes forward, or on Esc.

**Files:**
- Create: `Sources/SplarkUI/Panel/PanelController.swift`
- Test: `Tests/SplarkUITests/PanelControllerTests.swift`

**Interfaces:**
- Consumes: `Theme` (Task 4).
- Produces:
  - `SparkPanel: NSPanel` (`canBecomeKey`, `onEscape`).
  - `PanelController(anchor: () -> NSRect?, screen: (() -> NSRect)? = nil)`. By default the screen is the one holding the spark.
  - `@Observable PanelLayout { maxHeight }`, which the panel's content reads.
  - Its members:
    - `isShown`, `onEscape`, `onClose`, `layout`;
    - `setContent(_:)` and `contentSizeChanged(_:)`;
    - `maxContentHeight`;
    - `toggle()`, `show()` and `close()`;
    - `static frame(for:under:in:)` and `static visibleFrame(containing:in:)`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SplarkUITests/PanelControllerTests.swift`:

```swift
import AppKit
import Testing
@testable import SplarkUI

@MainActor @Suite struct PanelControllerTests {
    let screen = NSRect(x: 0, y: 0, width: 1512, height: 944)          // visible frame, below a 38 pt menu bar
    let spark = NSRect(x: 1200, y: 945, width: 40, height: 24)          // the status item, in the menu bar

    @Test func sitsCentredUnderTheSparkWithAGap() {
        let frame = PanelController.frame(for: CGSize(width: 372, height: 400), under: spark, in: screen)
        #expect(frame == NSRect(x: 1220 - 186, y: 945 - 6 - 400, width: 372, height: 400))
    }

    @Test func staysOnScreenNearTheRightEdge() {
        let frame = PanelController.frame(for: CGSize(width: 372, height: 300), under: NSRect(x: 1480, y: 945, width: 30, height: 24), in: screen)
        #expect(frame.maxX == screen.maxX - 8)
    }

    @Test func neverTallerThanSeventyPercentOfTheScreen() {
        let frame = PanelController.frame(for: CGSize(width: 372, height: 2000), under: spark, in: screen)
        #expect(frame.height == (944 * 0.7).rounded(.down))
        #expect(PanelController.maxContentHeight(in: screen) == (944 * 0.7).rounded(.down))
    }

    @Test func withoutTheSparkItSitsTopRight() {
        let frame = PanelController.frame(for: CGSize(width: 372, height: 300), under: nil, in: screen)
        #expect(frame.maxX == screen.maxX - 8 && frame.maxY == screen.maxY - 6)
    }

    @Test func thePanelIsNonActivatingAndCanTakeTheKeyboard() {
        let controller = PanelController(anchor: { nil }, screen: { NSRect(x: 0, y: 0, width: 1000, height: 800) })
        let panel = controller.window
        #expect(panel.styleMask.contains(.nonactivatingPanel) && panel.styleMask.contains(.borderless))
        #expect(panel.canBecomeKey && !panel.canBecomeMain && !panel.isOpaque && panel.hasShadow)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces) && panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(!controller.isShown)
    }

    @Test func followsItsContentsHeightKeepingTheTopEdge() {
        let controller = PanelController(anchor: { NSRect(x: 500, y: 760, width: 40, height: 24) }, screen: { NSRect(x: 0, y: 0, width: 1000, height: 760) })
        controller.contentSizeChanged(CGSize(width: 372, height: 300))
        let top = controller.window.frame.maxY
        controller.contentSizeChanged(CGSize(width: 372, height: 420))
        #expect(controller.window.frame.height == 420 && controller.window.frame.maxY == top)
    }

    @Test func escapeIsForwarded() {
        var escaped = false
        let controller = PanelController(anchor: { nil }, screen: { .zero })
        controller.onEscape = { escaped = true }
        controller.window.cancelOperation(nil)
        #expect(escaped)
    }

    /// A laptop with an external display to its right, each with its own menu bar: the panel opens on the spark's screen.
    @Test func opensOnTheScreenTheSparkIsOn() {
        let laptop = (frame: NSRect(x: 0, y: 0, width: 1512, height: 982), visible: NSRect(x: 0, y: 0, width: 1512, height: 944))
        let external = (frame: NSRect(x: 1512, y: 0, width: 2560, height: 1440), visible: NSRect(x: 1512, y: 0, width: 2560, height: 1415))
        let sparkOnExternal = NSRect(x: 3900, y: 1416, width: 40, height: 24)
        #expect(PanelController.visibleFrame(containing: sparkOnExternal, in: [laptop, external]) == external.visible)
        #expect(PanelController.visibleFrame(containing: spark, in: [laptop, external]) == laptop.visible)
        #expect(PanelController.visibleFrame(containing: nil, in: [laptop, external]) == laptop.visible)
    }

    /// Undocking moves Splark to a smaller screen: the content's height limit follows at the next opening.
    @Test func theHeightLimitFollowsTheScreenAtEachOpening() {
        var visible = NSRect(x: 0, y: 0, width: 2560, height: 1415)
        let controller = PanelController(anchor: { nil }, screen: { visible })
        controller.show()
        #expect(controller.layout.maxHeight == (1415 * 0.7).rounded(.down))
        controller.close()
        visible = NSRect(x: 0, y: 0, width: 1512, height: 944)
        controller.show()
        #expect(controller.layout.maxHeight == (944 * 0.7).rounded(.down))
        controller.close()
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift build --build-tests`
Expected: the build fails: `cannot find 'PanelController' in scope`

- [ ] **Step 3: Implement**

Create `Sources/SplarkUI/Panel/PanelController.swift`:

```swift
import AppKit
import SwiftUI

/// The panel's window: borderless and non-activating (the app you were in stays active), able to take the keyboard for
/// the reply field and Esc. It sits under the menu-bar spark on Liquid Glass (macOS 26) or a frosted material (14–15).
final class SparkPanel: NSPanel {
    var onEscape: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// How tall the panel's content may grow: 70% of the spark's screen, worked out each time the panel opens.
@MainActor @Observable public final class PanelLayout {
    public var maxHeight: CGFloat = 600
}

/// Shows, sizes and dismisses the panel (spec §4.3): 372 pt wide, as tall as its content up to 70% of the screen,
/// closed by a click elsewhere, by Esc, or when another app comes forward.
@MainActor public final class PanelController {
    let window = SparkPanel()
    public private(set) var isShown = false
    public var onEscape: (() -> Void)? {
        get { window.onEscape }
        set { window.onEscape = newValue }
    }
    public var onClose: (() -> Void)?
    public let layout = PanelLayout()

    private let anchor: () -> NSRect?
    private let screen: () -> NSRect
    private var contentSize = CGSize(width: Theme.panelWidth, height: 200)
    private var mouseMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    /// `anchor` gives the spark's frame on screen; `screen` the visible frame to stay inside. By default that is the
    /// screen the spark is on: with "Displays have separate Spaces", every display has its own menu bar and spark.
    public init(anchor: @escaping () -> NSRect?, screen: (() -> NSRect)? = nil) {
        self.anchor = anchor
        self.screen = screen ?? {
            Self.visibleFrame(containing: anchor(), in: NSScreen.screens.map { (frame: $0.frame, visible: $0.visibleFrame) })
        }
    }

    /// The panel's content: a `PanelView` in its `.live` layout, reporting its size to `contentSizeChanged`.
    public func setContent<Content: View>(_ content: Content) {
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        window.contentView = Self.background(around: hosting)
    }

    public var maxContentHeight: CGFloat { Self.maxContentHeight(in: screen()) }

    public func toggle() { isShown ? close() : show() }

    public func show() {
        guard !isShown else { return }
        isShown = true
        layout.maxHeight = maxContentHeight
        window.setFrame(Self.frame(for: contentSize, under: anchor(), in: screen()), display: false)
        window.orderFrontRegardless()
        window.makeKey()
        // A click in another app, or another app coming forward, closes the panel.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.close() }
            }
    }

    public func close() {
        guard isShown else { return }
        isShown = false
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        mouseMonitor = nil
        activationObserver = nil
        window.orderOut(nil)
        onClose?()
    }

    /// The content's natural size changed: follow it, keeping the top edge under the spark.
    public func contentSizeChanged(_ size: CGSize) {
        contentSize = size
        let frame = Self.frame(for: size, under: anchor(), in: screen())
        window.setFrame(frame, display: isShown)
    }

    // MARK: Geometry

    /// The visible frame of the screen whose frame (menu bar included) holds the spark; the first screen without one.
    static func visibleFrame(containing anchor: NSRect?, in screens: [(frame: NSRect, visible: NSRect)]) -> NSRect {
        let match = anchor.flatMap { anchor in screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } }
        return (match ?? screens.first)?.visible ?? .zero
    }

    static func maxContentHeight(in screen: NSRect) -> CGFloat { (screen.height * Theme.panelMaxScreenFraction).rounded(.down) }

    /// Centred under the spark, 6 pt below it, inside the screen with an 8 pt margin; top right without a spark.
    static func frame(for size: CGSize, under anchor: NSRect?, in screen: NSRect) -> NSRect {
        let height = min(size.height, maxContentHeight(in: screen))
        let width = size.width
        let top = (anchor?.minY ?? screen.maxY) - 6
        let centredX = anchor.map { $0.midX - width / 2 } ?? screen.maxX - 8 - width
        let x = min(max(centredX, screen.minX + 8), screen.maxX - 8 - width)
        return NSRect(x: x, y: top - height, width: width, height: height)
    }

    // MARK: Background

    private static func background(around content: NSView) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Theme.panelCorner
            glass.contentView = content
            return glass
        }
        #endif
        let frosted = NSVisualEffectView()
        frosted.material = .popover
        frosted.blendingMode = .behindWindow
        frosted.state = .active
        frosted.wantsLayer = true
        frosted.layer?.cornerRadius = Theme.panelCorner
        frosted.layer?.masksToBounds = true
        content.frame = frosted.bounds
        content.autoresizingMask = [.width, .height]
        frosted.addSubview(content)
        return frosted
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test`
Expected: PASS, `✔ Test run with 304 tests`. `swift build --build-tests` prints no warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/SplarkUI/Panel/PanelController.swift Tests/SplarkUITests/PanelControllerTests.swift
git commit -m "Put the panel in its own window under the spark" -m "A non-activating panel, centred under the spark and inside the screen, as
tall as its content up to 70%, on glass on macOS 26 and frosted before."
```

---

### Task 10: Setup

The first-run window (spec §4.4, `design/prototype/setup.html`). Its four steps show as sparks in the transparent title bar.
- **Welcome.**
- **Connect Slack:** config token → Connect → "Creating your private Slack app…" → "Waiting for you to click Allow…" → Connected. Then "+ Add another workspace".
  - **Errors:** a refused token keeps the field. After a failed Allow, Try again reuses the app.
  - **Admin approval:** "My workspace needs an admin to approve apps" keeps the app for Settings' Finish connecting, and setup goes on.
  - **Having trouble?** offers the pasted-token fallback.
- **Connect ChatGPT:** shows the account and the usage note. A plan that can't be used is explained, and Continue still works.
- **You're set:** Open at login and Show count, both on. They are applied on Done.

**While waiting for Allow:**
- Splark listens on the app's redirect port. Closing the window, Cancel, or "needs an admin" stops listening.
- Without that, the next Allow on the same port fails with "Another app is using port 53682", and the other app is Splark.

`FittedWindow` is the window setup (and later Settings) lives in. The content reports its own height and the window follows, keeping its top edge. Letting the hosting controller size the window looped on macOS 26 and crashed, because each resize changes the title bar's safe area.

`SetupModel` holds the behaviour behind a `SetupServices` protocol, so tests use a fake. `LiveSetupServices` wires `WorkspaceSetup`, the engine and `SMAppService`.

**Files:**
- Create: `Sources/SplarkUI/Components.swift`, `Sources/SplarkUI/FittedWindow.swift`, `Sources/SplarkUI/LoginItem.swift`, `Sources/SplarkUI/Setup/SetupModel.swift`, `Sources/SplarkUI/Setup/SetupView.swift`, `Sources/SplarkUI/Setup/SetupWindowController.swift`
- Modify: `Sources/SplarkUI/Fixtures.swift`, `Sources/SplarkUI/Theme.swift`, `Sources/splark-dev/RenderUICommand.swift`
- Test: `Tests/SplarkUITests/SetupModelTests.swift`, `Tests/SplarkUITests/SetupViewTests.swift`

**Interfaces:**
- Consumes: `WorkspaceSetup`, `SplarkEngine.connect/addPendingApp/signInToChatGPT/chatGPTAccount/updateSettings` (Task 1), the views from Task 4.
- Produces:
  - `protocol SetupServices` and `SetupModel(services:)`:
    - `step` (`welcome`, `slack`, `chatgpt`, `done`), `slack: SlackState`, `chatgpt: ChatGPTState`, `connected`;
    - `token`, `manualToken`, `openAtLogin`, `showCount`;
    - `connect()`, `retryAllow()`, `cancel()`, `needsApproval()`, `connectManual()`, `signIn()`, `finish()`, `doneMessage`;
    - `static message(for: Error) -> String`.
  - `SetupView(model:)` and `LiveSetupServices(engine:loginItem:onFinish:)`.
  - `class FittedWindow` (`show`, `close`, `isVisible`, `onClose`).
  - `SetupWindowController(model:)`, a `FittedWindow` 560 pt wide and at least 520 tall, which cancels a waiting Allow when it closes.
  - `protocol LoginItemControlling` and `MainAppLoginItem` (`SMAppService.mainApp`).
  - Shared components: `WindowButton`, `MiniButton`, `RichText`, `Card`, `CardSeparator`, `MessageBox`, `WorkingLine`, `InitialTile`, `SwitchRow`, `AppIconView`, `TokenField` and `MonoSwitchStyle`.
  - `SetupGallery.states()`, which `render-ui` also renders.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SplarkUITests/SetupModelTests.swift`:

```swift
import Foundation
import Testing
@testable import SplarkKit
@testable import SplarkUI

/// Stands in for WorkspaceSetup, the engine and ChatGPT; each call can be told to fail or to wait.
@MainActor final class FakeSetupServices: SetupServices {
    var log: [String] = []
    var createError: Error?, authorizeError: Error?, signInError: Error?
    var account = ChatGPTAccount(email: "ivan@lumen.dev", canUsePlan: true)
    var authorizeGate: CheckedContinuation<Void, Never>?
    var holdAuthorize = false
    var holdUntilCancelled = false   // like the real Allow: waits on the redirect port until cancelled
    let app = SlackAppRegistration(appId: "A9", clientId: "1.2", redirectPort: 53682)

    func connection(_ name: String, team: String) -> SlackConnection {
        SlackConnection(workspace: Workspace(teamId: team, name: name, userId: "U1", userName: "ivan", url: "https://\(name.lowercased()).slack.com/",
                                             redirectPort: 53682, appId: "A9"),
                        credentials: SlackCredentials(teamId: team, userId: "U1", accessToken: "xoxe.xoxp-not-a-real-token", refreshToken: nil, expiresAt: nil, clientId: "1.2"))
    }

    func createApp(configToken: String) async throws -> SlackAppRegistration {
        log.append("create \(configToken)")
        if let createError { throw createError }
        return app
    }
    func authorize(_ app: SlackAppRegistration) async throws -> SlackConnection {
        log.append("authorize \(app.clientId)")
        if holdAuthorize { await withCheckedContinuation { authorizeGate = $0 } }
        if holdUntilCancelled {
            do { try await Task.sleep(for: .seconds(2)) } catch {
                log.append("authorize cancelled")
                throw error
            }
        }
        if let authorizeError { throw authorizeError }
        return connection("Lumen", team: "T1")
    }
    func connect(userToken: String) async throws -> SlackConnection {
        log.append("paste \(userToken)")
        return connection("Lumen Community", team: "T2")
    }
    func added(_ connection: SlackConnection) async throws { log.append("added \(connection.workspace.teamId)") }
    func waitingForApproval(_ app: SlackAppRegistration) async { log.append("pending \(app.clientId)") }
    func signInToChatGPT() async throws -> ChatGPTAccount {
        log.append("chatgpt")
        if let signInError { throw signInError }
        return account
    }
    func open(_ url: URL) { log.append("open \(url.host ?? url.absoluteString)") }
    func setOpenAtLogin(_ on: Bool) { log.append("login \(on)") }
    func setShowCount(_ on: Bool) { log.append("count \(on)") }
    func finish() { log.append("finish") }
}

@MainActor @Suite struct SetupModelTests {
    let services = FakeSetupServices()
    func model() -> SetupModel { SetupModel(services: services) }

    @Test func walksThroughTheFourSteps() {
        let m = model()
        #expect(m.step == .welcome)
        m.next()
        #expect(m.step == .slack && !m.canContinue)
        m.back()
        #expect(m.step == .welcome)
    }

    @Test func connectingCreatesTheAppWaitsForAllowAndForgetsTheToken() async {
        let m = model()
        m.step = .slack
        m.token = "  xoxe.xoxp-config  "
        #expect(m.canConnect)
        await m.connect()
        #expect(services.log == ["create xoxe.xoxp-config", "authorize 1.2", "added T1"])
        #expect(m.slack == .connected && m.token.isEmpty)
        #expect(m.connected.map(\.name) == ["Lumen"] && m.canContinue)
    }

    @Test func showsWaitingForAllowWhileTheBrowserIsOpen() async throws {
        services.holdAuthorize = true
        let m = model()
        m.token = "xoxe.xoxp-config"
        let connecting = Task { await m.connect() }
        #expect(await eventually { services.authorizeGate != nil })
        #expect(m.slack == .waitingForAllow)
        services.authorizeGate?.resume()
        await connecting.value
        #expect(m.slack == .connected)
    }

    @Test(arguments: [
        (WorkspaceSetupError.tokenRejected("token_expired") as Error,
         "That token didn't work. Setup tokens expire after 12 hours and are tied to one workspace. Generate a fresh one and paste it again."),
        (WorkspaceSetupError.noFreePort, "Splark's sign-in ports (53682–53691) are all in use. Quit the app using them and try again."),
    ])
    func aFailedConnectSaysWhyAndKeepsTheField(error: Error, message: String) async {
        services.createError = error
        let m = model()
        m.token = "xoxe.xoxp-config"
        await m.connect()
        #expect(m.slack == .failed(message))
        #expect(m.token == "xoxe.xoxp-config")   // kept, so it can be corrected
    }

    @Test(arguments: [
        (WorkspaceSetupError.cancelled as Error, "Slack sign-in was cancelled. Click Try again when you're ready."),
        (WorkspaceSetupError.timedOut, "Slack didn't answer in time. Click Try again."),
        (WorkspaceSetupError.portBusy(53682), "Another app is using port 53682, which your Splark app needs. Quit it and click Try again."),
    ])
    func aFailedAllowCanBeRetriedWithoutANewToken(error: Error, message: String) async {
        services.authorizeError = error
        let m = model()
        m.token = "xoxe.xoxp-config"
        await m.connect()
        #expect(m.slack == .allowFailed(message))
        services.authorizeError = nil
        await m.retryAllow()
        #expect(services.log.filter { $0.hasPrefix("create") }.count == 1)   // the same app, Allow again
        #expect(m.slack == .connected)
    }

    @Test func aWorkspaceNeedingApprovalLetsSetupGoOn() async throws {
        services.holdAuthorize = true
        let m = model()
        m.token = "xoxe.xoxp-config"
        let connecting = Task { await m.connect() }
        #expect(await eventually { services.authorizeGate != nil })
        await m.needsApproval()
        #expect(m.slack == .waitingForApproval && m.canContinue)
        #expect(services.log.last == "pending 1.2")
        services.authorizeGate?.resume()
        await connecting.value
        #expect(m.slack == .waitingForApproval)    // the abandoned Allow doesn't come back to haunt
    }

    /// Allow listens on the app's redirect port. Leaving it waiting would keep the port, so the next Allow on it would fail.
    @Test func cancellingStopsWaitingForAllow() async {
        services.holdUntilCancelled = true
        let m = model()
        m.token = "xoxe.xoxp-config"
        let connecting = Task { await m.connect() }
        #expect(await eventually { services.log.last == "authorize 1.2" })
        m.cancel()
        await connecting.value
        #expect(services.log.last == "authorize cancelled")
        #expect(m.slack == .allowFailed("Slack sign-in was cancelled. Click Try again when you're ready."))
    }

    @Test func needingApprovalStopsWaitingForAllowToo() async {
        services.holdUntilCancelled = true
        let m = model()
        m.token = "xoxe.xoxp-config"
        let connecting = Task { await m.connect() }
        #expect(await eventually { services.log.last == "authorize 1.2" })
        await m.needsApproval()
        await connecting.value
        #expect(services.log.contains("authorize cancelled") && m.slack == .waitingForApproval)
    }

    /// While one workspace waits for an admin, the next can be connected straight away, as in the prototype.
    @Test func anotherWorkspaceCanBeConnectedWhileOneWaitsForApproval() async throws {
        services.holdAuthorize = true
        let m = model()
        m.token = "xoxe.xoxp-config"
        let connecting = Task { await m.connect() }
        #expect(await eventually { services.authorizeGate != nil })
        await m.needsApproval()
        services.authorizeGate?.resume()
        await connecting.value
        m.token = "xoxe.xoxp-second"
        #expect(m.canConnect)
    }

    @Test func doneSaysWhatHappensNext() async {
        let m = model()
        #expect(m.doneMessage == "Splark is in your menu bar now. It starts catching up once your workspace is approved.\nClick the spark to see what needs you.")
        m.token = "xoxe.xoxp-config"
        await m.connect()
        #expect(m.doneMessage == "Splark is in your menu bar now and is catching up on 1 workspace.\nClick the spark to see what needs you.")
    }

    @Test func anotherWorkspaceTheSameWay() async {
        let m = model()
        m.token = "a"
        await m.connect()
        m.addAnother()
        #expect(m.slack == .idle && m.connected.count == 1)
    }

    @Test func thePastedTokenFallback() async {
        let m = model()
        m.showManual()
        #expect(m.slack == .manual)
        m.openManifestLink()
        #expect(services.log.last == "open api.slack.com")
        m.manualToken = " xoxp-pasted "
        await m.connectManual()
        #expect(services.log.suffix(2) == ["paste xoxp-pasted", "added T2"])
        #expect(m.connected.map(\.name) == ["Lumen Community"] && m.manualToken.isEmpty)
    }

    @Test func signingInToChatGPT() async {
        let m = model()
        m.step = .chatgpt
        #expect(!m.canContinue)
        await m.signIn()
        #expect(m.chatgpt == .signedIn(ChatGPTAccount(email: "ivan@lumen.dev", canUsePlan: true)) && m.canContinue)
    }

    @Test func aPlanThatCantBeUsedStillLetsSetupFinish() async {
        services.account = ChatGPTAccount(email: "ivan@lumen.dev", canUsePlan: false)
        let m = model()
        m.step = .chatgpt
        await m.signIn()
        #expect(m.chatgpt == .failed("This ChatGPT plan can't be used for summaries. Splark will still rank what's unread, without summaries."))
        #expect(m.canContinue)
    }

    @Test func aCancelledChatGPTSignInCanBeTriedAgain() async {
        services.signInError = ChatGPTAuthError.denied(error: "access_denied", description: nil)
        let m = model()
        m.step = .chatgpt
        await m.signIn()
        #expect(m.chatgpt == .failed("Sign-in was cancelled. Try again when you're ready."))
        #expect(!m.canContinue)
    }

    @Test func doneAppliesTheLastStepsSwitches() {
        let m = model()
        m.step = .done
        #expect(m.openAtLogin && m.showCount)   // both on unless changed (spec §4.4)
        m.finish()
        #expect(services.log == ["login true", "count true", "finish"])
        services.log = []
        m.openAtLogin = false
        m.showCount = false
        m.finish()
        #expect(services.log == ["login false", "count false", "finish"])
    }
}
```

Create `Tests/SplarkUITests/SetupViewTests.swift`:

```swift
import AppKit
import SwiftUI
import Testing
@testable import SplarkKit
@testable import SplarkUI

@MainActor @Suite struct SetupViewTests {
    @Test func everySetupStateRendersInBothSchemes() throws {
        for (name, view) in SetupGallery.states() {
            for scheme in [ColorScheme.light, .dark] {
                let png = try #require(Snapshot.png(view, scheme: scheme, scale: 1), "\(name)")
                let rep = try #require(NSBitmapImageRep(data: png))
                #expect(rep.pixelsWide == 560 && rep.pixelsHigh >= 520, "\(name)")
            }
        }
    }

    @Test func initialsForTiles() {
        #expect(InitialTile.initials("Lumen") == "L")
        #expect(InitialTile.initials("Lumen Community") == "LC")
        #expect(InitialTile.initials("A B C") == "AB")
    }

    @Test func theSetupWindowHasATransparentTitleBar() {
        let controller = SetupWindowController(model: SetupModel(services: PreviewSetupServices()))
        #expect(controller.window.titlebarAppearsTransparent && controller.window.styleMask.contains(.fullSizeContentView))
        #expect(!controller.isVisible)
    }

    @Test func closingTheWindowStopsWaitingForAllow() async {
        let services = FakeSetupServices()
        services.holdUntilCancelled = true
        let model = SetupModel(services: services)
        model.token = "xoxe.xoxp-config"
        let controller = SetupWindowController(model: model)
        let connecting = Task { await model.connect() }
        #expect(await eventually { services.log.last == "authorize 1.2" })
        controller.close()
        await connecting.value
        #expect(services.log.last == "authorize cancelled")
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift build --build-tests`
Expected: the build fails: `cannot find 'SetupModel' in scope`, `cannot find type 'SetupServices' in scope`

- [ ] **Step 3: Implement**

Create `Sources/SplarkUI/Components.swift`:

```swift
import SplarkKit
import SwiftUI

/// The pieces setup and Settings share (design/prototype/setup.html).

/// A button: `.primary` (dark), `.secondary` (chip), `.ghost` (text only).
struct WindowButton: View {
    enum Kind { case primary, secondary, ghost }
    let title: String
    var kind: Kind = .primary
    var wide = false
    var enabled = true
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme)
        Button(action: action) {
            Text(title)
                .font(Theme.font(13, kind == .primary ? .semibold : .medium))
                .foregroundStyle(kind == .primary ? palette.buttonText : kind == .ghost ? palette.secondary : palette.text)
                .frame(maxWidth: wide ? .infinity : nil)
                .padding(.vertical, wide ? 11 : 9)
                .padding(.horizontal, kind == .ghost ? 10 : 18)
                .background(RoundedRectangle(cornerRadius: 10).fill(kind == .primary ? palette.button : kind == .secondary ? palette.chip : Ink(0, opacity: 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

/// A small chip button: "Open api.slack.com/apps ↗".
struct MiniButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme)
        Button(action: action) {
            Text(title).font(Theme.font(12, .medium)).foregroundStyle(palette.text)
                .padding(EdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 9))
                .background(RoundedRectangle(cornerRadius: 7).fill(palette.chip))
        }
        .buttonStyle(.plain)
    }
}

/// Body copy with **bold** runs, as in the prototype: secondary text, bold in the main text colour.
struct RichText: View {
    let markdown: String
    var size: CGFloat = 13
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme)
        var attributed = (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            attributed[run.range].foregroundColor = palette.text.color
            attributed[run.range].font = Theme.font(size, .semibold)
        }
        return Text(attributed).font(Theme.font(size)).foregroundStyle(palette.secondary).lineSpacing(size * 0.27)   // CSS line-height ≈ 1.45
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A rounded panel of rows on the chip colour, with separators: workspace lists, switches.
struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme)
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 12).fill(palette.chip))
    }
}

struct CardSeparator: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Rectangle().fill(Palette(scheme).separator).frame(height: 0.5) }
}

/// A note with a spark: errors, "needs approval", the ChatGPT usage note.
struct MessageBox: View {
    let level: SparkLevel
    let markdown: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme)
        HStack(alignment: .top, spacing: 10) {
            SparkView(level: level).foregroundStyle(palette.spark).padding(.top, 3)
            RichText(markdown: markdown, size: 12.5)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(palette.chip))
    }
}

/// "Creating your private Slack app…" with the cycling spark.
struct WorkingLine: View {
    let markdown: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            CyclingSpark().foregroundStyle(Palette(scheme).spark)
            RichText(markdown: markdown)
        }
        .padding(.vertical, 12)
    }
}

/// A workspace's or account's pixel-initial tile.
struct InitialTile: View {
    let text: String
    var size: CGFloat = 30
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme)
        PixelText(String(text.prefix(2)).uppercased(), scale: 2)
            .foregroundStyle(palette.tileText)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.23).fill(palette.tile))
    }

    /// "Lumen" → "L", "Lumen Community" → "LC".
    static func initials(_ name: String) -> String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first))
    }
}

/// A switch row: "Open at login", "Show count next to the spark".
struct SwitchRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme)
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.font(13)).foregroundStyle(palette.text)
                if let detail { Text(detail).font(Theme.font(11.5)).foregroundStyle(palette.tertiary) }
            }
            Spacer()
            Toggle(title, isOn: $isOn).toggleStyle(MonoSwitchStyle()).labelsHidden()
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
    }
}

/// The app icon, drawn from PixelArt.
struct AppIconView: View {
    let size: CGFloat
    var body: some View {
        Image(decorative: AppIconArt.cgImage(size: Int(size * 2 * 1024 / 824)), scale: 2)
            .resizable()
            .interpolation(.none)
            .frame(width: size * 1024 / 824, height: size * 1024 / 824)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.18), radius: 9, y: 8)
    }
}

/// A token field: monospaced, with the prototype's border. Offscreen snapshots draw a look-alike.
struct TokenField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let palette = Palette(scheme)
        Group {
            if isSnapshot {
                Text(text.isEmpty ? placeholder : text).foregroundStyle(text.isEmpty ? palette.tertiary : palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: $text, prompt: Text(placeholder).font(Theme.font(12.5)).foregroundColor(palette.tertiary.color))
                    .textFieldStyle(.plain)
                    .foregroundStyle(palette.text)
                    .onSubmit(onSubmit)
            }
        }
        .font(.system(size: 12.5, design: .monospaced))
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 9).fill(palette.field))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(palette.fieldBorder, lineWidth: 1))
    }
}

/// The prototype's monochrome switch: a grey track (#55555b when on; #a8a8ae in dark mode) and a white knob.
struct MonoSwitchStyle: ToggleStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        return Capsule()
            .fill(on ? Ink(scheme == .dark ? 0xa8a8ae : 0x55555b) : Ink(0x8e8e94))
            .frame(width: 34, height: 20)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 16, height: 16).shadow(color: .black.opacity(0.2), radius: 1, y: 1).padding(2)
            }
            .contentShape(Capsule())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { configuration.isOn.toggle() } }
            .accessibilityElement()
            .accessibilityLabel(Text("\(configuration.isOn ? "On" : "Off")"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { configuration.isOn.toggle() }
    }
}
```

Create `Sources/SplarkUI/FittedWindow.swift`:

```swift
import AppKit
import SwiftUI

/// A window for SwiftUI content with a transparent title bar, whose height follows the content's, keeping its top edge in place.
/// Setup and Settings are both one.
@MainActor public class FittedWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    public var onClose: (() -> Void)?

    init<Content: View>(rootView: Content, size: NSSize, title: String) {
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = title
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        // The content takes its own height, under the title bar, and reports it; the window follows. Letting the hosting
        // controller size the window instead loops on macOS 26, where every resize changes the safe area.
        let hosting = NSHostingController(rootView: rootView
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] size in self?.resize(to: size) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea())
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(size)
    }

    public var isVisible: Bool { window.isVisible }

    public func show() {
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    public func close() { window.close() }

    public func windowWillClose(_ notification: Notification) { onClose?() }

    private func resize(to size: CGSize) {
        guard size.height > 0 else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        guard abs(frame.height - window.frame.height) > 0.5 || abs(frame.width - window.frame.width) > 0.5 else { return }
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: window.isVisible)
    }
}
```

Append to `Sources/SplarkUI/Fixtures.swift`:

```swift

/// Setup services that do nothing: for previews and renders.
@MainActor final class PreviewSetupServices: SetupServices {
    func createApp(configToken: String) async throws -> SlackAppRegistration { SlackAppRegistration(appId: nil, clientId: "", redirectPort: 0) }
    func authorize(_ app: SlackAppRegistration) async throws -> SlackConnection { throw WorkspaceSetupError.cancelled }
    func connect(userToken: String) async throws -> SlackConnection { throw WorkspaceSetupError.cancelled }
    func added(_ connection: SlackConnection) async throws {}
    func waitingForApproval(_ app: SlackAppRegistration) async {}
    func signInToChatGPT() async throws -> ChatGPTAccount { throw WorkspaceSetupError.cancelled }
    func open(_ url: URL) {}
    func setOpenAtLogin(_ on: Bool) {}
    func setShowCount(_ on: Bool) {}
    func finish() {}
}

/// Every setup step and state worth looking at.
@MainActor public enum SetupGallery {
    public static func states() -> [(name: String, view: AnyView)] {
        func view(_ configure: (SetupModel) -> Void) -> AnyView {
            let model = SetupModel(services: PreviewSetupServices())
            configure(model)
            return AnyView(SetupView(model: model))
        }
        let lumen = [Fixtures.workspaces[0]]
        let rejected = SetupModel.message(for: WorkspaceSetupError.tokenRejected("token_expired"))
        return [
            ("setup-welcome", view { $0.preview(step: .welcome) }),
            ("setup-slack", view { $0.preview(step: .slack) }),
            ("setup-slack-error", view { $0.token = "xoxe.xoxp-1-2026…"; $0.preview(step: .slack, slack: .failed(rejected)) }),
            ("setup-slack-allow", view { $0.preview(step: .slack, slack: .waitingForAllow) }),
            ("setup-slack-connected", view { $0.preview(step: .slack, slack: .connected, connected: lumen) }),
            ("setup-slack-approval", view { $0.preview(step: .slack, slack: .waitingForApproval) }),
            ("setup-slack-manual", view { $0.preview(step: .slack, slack: .manual) }),
            ("setup-chatgpt", view { $0.preview(step: .chatgpt, connected: lumen) }),
            ("setup-chatgpt-done", view { $0.preview(step: .chatgpt, connected: lumen, chatgpt: .signedIn(ChatGPTAccount(email: "ivan@lumen.dev", canUsePlan: true))) }),
            ("setup-done", view { $0.preview(step: .done, connected: lumen) }),
        ]
    }
}
```

Create `Sources/SplarkUI/LoginItem.swift`:

```swift
import ServiceManagement

/// Open at login (spec §4.4, §4.5).
@MainActor public protocol LoginItemControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ on: Bool) throws
}

/// The app itself as a login item, through `SMAppService` (macOS 13+). macOS may tell the user it was added.
@MainActor public final class MainAppLoginItem: LoginItemControlling {
    public init() {}

    public var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public func setEnabled(_ on: Bool) throws {
        guard on != isEnabled else { return }
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
```

Create `Sources/SplarkUI/Setup/SetupModel.swift`:

```swift
import Foundation
import Observation
import SplarkKit

/// What setup needs from outside: Slack's app creation and Allow, the engine, ChatGPT, the browser and settings.
/// `LiveSetupServices` is the real one; tests use a fake.
@MainActor public protocol SetupServices: AnyObject {
    func createApp(configToken: String) async throws -> SlackAppRegistration
    func authorize(_ app: SlackAppRegistration) async throws -> SlackConnection
    func connect(userToken: String) async throws -> SlackConnection
    func added(_ connection: SlackConnection) async throws
    func waitingForApproval(_ app: SlackAppRegistration) async
    func signInToChatGPT() async throws -> ChatGPTAccount
    func open(_ url: URL)
    func setOpenAtLogin(_ on: Bool)
    func setShowCount(_ on: Bool)
    func finish()
}

/// First-run setup (spec §4.4, design/prototype/setup.html): welcome, connect Slack (any number of workspaces),
/// connect ChatGPT, done.
@MainActor @Observable public final class SetupModel {
    public enum Step: Int, CaseIterable { case welcome, slack, chatgpt, done }

    public enum SlackState: Equatable {
        case idle                       // the config-token form
        case creating                   // "Creating your private Slack app…"
        case waitingForAllow            // "Waiting for you to click Allow in your browser…"
        case connected                  // the list, "+ Add another workspace"
        case failed(String)             // the token was refused: fix it and Connect again
        case allowFailed(String)        // the app exists: Try again reopens Allow
        case waitingForApproval         // an admin must approve; Settings finishes later
        case manual                     // "Having trouble?": paste a user token
    }

    public enum ChatGPTState: Equatable {
        case idle, waiting
        case signedIn(ChatGPTAccount)
        case failed(String)
    }

    public var step: Step = .welcome
    public var token = ""         // the pasted app configuration token
    public var manualToken = ""   // the fallback's user token
    public private(set) var slack: SlackState = .idle
    public private(set) var connected: [Workspace] = []
    public private(set) var chatgpt: ChatGPTState = .idle
    public var openAtLogin = true   // applied on Done
    public var showCount = true

    private let services: SetupServices
    private var app: SlackAppRegistration?
    private var attempt = 0   // so an abandoned Allow can't change the state later
    private var allowTask: Task<SlackConnection, Error>?   // holds the app's redirect port while it waits

    public init(services: SetupServices) { self.services = services }

    public var canConnect: Bool {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return slack == .idle || slack == .connected || slack == .waitingForApproval || isFailed
    }

    private var isFailed: Bool { if case .failed = slack { true } else { false } }

    public var canContinue: Bool {
        switch step {
        case .welcome, .done: return true
        case .slack: return !connected.isEmpty || slack == .waitingForApproval
        case .chatgpt:
            switch chatgpt {
            case .signedIn: return true
            case .failed(let message): return message == Self.notEligible
            default: return false
            }
        }
    }

    public func next() { step = Step(rawValue: step.rawValue + 1) ?? .done }
    public func back() { step = Step(rawValue: step.rawValue - 1) ?? .welcome }

    // MARK: Slack

    /// Connect: create the private app with the config token (then forget it), and wait for Allow.
    public func connect() async {
        let configToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configToken.isEmpty else { return }
        slack = .creating
        do {
            app = try await services.createApp(configToken: configToken)
            token = ""
        } catch {
            slack = .failed(Self.message(for: error))
            return
        }
        await allow()
    }

    /// After a cancelled, timed-out or blocked Allow: the same app, no new token.
    public func retryAllow() async { await allow() }

    private func allow() async {
        guard let app else { return }
        attempt += 1
        let mine = attempt
        slack = .waitingForAllow
        let task = Task { try await services.authorize(app) }
        allowTask = task
        do {
            let connection = try await task.value
            guard mine == attempt else { return }
            try await services.added(connection)
            connected.append(connection.workspace)
            self.app = nil
            slack = .connected
        } catch {
            guard mine == attempt else { return }
            slack = .allowFailed(Self.message(for: error))
        }
    }

    /// Stops waiting for Allow, freeing the redirect port: the window closed, or the user clicked Cancel.
    public func cancel() {
        guard let allowTask else { return }
        allowTask.cancel()
        self.allowTask = nil
        if slack == .waitingForAllow { slack = .allowFailed(Self.message(for: WorkspaceSetupError.cancelled)) }
        attempt += 1
    }

    /// "My workspace needs admin approval": keep the app for Settings' Finish connecting, and carry on.
    public func needsApproval() async {
        guard let app else { return }
        allowTask?.cancel()
        allowTask = nil
        attempt += 1
        await services.waitingForApproval(app)
        self.app = nil
        slack = .waitingForApproval
    }

    public func addAnother() { slack = .idle }

    public func showManual() { slack = .manual }

    public func openSlackAppSettings() { services.open(URL(string: "https://api.slack.com/apps")!) }

    public func openManifestLink() {
        if let url = try? SlackAppManifest.createFromManifestURL() { services.open(url) }
    }

    public func connectManual() async {
        let userToken = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userToken.isEmpty else { return }
        do {
            let connection = try await services.connect(userToken: userToken)
            try await services.added(connection)
            connected.append(connection.workspace)
            manualToken = ""
            slack = .connected
        } catch {
            slack = .failed(Self.message(for: error))
        }
    }

    // MARK: ChatGPT

    static let notEligible = "This ChatGPT plan can't be used for summaries. Splark will still rank what's unread, without summaries."

    public func signIn() async {
        chatgpt = .waiting
        do {
            let account = try await services.signInToChatGPT()
            chatgpt = account.canUsePlan ? .signedIn(account) : .failed(Self.notEligible)
        } catch ChatGPTAuthError.denied {
            chatgpt = .failed("Sign-in was cancelled. Try again when you're ready.")
        } catch {
            chatgpt = .failed("Couldn't sign in to ChatGPT. Try again.")
        }
    }

    /// Previews and renders only: put the model in a state without going through Slack.
    func preview(step: Step, slack: SlackState = .idle, connected: [Workspace] = [], chatgpt: ChatGPTState = .idle) {
        self.step = step
        self.slack = slack
        self.connected = connected
        self.chatgpt = chatgpt
    }

    // MARK: Done

    public var doneMessage: String {
        let count = connected.count
        let first = count == 0
            ? "Splark is in your menu bar now. It starts catching up once your workspace is approved."
            : "Splark is in your menu bar now and is catching up on \(count) workspace\(count == 1 ? "" : "s")."
        return first + "\nClick the spark to see what needs you."
    }

    public func finish() {
        services.setOpenAtLogin(openAtLogin)
        services.setShowCount(showCount)
        services.finish()
    }

    static func message(for error: Error) -> String {
        switch error {
        case WorkspaceSetupError.tokenRejected:
            return "That token didn't work. Setup tokens expire after 12 hours and are tied to one workspace. Generate a fresh one and paste it again."
        case WorkspaceSetupError.noFreePort:
            return "Splark's sign-in ports (53682–53691) are all in use. Quit the app using them and try again."
        case WorkspaceSetupError.portBusy(let port):
            return "Another app is using port \(port), which your Splark app needs. Quit it and click Try again."
        case WorkspaceSetupError.cancelled:
            return "Slack sign-in was cancelled. Click Try again when you're ready."
        case WorkspaceSetupError.timedOut:
            return "Slack didn't answer in time. Click Try again."
        case is URLError:
            return "Couldn't reach Slack. Check your connection and try again."
        default:
            return "Slack said no (\(error)). Try again, or use a pasted token under Having trouble?"
        }
    }
}
```

Create `Sources/SplarkUI/Setup/SetupView.swift`:

```swift
import SplarkKit
import SwiftUI

/// The setup window's content (spec §4.4; copy and states as in design/prototype/setup.html).
public struct SetupView: View {
    let model: SetupModel
    @Environment(\.colorScheme) private var scheme

    public init(model: SetupModel) { self.model = model }

    public var body: some View {
        let palette = Palette(scheme)
        VStack(spacing: 0) {
            steps(palette).frame(height: 28)
            Group {
                switch model.step {
                case .welcome: welcome(palette)
                case .slack: slack(palette)
                case .chatgpt: chatgpt(palette)
                case .done: done(palette)
                }
            }
            .padding(EdgeInsets(top: 18, leading: 44, bottom: 30, trailing: 44))
        }
        .frame(width: 560)
        .frame(minHeight: 520, alignment: .top)
        .background(palette.window)
    }

    /// Four sparks in the title bar: bright for the current step, brighter for done ones, dimmed for the rest.
    private func steps(_ palette: Palette) -> some View {
        HStack(spacing: 14) {
            ForEach(SetupModel.Step.allCases, id: \.self) { step in
                SparkView(level: step == model.step ? .bright : step.rawValue < model.step.rawValue ? .brighter : .dimmed)
                    .help(["Welcome", "Slack", "ChatGPT", "Done"][step.rawValue])
            }
        }
        .foregroundStyle(palette.spark)
        .padding(.top, 8)
    }

    private func title(_ text: String, _ palette: Palette) -> some View {
        Text(text).font(Theme.font(22, .semibold)).foregroundStyle(palette.text).padding(.top, 6).padding(.bottom, 8)
    }

    // MARK: Welcome

    private func welcome(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            AppIconView(size: 84).padding(.top, 18).padding(.bottom, 8)
            title("Splark", palette)
            RichText(markdown: "Slack, sorted by what needs you.\nClick the spark in your menu bar to see what's unread, summarised and ranked.", size: 13.5)
                .multilineTextAlignment(.center)
                .padding(.bottom, 18)
            VStack(alignment: .leading, spacing: 11) {
                point(.bright, "**Needs action** first, then **questions for you**, then everything else folded away.", palette)
                point(.brighter, "**Reply, react or mark as read** right from the menu bar. Nothing is sent until you press send.", palette)
                point(.dimmed, "**Private by design.** Your Slack messages go only to your own ChatGPT account for summaries. There's no Splark server.", palette)
            }
            .frame(maxWidth: 400, alignment: .leading)
            Spacer(minLength: 22)
            HStack {
                Text("Takes about two minutes.").font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                Spacer()
                WindowButton(title: "Get started") { model.next() }
            }
        }
    }

    private func point(_ level: SparkLevel, _ markdown: String, _ palette: Palette) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SparkView(level: level).foregroundStyle(palette.spark).frame(height: 19)
            RichText(markdown: markdown)
        }
    }

    // MARK: Slack

    private func slack(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Connect Slack", palette)
            RichText(markdown: model.connected.isEmpty
                     ? "Splark reads your Slack through a **private app that only you install**, so there are no shared servers and no rate limits from a public app."
                     : "Add another workspace the same way, or continue.", size: 13.5)
                .padding(.bottom, 18)
            if !model.connected.isEmpty { workspaces(palette).padding(.bottom, 12) }
            slackBody(palette)
            Spacer(minLength: 18)
            HStack(spacing: 10) {
                if model.slack != .manual && model.slack != .idle {
                    Button("Having trouble?") { model.showManual() }.buttonStyle(.plain).font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                }
                Spacer()
                if model.slack == .connected {
                    WindowButton(title: "+ Add another workspace", kind: .ghost) { model.addAnother() }
                }
                WindowButton(title: "Back", kind: .secondary) { model.back() }
                WindowButton(title: "Continue", enabled: model.canContinue) { model.next() }
            }
        }
    }

    private func workspaces(_ palette: Palette) -> some View {
        Card {
            ForEach(Array(model.connected.enumerated()), id: \.offset) { index, workspace in
                if index > 0 { CardSeparator() }
                HStack(spacing: 12) {
                    InitialTile(text: InitialTile.initials(workspace.name))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(workspace.name).font(Theme.font(13, .semibold)).foregroundStyle(palette.text)
                        Text("\(workspace.url.flatMap { URL(string: $0)?.host } ?? workspace.teamId) · as \(workspace.userName ?? workspace.userId)")
                            .font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                    }
                    Spacer()
                    HStack(spacing: 6) { SparkView(level: .bright); Text("Connected") }.font(Theme.font(12)).foregroundStyle(palette.secondary)
                }
                .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
            }
        }
    }

    @ViewBuilder private func slackBody(_ palette: Palette) -> some View {
        switch model.slack {
        case .idle, .failed:
            tokenForm(palette)
        case .creating:
            WorkingLine(markdown: "Creating your private Slack app…")
        case .waitingForAllow:
            VStack(alignment: .leading, spacing: 4) {
                WorkingLine(markdown: "Waiting for you to click **Allow** in your browser…")
                HStack(spacing: 14) {
                    Button("My workspace needs an admin to approve apps") { Task { await model.needsApproval() } }
                    Button("Cancel") { model.cancel() }
                }
                .buttonStyle(.plain).font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
            }
        case .allowFailed(let message):
            VStack(alignment: .leading, spacing: 10) {
                MessageBox(level: .bright, markdown: message)
                WindowButton(title: "Try again", kind: .secondary) { Task { await model.retryAllow() } }
            }
        case .waitingForApproval:
            VStack(alignment: .leading, spacing: 16) {
                MessageBox(level: .brighter, markdown: "**Your workspace needs an admin to approve new apps.** Slack has sent them your request. Once it's approved, open Splark's Settings and click **Finish connecting**. You can carry on with setup meanwhile.")
                tokenForm(palette)
            }
        case .connected:
            EmptyView()
        case .manual:
            manualForm(palette)
        }
    }

    private func tokenForm(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                howTo("1", palette) {
                    RichText(markdown: "Open Slack's app settings and, under **Your App Configuration Tokens**, click **Generate Token** for the workspace you want.")
                    MiniButton(title: "Open api.slack.com/apps ↗") { model.openSlackAppSettings() }.padding(.top, 6)
                }
                howTo("2", palette) {
                    RichText(markdown: "Copy the **access token** and paste it here. Splark uses it once to create your own private Slack app, then forgets it.")
                }
            }
            .padding(.bottom, 16)
            HStack(spacing: 8) {
                TokenField(placeholder: "Paste access token (xoxe.xoxp-…)", text: Binding(get: { model.token }, set: { model.token = $0 })) {
                    Task { await model.connect() }
                }
                WindowButton(title: "Connect", enabled: model.canConnect) { Task { await model.connect() } }
            }
            Text("The app lives only in your workspace and only you install it. Your Slack token is stored in your Mac's Keychain.")
                .font(Theme.font(11.5)).foregroundStyle(palette.tertiary).padding(.top, 7)
            if case .failed(let message) = model.slack { MessageBox(level: .bright, markdown: message).padding(.top, 10) }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(["Read messages in conversations you're already in, to find what's unread",
                             "Send replies and reactions as you, only when you click",
                             "Mark conversations as read when you ask it to",
                             "Nothing in channels you're not a member of"], id: \.self) { Text("· " + $0) }
                }
                .font(Theme.font(12)).foregroundStyle(palette.secondary).padding(.top, 4)
            } label: {
                Text("What Splark can do in Slack").font(Theme.font(12)).foregroundStyle(palette.secondary)
            }
            .padding(.top, 12)
        }
    }

    private func howTo<Content: View>(_ number: String, _ palette: Palette, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            PixelText(number, scale: 2).foregroundStyle(palette.secondary)
                .frame(width: 22, height: 22).background(RoundedRectangle(cornerRadius: 5).fill(palette.chip))
            VStack(alignment: .leading, spacing: 0) { content() }
        }
    }

    private func manualForm(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RichText(markdown: "If the token route doesn't work, create the app yourself: open the link, click **Create**, then **Install to Workspace**, and paste the **User OAuth Token** here.")
            MiniButton(title: "Create Splark's app on api.slack.com ↗") { model.openManifestLink() }
            HStack(spacing: 8) {
                TokenField(placeholder: "Paste user token (xoxp-…)", text: Binding(get: { model.manualToken }, set: { model.manualToken = $0 })) {
                    Task { await model.connectManual() }
                }
                WindowButton(title: "Connect", enabled: !model.manualToken.isEmpty) { Task { await model.connectManual() } }
            }
            Button("Use a setup token instead") { model.addAnother() }.buttonStyle(.plain).font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
        }
    }

    // MARK: ChatGPT

    private func chatgpt(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Connect ChatGPT", palette)
            RichText(markdown: "Splark uses your **ChatGPT subscription** to summarise and rank unread messages. Messages go to OpenAI only for this, with storage turned off, and never touch any other server.", size: 13.5)
                .padding(.bottom, 18)
            switch model.chatgpt {
            case .idle, .failed:
                WindowButton(title: "Sign in with ChatGPT", wide: true) { Task { await model.signIn() } }
                Text("Opens chatgpt.com in your browser. Works with ChatGPT Plus and Pro.")
                    .font(Theme.font(11.5)).foregroundStyle(palette.tertiary).frame(maxWidth: .infinity).padding(.top, 7)
                if case .failed(let message) = model.chatgpt { MessageBox(level: .bright, markdown: message).padding(.top, 10) }
            case .waiting:
                WorkingLine(markdown: "Finish signing in in your browser…")
            case .signedIn(let account):
                HStack(spacing: 12) {
                    InitialTile(text: String((account.email ?? "?").prefix(1)), size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.email ?? "Signed in").font(Theme.font(13, .semibold)).foregroundStyle(palette.text)
                        Text("ChatGPT · signed in").font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                    }
                    Spacer()
                    HStack(spacing: 6) { SparkView(level: .bright); Text("Connected") }.font(Theme.font(12)).foregroundStyle(palette.secondary)
                }
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                .background(RoundedRectangle(cornerRadius: 12).fill(palette.chip))
                .padding(.bottom, 14)
                MessageBox(level: .dimmed, markdown: "Summaries use your **ChatGPT plan's usage**. Splark only summarises conversations that changed and waits for activity to settle, so it uses very little.")
            }
            Spacer(minLength: 18)
            HStack(spacing: 10) {
                Spacer()
                WindowButton(title: "Back", kind: .secondary) { model.back() }
                WindowButton(title: "Continue", enabled: model.canContinue) { model.next() }
            }
        }
    }

    // MARK: Done

    private func done(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            AppIconView(size: 64).padding(.top, 18).padding(.bottom, 8)
            title("You're set", palette)
            RichText(markdown: model.doneMessage, size: 13.5)
                .multilineTextAlignment(.center)
                .padding(.bottom, 18)
            Card {
                SwitchRow(title: "Open at login", isOn: Binding(get: { model.openAtLogin }, set: { model.openAtLogin = $0 }))
                CardSeparator()
                SwitchRow(title: "Show count next to the spark", detail: "How many items need you",
                          isOn: Binding(get: { model.showCount }, set: { model.showCount = $0 }))
            }
            .frame(maxWidth: 400)
            Spacer(minLength: 18)
            HStack {
                Text("Change this any time in Settings.").font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                Spacer()
                WindowButton(title: "Done") { model.finish() }
            }
        }
    }
}
```

Create `Sources/SplarkUI/Setup/SetupWindowController.swift`:

```swift
import AppKit
import SplarkKit
import SwiftUI

/// The real setup services: WorkspaceSetup for Slack, the engine for workspaces and ChatGPT, the browser, and login items.
@MainActor public final class LiveSetupServices: SetupServices {
    private let engine: SplarkEngine
    private let setup: WorkspaceSetup
    private let loginItem: LoginItemControlling
    private let onFinish: () -> Void

    public init(engine: SplarkEngine, loginItem: LoginItemControlling, onFinish: @escaping () -> Void) {
        self.engine = engine
        self.setup = WorkspaceSetup(open: { url in Task { @MainActor in NSWorkspace.shared.open(url) } })
        self.loginItem = loginItem
        self.onFinish = onFinish
    }

    public func createApp(configToken: String) async throws -> SlackAppRegistration { try await setup.createApp(configToken: configToken) }
    public func authorize(_ app: SlackAppRegistration) async throws -> SlackConnection { try await setup.authorize(app) }
    public func connect(userToken: String) async throws -> SlackConnection { try await setup.connect(userToken: userToken) }
    public func added(_ connection: SlackConnection) async throws { try await engine.connect(connection) }
    public func waitingForApproval(_ app: SlackAppRegistration) async { await engine.addPendingApp(app) }

    public func signInToChatGPT() async throws -> ChatGPTAccount {
        _ = try await engine.signInToChatGPT(open: { url in Task { @MainActor in NSWorkspace.shared.open(url) } })
        return await engine.chatGPTAccount() ?? ChatGPTAccount(email: nil, canUsePlan: false)
    }

    public func open(_ url: URL) { NSWorkspace.shared.open(url) }

    public func setOpenAtLogin(_ on: Bool) {
        try? loginItem.setEnabled(on)
        Task { await engine.updateSettings { $0.openAtLogin = on } }
    }

    public func setShowCount(_ on: Bool) { Task { await engine.updateSettings { $0.showCount = on } } }

    public func finish() { onFinish() }
}

/// The setup window: 560 pt wide, with the step sparks in its transparent title bar. It grows with its content.
@MainActor public final class SetupWindowController: FittedWindow {
    private let model: SetupModel

    public init(model: SetupModel) {
        self.model = model
        super.init(rootView: SetupView(model: model), size: NSSize(width: 560, height: 520), title: "Splark")
    }

    /// A closed window stops waiting for Allow, so the app's redirect port is free for the next try.
    override public func windowWillClose(_ notification: Notification) {
        model.cancel()
        super.windowWillClose(notification)
    }
}
```

In `Sources/SplarkUI/Theme.swift`, replace:

```swift
    public let rowHover, separator, chip, chipHover, inputBackground, panelBackground, panelBorder, knock, toastBackground: Ink

```

with:

```swift
    public let rowHover, separator, chip, chipHover, inputBackground, panelBackground, panelBorder, knock, toastBackground: Ink
    /// Setup and Settings (design/prototype/setup.html).
    public let window, windowBorder, button, buttonText, tile, tileText, field, fieldBorder: Ink

```

In `Sources/SplarkUI/Theme.swift`, replace:

```swift
            panelBorder = Ink(0xffffff, opacity: 0.12); knock = Ink(0x2c2c30)
        } else {
```

with:

```swift
            panelBorder = Ink(0xffffff, opacity: 0.12); knock = Ink(0x2c2c30)
            window = Ink(0x28282c, opacity: 0.92); windowBorder = Ink(0xffffff, opacity: 0.10)
            button = Ink(0xd0d0d5); buttonText = Ink(0x232327); tile = Ink(0x5a5a60); tileText = Ink(0xececf0)
            field = Ink(0x000000, opacity: 0.25); fieldBorder = Ink(0xffffff, opacity: 0.12)
        } else {
```

In `Sources/SplarkUI/Theme.swift`, replace:

```swift
            panelBorder = Ink(0x000000, opacity: 0.10); knock = Ink(0xf4f4f6)
        }
```

with:

```swift
            panelBorder = Ink(0x000000, opacity: 0.10); knock = Ink(0xf4f4f6)
            window = Ink(0xfafafc, opacity: 0.92); windowBorder = Ink(0x000000, opacity: 0.10)
            button = Ink(0x4a4a50); buttonText = Ink(0xf4f4f6); tile = Ink(0x4a4a50); tileText = Ink(0xe6e6ea)
            field = Ink(0xffffff, opacity: 0.95); fieldBorder = Ink(0x000000, opacity: 0.12)
        }
```

In `Sources/splark-dev/RenderUICommand.swift`, replace:

```swift
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (name, view) in PanelGallery.states() {
        for scheme in [ColorScheme.light, .dark] {
```

with:

```swift
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (name, view) in PanelGallery.states() + SetupGallery.states() {
        for scheme in [ColorScheme.light, .dark] {
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test`
Expected: PASS, `✔ Test run with 324 tests`. `swift build --build-tests` prints no warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/SplarkUI/Components.swift Sources/SplarkUI/FittedWindow.swift Sources/SplarkUI/Fixtures.swift Sources/SplarkUI/LoginItem.swift Sources/SplarkUI/Setup/SetupModel.swift Sources/SplarkUI/Setup/SetupView.swift Sources/SplarkUI/Setup/SetupWindowController.swift Sources/SplarkUI/Theme.swift Sources/splark-dev/RenderUICommand.swift Tests/SplarkUITests/SetupModelTests.swift Tests/SplarkUITests/SetupViewTests.swift
git commit -m "Walk through setup: welcome, Slack, ChatGPT, done" -m "Four steps as sparks in the title bar: a private Slack app per workspace
from one pasted token, ChatGPT sign-in, and the two switches."
```

- [ ] **Step 6: Compare with the prototype**

Run: `swift run splark-dev render-ui --out /tmp/ui`
Expected: Read `setup-welcome-light.png`, `setup-slack-error-light.png`, `setup-slack-connected-dark.png` and `setup-done-light.png`. They should match `design/prototype/setup.html`, rendered as in Task 8.

---

### Task 11: Settings

One window, with its four sections as tabs in the title bar (spec §4.5). It has setup's look; there is no prototype.
- **Workspaces:** each one's status and last sync, Channels… and Remove.
  - A row that needs it gets its fix underneath: Reconnect, Paste new token (for a pasted token, which has no app to Allow again), or Finish connecting (an app waiting for an admin).
  - "+ Add workspace" opens setup.
  - A line says whether Slack's badge can be read.
  - Remove asks first, inline, and says how to delete the private app.
  - Only one Allow runs at a time, with a Cancel. Closing the window cancels it.
- **Channels…:** every channel, with a search and checkboxes for the excluded ones.
- **ChatGPT:** the account, the model menu (recommended first), Sign in or Sign out, and Pause summaries. The switches show the engine's settings as they are now, so a pause from the menu shows here too.
- **General:** Open at login, Show count, and Reset Splark, which asks first.
- **About:** the icon, the version, the licence, the repo, and the credits.

Settings lives in Task 10's `FittedWindow`. Its test that switches sections in a shown window is the one that crashed the first sizing.

**Files:**
- Create: `Sources/SplarkUI/Settings/SettingsModel.swift`, `Sources/SplarkUI/Settings/SettingsView.swift`, `Sources/SplarkUI/Settings/SettingsWindowController.swift`
- Modify: `Sources/SplarkKit/Sync/SyncEngine.swift`, `Sources/SplarkKit/Sync/SyncSchedule.swift`, `Sources/SplarkUI/Components.swift`, `Sources/SplarkUI/Fixtures.swift`, `Sources/splark-dev/RenderUICommand.swift`
- Test: `Tests/SplarkUITests/SettingsModelTests.swift`, `Tests/SplarkUITests/SettingsViewTests.swift`

**Interfaces:**
- Consumes: Task 1's engine API, `Presenter.workspaceStatus` (Task 5), and from Task 10 `SetupModel.message(for:)`, the components and `FittedWindow`.
- Produces:
  - `protocol SettingsServices`, `enum ReconnectError { noSavedSignIn }`, and `SettingsModel(services:now:onReset:)`:
    - `section`, `workspaceRows: [WorkspaceRow]`, `badgeLine`, `message`, `working`, `pasting`, `newToken`, `removal`, `removalNote`, `channelPicker: ChannelPicker?`;
    - `account`, `models`, `model`, `recommendedModel`;
    - `openAtLogin`, `showCount`, `summariesPaused`, `confirmingReset`, `version`;
    - `load()`, `perform(_:on:)`, `cancel()`, `savePastedToken()`, `askToRemove`/`confirmRemoval`, `editChannels`/`toggleChannel`/`saveChannels`, `chooseModel`, `signIn`, `signOut`, `setOpenAtLogin`, `setShowCount`, `setSummariesPaused`, `askToReset`/`confirmReset`, `addWorkspace`, `openRepository` and `openDoll`.
  - `WorkspaceRow { id, name, status, action: Action? (reconnect, pasteNewToken, finishConnecting; .title) }` and `ChannelPicker { teamId, name, channels, excluded, search, shown }`.
  - `SettingsView(model:)`, `LiveSettingsServices(engine:loginItem:onAddWorkspace:)`, and `SettingsWindowController(model:)` (520 pt wide) with `show(_ section:)`.
  - A public `SyncStatus.init(problem:missingScope:progress:lastSuccess:)` and `SyncSchedule.Progress.init(checked:total:)`, for fixtures. `TokenField` gains `monospaced`.
  - `PreviewSettingsServices` and `SettingsGallery.states()` (10 states), which `render-ui` also renders.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SplarkUITests/SettingsModelTests.swift`:

```swift
import Foundation
import Testing
@testable import SplarkKit
@testable import SplarkUI

/// Stands in for the engine, Slack's Allow, ChatGPT, login items and the browser.
@MainActor final class FakeSettingsServices: SettingsServices {
    var log: [String] = []
    var workspaces: [Workspace] = [lumen, community]
    var pendingApps = [SlackAppRegistration(appId: "A7", clientId: "7.7", redirectPort: 53684)]
    var syncStatus: [String: SyncStatus] = [:]
    var badge: SlackBadge? = .dot
    var settings = SavedState.Settings()
    var account: ChatGPTAccount? = ChatGPTAccount(email: "ivan@lumen.dev", canUsePlan: true)
    var excluded: [String: Set<String>] = ["T1": ["C2"]]
    var reconnectError: Error?, loginError: Error?, removeError: Error?, resetError: Error?
    var pastedTeam = "T2"
    var reconnectGate: CheckedContinuation<Void, Never>?
    var holdReconnect = false
    var holdUntilCancelled = false

    func channels(teamId: String) async -> [ChannelOption] {
        [ChannelOption(id: "C1", title: "#eng", isPrivate: false), ChannelOption(id: "C2", title: "#random", isPrivate: false),
         ChannelOption(id: "G1", title: "#leads", isPrivate: true)]
    }
    func excludedChannels(teamId: String) -> Set<String> { excluded[teamId] ?? [] }
    func setExcluded(_ channels: Set<String>, teamId: String) async { log.append("exclude \(teamId) \(channels.sorted())") }
    func reconnect(teamId: String) async throws {
        log.append("reconnect \(teamId)")
        if holdReconnect { await withCheckedContinuation { reconnectGate = $0 } }
        if holdUntilCancelled {
            do { try await Task.sleep(for: .seconds(2)) } catch {
                log.append("reconnect cancelled")
                throw error
            }
        }
        if let reconnectError { throw reconnectError }
    }
    func finishConnecting(_ app: SlackAppRegistration) async throws { log.append("finish \(app.clientId)") }
    func connect(userToken: String) async throws -> SlackConnection {
        log.append("paste \(userToken)")
        let workspace = workspaces.first { $0.teamId == pastedTeam }
            ?? Workspace(teamId: pastedTeam, name: "Elsewhere", userId: "U5", userName: nil, url: nil, redirectPort: nil, appId: nil)
        return SlackConnection(workspace: workspace, credentials: SlackCredentials(teamId: pastedTeam, userId: "U5", accessToken: "xoxp-not-a-real-token",
                                                                                   refreshToken: nil, expiresAt: nil, clientId: nil))
    }
    func added(_ connection: SlackConnection) async throws { log.append("added \(connection.workspace.teamId)") }
    func remove(teamId: String) async throws {
        log.append("remove \(teamId)")
        if let removeError { throw removeError }
    }
    func removePending(_ app: SlackAppRegistration) async { log.append("remove pending \(app.clientId)") }
    func addWorkspace() { log.append("add") }
    func chatGPTAccount() async -> ChatGPTAccount? { account }
    func models() async -> [String] { ["gpt-5.6-luna", "gpt-6-luna"] }
    func setModel(_ model: String?) async {
        log.append("model \(model ?? "default")")
        settings.model = model
    }
    func signInToChatGPT() async throws { log.append("sign in"); account = ChatGPTAccount(email: "ivan@lumen.dev", canUsePlan: true) }
    func signOutOfChatGPT() async throws { log.append("sign out"); account = nil }
    func setSummariesPaused(_ paused: Bool) async {
        log.append("pause \(paused)")
        settings.summariesPaused = paused
    }
    func setOpenAtLogin(_ on: Bool) throws {
        if let loginError { throw loginError }
        log.append("login \(on)")
        settings.openAtLogin = on
    }
    func setShowCount(_ on: Bool) async {
        log.append("count \(on)")
        settings.showCount = on
    }
    func reset() async throws {
        log.append("reset")
        if let resetError { throw resetError }
    }
    func open(_ url: URL) { log.append("open \(url.absoluteString)") }
}

@MainActor @Suite struct SettingsModelTests {
    let services = FakeSettingsServices()
    func model() -> SettingsModel { SettingsModel(services: services, now: { now }) }

    @Test func listsWorkspacesWithTheirStatusAndPendingOnes() {
        var synced = SyncStatus()
        synced.lastSuccess = ago(120)
        services.syncStatus = ["T1": synced, "T2": SyncStatus(problem: .reauthorize)]
        let rows = model().workspaceRows
        #expect(rows.map(\.name) == ["Lumen", "Lumen Community", "Slack workspace"])
        #expect(rows.map(\.status) == [WorkspaceStatusText(title: "Connected", detail: "Synced 2m ago"),
                                        WorkspaceStatusText(title: "Token expired", detail: "Not synced yet"),
                                        WorkspaceStatusText(title: "Waiting for approval", detail: "An admin needs to approve it")])
        #expect(rows.map(\.action) == [nil, .pasteNewToken, .finishConnecting])
        #expect(rows.compactMap(\.action?.title) == ["Paste new token", "Finish connecting"])
        #expect(rows.map(\.canExcludeChannels) == [true, true, false])
    }

    @Test(arguments: [
        (SyncProblem.tokenRevoked, false, "T1", WorkspaceRow.Action.reconnect),
        (.tokenRevoked, false, "T2", .pasteNewToken),     // a pasted token has no app to Allow again
        (.reauthorize, false, "T1", .reconnect),
        (.offline(retryAt: now), false, "T1", nil),
        (nil, true, "T1", .reconnect),                     // "Needs new permissions"
    ] as [(SyncProblem?, Bool, String, WorkspaceRow.Action?)])
    func theRowsActionFollowsItsProblem(problem: SyncProblem?, missingScope: Bool, team: String, action: WorkspaceRow.Action?) {
        services.syncStatus = [team: SyncStatus(problem: problem, missingScope: missingScope)]
        #expect(model().workspaceRows.first { $0.id == team }?.action == action)
    }

    @Test func saysWhetherSlacksBadgeCanBeRead() {
        #expect(model().badgeLine == "Slack is open, so new messages show up within seconds.")
        services.badge = nil
        #expect(model().badgeLine == "Slack isn't open, or its Dock badge can't be read, so Splark checks every couple of minutes.")
    }

    @Test func reconnectWaitsForAllowAndSaysWhyItFailed() async throws {
        services.holdReconnect = true
        let m = model()
        let reconnecting = Task { await m.perform(.reconnect, on: m.workspaceRows[0]) }
        #expect(await eventually { services.reconnectGate != nil })
        #expect(m.working == "T1")
        services.reconnectError = WorkspaceSetupError.cancelled
        services.reconnectGate?.resume()
        await reconnecting.value
        #expect(m.working == nil)
        #expect(m.message == "Slack sign-in was cancelled. Click Try again when you're ready.")
        services.holdReconnect = false
        services.reconnectError = nil
        await m.perform(.finishConnecting, on: m.workspaceRows[2])
        #expect(services.log == ["reconnect T1", "finish 7.7"] && m.message == nil)
    }

    @Test func cancellingStopsWaitingForAllowWithoutComplaint() async {
        services.holdUntilCancelled = true
        let m = model()
        let reconnecting = Task { await m.perform(.reconnect, on: m.workspaceRows[0]) }
        #expect(await eventually { services.log == ["reconnect T1"] })
        #expect(m.working == "T1")
        m.cancel()
        await reconnecting.value
        #expect(services.log == ["reconnect T1", "reconnect cancelled"])
        #expect(m.working == nil && m.message == nil)
    }

    /// Both apps would want the same redirect port: one Allow at a time.
    @Test func aSecondReconnectWaitsItsTurn() async {
        services.holdUntilCancelled = true
        let m = model()
        let first = Task { await m.perform(.reconnect, on: m.workspaceRows[0]) }
        #expect(await eventually { services.log == ["reconnect T1"] })
        await m.perform(.finishConnecting, on: m.workspaceRows[2])
        #expect(services.log == ["reconnect T1"] && m.working == "T1")
        m.cancel()
        await first.value
    }

    @Test func aSignInSplarkCantReadSaysWhatToDo() async {
        services.reconnectError = ReconnectError.noSavedSignIn
        let m = model()
        await m.perform(.reconnect, on: m.workspaceRows[0])
        #expect(m.message == "Splark can't read Lumen's saved sign-in from the Keychain. Remove it and add it again.")
    }

    /// Paused from the menu while Settings is open: the switch shows it.
    @Test func theSwitchesShowWhatTheEngineHasNow() {
        let m = model()
        services.settings.summariesPaused = true
        services.settings.showCount = false
        #expect(m.summariesPaused && !m.showCount)
    }

    @Test func aPastedTokenReplacesTheWorkspacesOwn() async {
        let m = model()
        await m.perform(.pasteNewToken, on: m.workspaceRows[1])
        #expect(m.pasting == "T2")
        m.newToken = " xoxp-new "
        await m.savePastedToken()
        #expect(services.log == ["paste xoxp-new", "added T2"])
        #expect(m.pasting == nil && m.newToken.isEmpty)
    }

    @Test func aTokenForAnotherWorkspaceIsRefused() async {
        services.pastedTeam = "T5"
        let m = model()
        await m.perform(.pasteNewToken, on: m.workspaceRows[1])
        m.newToken = "xoxp-other"
        await m.savePastedToken()
        #expect(services.log == ["paste xoxp-other"])
        #expect(m.message == "That token is for Elsewhere, not Lumen Community. Paste one made in Lumen Community.")
        #expect(m.pasting == "T2" && m.newToken == "xoxp-other")
    }

    @Test func removingAWorkspaceAsksFirst() async {
        let m = model()
        m.askToRemove(m.workspaceRows[0])
        #expect(m.removal?.name == "Lumen")
        #expect(m.removalNote == "Splark forgets Lumen's token. To delete your private Splark app too, open api.slack.com/apps, choose Splark, and click Delete App.")
        m.cancelRemoval()
        #expect(m.removal == nil && services.log.isEmpty)
        m.askToRemove(m.workspaceRows[0])
        await m.confirmRemoval()
        #expect(services.log == ["remove T1"] && m.removal == nil)
        m.askToRemove(m.workspaceRows[2])
        #expect(m.removalNote == "Splark forgets this app. To delete it from Slack too, open api.slack.com/apps, choose Splark, and click Delete App.")
        await m.confirmRemoval()
        #expect(services.log.last == "remove pending 7.7")
    }

    @Test func pickingExcludedChannels() async {
        let m = model()
        await m.editChannels(m.workspaceRows[0])
        #expect(m.channelPicker?.name == "Lumen")
        #expect(m.channelPicker?.shown.map(\.title) == ["#eng", "#random", "#leads"])
        #expect(m.channelPicker?.excluded == ["C2"])
        m.channelPicker?.search = "RA"
        #expect(m.channelPicker?.shown.map(\.title) == ["#random"])
        m.toggleChannel("C1")
        m.toggleChannel("C2")
        await m.saveChannels()
        #expect(services.log == ["exclude T1 [\"C1\"]"] && m.channelPicker == nil)
    }

    @Test func chatGPTAccountAndModel() async {
        services.settings.model = "gpt-5.6-luna"
        let m = model()
        await m.load()
        #expect(m.account?.email == "ivan@lumen.dev")
        #expect(m.models == ["gpt-5.6-luna", "gpt-6-luna"] && m.recommendedModel == "gpt-6-luna")
        #expect(m.model == "gpt-5.6-luna")
        await m.chooseModel(nil)
        #expect(m.model == nil)
        await m.signOut()
        #expect(m.account == nil && m.models.isEmpty)
        await m.signIn()
        #expect(m.account?.email == "ivan@lumen.dev" && m.models.count == 2)
        #expect(services.log == ["model default", "sign out", "sign in"])
    }

    @Test func generalSwitches() async {
        let m = model()
        #expect(m.openAtLogin && m.showCount && !m.summariesPaused)
        m.setOpenAtLogin(false)
        await m.setShowCount(false)
        await m.setSummariesPaused(true)
        #expect(services.log == ["login false", "count false", "pause true"])
        #expect(!m.openAtLogin && !m.showCount && m.summariesPaused)
    }

    @Test func openAtLoginExplainsWhenMacOSRefuses() {
        services.loginError = CocoaError(.featureUnsupported)
        let m = model()
        m.setOpenAtLogin(false)
        #expect(m.openAtLogin)
        #expect(m.message == "macOS didn't let Splark change this. Check System Settings → General → Login Items.")
    }

    @Test func resetAsksFirst() async {
        var reset = false
        let m = SettingsModel(services: services, now: { now }, onReset: { reset = true })
        m.askToReset()
        #expect(m.confirmingReset)
        await m.confirmReset()
        #expect(services.log == ["reset"] && reset && !m.confirmingReset)
    }

    /// The engine forgets everything it can even when a Keychain item won't go, so setup starts again regardless.
    @Test func aResetThatHitsAKeychainErrorStillStartsOver() async {
        services.resetError = SecretStoreError.keychain(-25293)
        var reset = false
        let m = SettingsModel(services: services, now: { now }, onReset: { reset = true })
        m.askToReset()
        await m.confirmReset()
        #expect(reset)
    }

    @Test func aRemovedWorkspaceWhoseTokenWontGoSaysSo() async {
        services.removeError = SecretStoreError.keychain(-25293)
        let m = model()
        m.askToRemove(m.workspaceRows[0])
        await m.confirmRemoval()
        #expect(m.message == "Removed Lumen, but macOS wouldn't delete its token from the Keychain.")
    }

    @Test func addingAWorkspaceAndTheAboutLinks() {
        let m = model()
        m.addWorkspace()
        #expect(m.version == "Version \(SplarkInfo.version) · Open source, MIT licence")
        m.openRepository()
        m.openDoll()
        #expect(services.log == ["add", "open https://github.com/ivliag/splark", "open https://github.com/xiaogdgenuine/Doll"])
    }
}
```

Create `Tests/SplarkUITests/SettingsViewTests.swift`:

```swift
import AppKit
import SwiftUI
import Testing
@testable import SplarkKit
@testable import SplarkUI

@MainActor @Suite struct SettingsViewTests {
    @Test func everySettingsStateRendersInBothSchemes() throws {
        let states = SettingsGallery.states()
        #expect(states.count == 10)
        for (name, view) in states {
            for scheme in [ColorScheme.light, .dark] {
                let png = try #require(Snapshot.png(view, scheme: scheme, scale: 1), "\(name)")
                let rep = try #require(NSBitmapImageRep(data: png))
                #expect(rep.pixelsWide == 520 && rep.pixelsHigh >= 200, "\(name)")
            }
        }
    }

    @Test func theSettingsWindowHasATransparentTitleBar() {
        let model = SettingsModel(services: PreviewSettingsServices())
        let controller = SettingsWindowController(model: model)
        #expect(controller.window.title == "Splark Settings" && controller.window.titlebarAppearsTransparent)
        #expect(!controller.isVisible && model.section == .workspaces)
    }

    /// A shown window resizes to each section, keeping its top edge. (Sized by its hosting controller, it looped and crashed on macOS 26.)
    @Test func theShownWindowFollowsEachSectionsHeight() async throws {
        _ = NSApplication.shared
        let model = SettingsModel(services: PreviewSettingsServices(), now: { now })
        let controller = SettingsWindowController(model: model)
        controller.show()
        #expect(await eventually { controller.window.frame.height > 300 })   // Workspaces, with four rows
        let top = controller.window.frame.maxY
        var height = controller.window.frame.height
        for section in [SettingsModel.Section.about, .general, .workspaces] {
            model.section = section
            #expect(await eventually { abs(controller.window.frame.height - height) > 1 }, "\(section)")
            #expect(abs(controller.window.frame.maxY - top) < 1, "\(section)")
            height = controller.window.frame.height
        }
        controller.close()
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift build --build-tests`
Expected: the build fails: `cannot find type 'SettingsServices' in scope`, `cannot find 'SettingsModel' in scope`, `cannot find 'SettingsGallery' in scope`

- [ ] **Step 3: Implement**

In `Sources/SplarkKit/Sync/SyncEngine.swift`, replace:

```swift
    public var lastSuccess: Date?
}
```

with:

```swift
    public var lastSuccess: Date?

    public init(problem: SyncProblem? = nil, missingScope: Bool = false, progress: SyncSchedule.Progress = .init(checked: 0, total: 0),
                lastSuccess: Date? = nil) {
        self.problem = problem
        self.missingScope = missingScope
        self.progress = progress
        self.lastSuccess = lastSuccess
    }
}
```

In `Sources/SplarkKit/Sync/SyncSchedule.swift`, replace:

```swift
        public var isComplete: Bool { checked >= total }
    }
```

with:

```swift
        public var isComplete: Bool { checked >= total }

        public init(checked: Int, total: Int) {
            self.checked = checked
            self.total = total
        }
    }
```

In `Sources/SplarkUI/Components.swift`, replace:

```swift
        Button(action: action) {
            Text(title).font(Theme.font(12, .medium)).foregroundStyle(palette.text)
                .padding(EdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 9))
```

with:

```swift
        Button(action: action) {
            Text(title).font(Theme.font(12, .medium)).foregroundStyle(palette.text).lineLimit(1).fixedSize()
                .padding(EdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 9))
```

In `Sources/SplarkUI/Components.swift`, replace:

```swift
    @Binding var text: String
    var onSubmit: () -> Void = {}
```

with:

```swift
    @Binding var text: String
    var monospaced = true
    var onSubmit: () -> Void = {}
```

In `Sources/SplarkUI/Components.swift`, replace:

```swift
        }
        .font(.system(size: 12.5, design: .monospaced))
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
```

with:

```swift
        }
        .font(monospaced ? .system(size: 12.5, design: .monospaced) : Theme.font(12.5))
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
```

Append to `Sources/SplarkUI/Fixtures.swift`:

```swift

/// Settings' services for previews and renders: the fixture workspaces, one needing a new token, and an app waiting for approval.
@MainActor final class PreviewSettingsServices: SettingsServices {
    var workspaces: [Workspace] {
        Fixtures.workspaces + [Workspace(teamId: "T3", name: "Acme Partners", userId: "U3", userName: "ivan", url: nil, redirectPort: nil, appId: nil)]
    }
    let pendingApps = [SlackAppRegistration(appId: "A4", clientId: "4.4", redirectPort: 53684)]
    var syncStatus: [String: SyncStatus] {
        ["T1": SyncStatus(lastSuccess: Fixtures.now.addingTimeInterval(-60)),
         "T2": SyncStatus(lastSuccess: Fixtures.now.addingTimeInterval(-240)),
         "T3": SyncStatus(problem: .reauthorize, lastSuccess: Fixtures.now.addingTimeInterval(-3 * 3600))]
    }
    let badge: SlackBadge? = .count(3)
    var settings: SavedState.Settings { SavedState.Settings() }
    func channels(teamId: String) async -> [ChannelOption] { [] }
    func excludedChannels(teamId: String) -> Set<String> { [] }
    func setExcluded(_ channels: Set<String>, teamId: String) async {}
    func reconnect(teamId: String) async throws {}
    func finishConnecting(_ app: SlackAppRegistration) async throws {}
    func connect(userToken: String) async throws -> SlackConnection { throw WorkspaceSetupError.cancelled }
    func added(_ connection: SlackConnection) async throws {}
    func remove(teamId: String) async throws {}
    func removePending(_ app: SlackAppRegistration) async {}
    func addWorkspace() {}
    func chatGPTAccount() async -> ChatGPTAccount? { nil }
    func models() async -> [String] { [] }
    func setModel(_ model: String?) async {}
    func signInToChatGPT() async throws {}
    func signOutOfChatGPT() async throws {}
    func setSummariesPaused(_ paused: Bool) async {}
    func setOpenAtLogin(_ on: Bool) throws {}
    func setShowCount(_ on: Bool) async {}
    func reset() async throws {}
    func open(_ url: URL) {}
}

/// Every Settings section and state worth looking at.
@MainActor public enum SettingsGallery {
    public static func states() -> [(name: String, view: AnyView)] {
        func view(_ configure: (SettingsModel) -> Void) -> AnyView {
            let model = SettingsModel(services: PreviewSettingsServices(), now: { Fixtures.now })
            configure(model)
            return AnyView(SettingsView(model: model))
        }
        let account = ChatGPTAccount(email: "ivan@lumen.dev", canUsePlan: true)
        let models = ["gpt-5.6-luna", "gpt-6-luna", "gpt-6-mini"]
        let channels = [ChannelOption(id: "C1", title: "#announcements", isPrivate: false), ChannelOption(id: "C2", title: "#eng", isPrivate: false),
                        ChannelOption(id: "C3", title: "#incidents", isPrivate: false), ChannelOption(id: "G1", title: "#leads", isPrivate: true),
                        ChannelOption(id: "C4", title: "#random", isPrivate: false), ChannelOption(id: "C5", title: "#social", isPrivate: false)]
        return [
            ("settings-workspaces", view { $0.preview(section: .workspaces) }),
            ("settings-workspaces-allow", view { $0.preview(section: .workspaces, message: SetupModel.message(for: WorkspaceSetupError.timedOut), working: "T1") }),
            ("settings-workspaces-paste", view { $0.preview(section: .workspaces, pasting: "T3"); $0.newToken = "xoxp-2026…" }),
            ("settings-workspaces-remove", view { $0.preview(section: .workspaces, removal: $0.workspaceRows[1]) }),
            ("settings-channels", view {
                $0.preview(section: .workspaces)
                $0.channelPicker = ChannelPicker(teamId: "T1", name: "Lumen", channels: channels, excluded: ["C4", "C5"])
            }),
            ("settings-chatgpt", view { $0.preview(section: .chatgpt, account: account, models: models) }),
            ("settings-chatgpt-signed-out", view { $0.preview(section: .chatgpt) }),
            ("settings-general", view { $0.preview(section: .general) }),
            ("settings-general-reset", view { $0.preview(section: .general, confirmingReset: true) }),
            ("settings-about", view { $0.preview(section: .about) }),
        ]
    }
}
```

Create `Sources/SplarkUI/Settings/SettingsModel.swift`:

```swift
import Foundation
import Observation
import SplarkKit

/// What Settings needs from outside: the engine, Slack's Allow, ChatGPT, login items and the browser.
/// `LiveSettingsServices` is the real one; tests use a fake.
@MainActor public protocol SettingsServices: AnyObject {
    var workspaces: [Workspace] { get }
    var pendingApps: [SlackAppRegistration] { get }
    var syncStatus: [String: SyncStatus] { get }
    var badge: SlackBadge? { get }
    var settings: SavedState.Settings { get }
    func channels(teamId: String) async -> [ChannelOption]
    func excludedChannels(teamId: String) -> Set<String>
    func setExcluded(_ channels: Set<String>, teamId: String) async
    func reconnect(teamId: String) async throws
    func finishConnecting(_ app: SlackAppRegistration) async throws
    func connect(userToken: String) async throws -> SlackConnection
    func added(_ connection: SlackConnection) async throws
    func remove(teamId: String) async throws
    func removePending(_ app: SlackAppRegistration) async
    func addWorkspace()
    func chatGPTAccount() async -> ChatGPTAccount?
    func models() async -> [String]
    func setModel(_ model: String?) async
    func signInToChatGPT() async throws
    func signOutOfChatGPT() async throws
    func setSummariesPaused(_ paused: Bool) async
    func setOpenAtLogin(_ on: Bool) throws
    func setShowCount(_ on: Bool) async
    func reset() async throws
    func open(_ url: URL)
}

/// Reconnect needs the workspace's client ID, which only the Keychain has.
public enum ReconnectError: Error, Equatable { case noSavedSignIn }

/// A line in Settings → Workspaces: a connected workspace, or an app still waiting for an admin.
public struct WorkspaceRow: Identifiable, Equatable {
    public enum Action: Equatable, Sendable {
        case reconnect, pasteNewToken, finishConnecting

        public var title: String {
            switch self {
            case .reconnect: "Reconnect"
            case .pasteNewToken: "Paste new token"
            case .finishConnecting: "Finish connecting"
            }
        }
    }

    public let id: String          // the team ID, or the pending app's client ID
    public let name: String
    public let status: WorkspaceStatusText
    public let action: Action?     // the button the row needs, if any
    let pending: SlackAppRegistration?

    public var canExcludeChannels: Bool { pending == nil }
}

/// The excluded-channels sheet: every channel, a search, and checkmarks for the excluded ones.
public struct ChannelPicker: Equatable {
    public let teamId: String
    public let name: String
    public let channels: [ChannelOption]
    public var excluded: Set<String>
    public var search = ""

    public var shown: [ChannelOption] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? channels : channels.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}

/// Settings (spec §4.5): workspaces, ChatGPT, general switches and about.
@MainActor @Observable public final class SettingsModel {
    public enum Section: String, CaseIterable { case workspaces = "Workspaces", chatgpt = "ChatGPT", general = "General", about = "About" }

    public var section: Section = .workspaces
    public private(set) var message: String?           // the last thing that went wrong, shown at the top
    public private(set) var working: String?           // the row waiting for Allow
    public private(set) var pasting: String?           // the row showing a token field
    public var newToken = ""
    public private(set) var removal: WorkspaceRow?
    public var channelPicker: ChannelPicker?
    public private(set) var confirmingReset = false

    public private(set) var account: ChatGPTAccount?
    public private(set) var models: [String] = []
    public private(set) var signingIn = false

    // As the engine has them now, so a pause from the menu shows here too.
    public var openAtLogin: Bool { services.settings.openAtLogin }
    public var showCount: Bool { services.settings.showCount }
    public var summariesPaused: Bool { services.settings.summariesPaused }
    public var model: String? { services.settings.model }   // nil: the recommended default

    private let services: SettingsServices
    private let now: () -> Date
    private let onReset: () -> Void
    private var allowTask: Task<Void, Error>?   // Reconnect or Finish connecting, holding the app's redirect port

    public init(services: SettingsServices, now: @escaping () -> Date = Date.init, onReset: @escaping () -> Void = {}) {
        self.services = services
        self.now = now
        self.onReset = onReset
    }

    /// When the window opens: the ChatGPT account and its models.
    public func load() async {
        account = await services.chatGPTAccount()
        models = account == nil ? [] : await services.models()
    }

    // MARK: Workspaces

    public var workspaceRows: [WorkspaceRow] {
        let workspaces = services.workspaces.map { workspace in
            let sync = services.syncStatus[workspace.teamId]
            return WorkspaceRow(id: workspace.teamId, name: workspace.name,
                                status: Presenter.workspaceStatus(workspace, sync: sync, now: now()),
                                action: Self.action(workspace, sync: sync), pending: nil)
        }
        let pending = services.pendingApps.map { app in
            WorkspaceRow(id: app.clientId, name: "Slack workspace",
                         status: WorkspaceStatusText(title: "Waiting for approval", detail: "An admin needs to approve it"),
                         action: .finishConnecting, pending: app)
        }
        return workspaces + pending
    }

    private static func action(_ workspace: Workspace, sync: SyncStatus?) -> WorkspaceRow.Action? {
        let needed = sync?.problem?.stopsSync == true || sync?.missingScope == true
        guard needed else { return nil }
        return workspace.redirectPort == nil ? .pasteNewToken : .reconnect
    }

    public var badgeLine: String {
        services.badge == nil
            ? "Slack isn't open, or its Dock badge can't be read, so Splark checks every couple of minutes."
            : "Slack is open, so new messages show up within seconds."
    }

    public func perform(_ action: WorkspaceRow.Action, on row: WorkspaceRow) async {
        message = nil
        switch action {
        case .pasteNewToken:
            pasting = row.id
            newToken = ""
        case .reconnect, .finishConnecting:
            guard working == nil else { return }   // one Allow at a time: they would want the same port
            working = row.id
            let task = Task { [services] in
                if let app = row.pending { try await services.finishConnecting(app) } else { try await services.reconnect(teamId: row.id) }
            }
            allowTask = task
            defer {
                working = nil
                allowTask = nil
            }
            do {
                try await task.value
            } catch ReconnectError.noSavedSignIn {
                message = "Splark can't read \(row.name)'s saved sign-in from the Keychain. Remove it and add it again."
            } catch {
                if !task.isCancelled { message = SetupModel.message(for: error) }
            }
        }
    }

    /// A pasted token's workspace has no app to Allow again: a fresh token from the same workspace replaces it.
    public func savePastedToken() async {
        guard let teamId = pasting, let row = workspaceRows.first(where: { $0.id == teamId }) else { return }
        let token = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        message = nil
        do {
            let connection = try await services.connect(userToken: token)
            guard connection.workspace.teamId == teamId else {
                message = "That token is for \(connection.workspace.name), not \(row.name). Paste one made in \(row.name)."
                return
            }
            try await services.added(connection)
            pasting = nil
            newToken = ""
        } catch {
            message = SetupModel.message(for: error)
        }
    }

    /// Stops waiting for Allow, freeing the redirect port: the window closed, or the user clicked Cancel.
    public func cancel() {
        allowTask?.cancel()
    }

    public func cancelPasting() {
        pasting = nil
        newToken = ""
    }

    public func addWorkspace() { services.addWorkspace() }

    public func askToRemove(_ row: WorkspaceRow) { removal = row }
    public func cancelRemoval() { removal = nil }

    public var removalNote: String {
        guard let removal else { return "" }
        if removal.pending != nil {
            return "Splark forgets this app. To delete it from Slack too, open api.slack.com/apps, choose Splark, and click Delete App."
        }
        return "Splark forgets \(removal.name)'s token. To delete your private Splark app too, open api.slack.com/apps, choose Splark, and click Delete App."
    }

    public func confirmRemoval() async {
        guard let row = removal else { return }
        removal = nil
        do {
            if let app = row.pending { await services.removePending(app) } else { try await services.remove(teamId: row.id) }
        } catch {
            message = "Removed \(row.name), but macOS wouldn't delete its token from the Keychain."   // the engine removes it regardless
        }
    }

    public func openSlackApps() { services.open(URL(string: "https://api.slack.com/apps")!) }

    // MARK: Excluded channels

    public func editChannels(_ row: WorkspaceRow) async {
        guard row.canExcludeChannels else { return }
        let channels = await services.channels(teamId: row.id)
        channelPicker = ChannelPicker(teamId: row.id, name: row.name, channels: channels, excluded: services.excludedChannels(teamId: row.id))
    }

    public func toggleChannel(_ id: String) {
        guard var picker = channelPicker else { return }
        if picker.excluded.contains(id) { picker.excluded.remove(id) } else { picker.excluded.insert(id) }
        channelPicker = picker
    }

    public func saveChannels() async {
        guard let picker = channelPicker else { return }
        channelPicker = nil
        await services.setExcluded(picker.excluded, teamId: picker.teamId)
    }

    public func cancelChannels() { channelPicker = nil }

    // MARK: ChatGPT

    public var recommendedModel: String? { ChatGPTLLMClient.pickModel(available: models, chosen: nil) }

    public func chooseModel(_ model: String?) async {
        await services.setModel(model)
    }

    public func signIn() async {
        message = nil
        signingIn = true
        defer { signingIn = false }
        do {
            try await services.signInToChatGPT()
            account = await services.chatGPTAccount()
            models = await services.models()
        } catch ChatGPTAuthError.denied {
            message = "Sign-in was cancelled. Try again when you're ready."
        } catch {
            message = "Couldn't sign in to ChatGPT. Try again."
        }
    }

    public func signOut() async {
        message = nil
        do {
            try await services.signOutOfChatGPT()
            account = nil
            models = []
        } catch {
            message = "Couldn't sign out: \(error.localizedDescription)"
        }
    }

    // MARK: General

    public func setOpenAtLogin(_ on: Bool) {
        do {
            try services.setOpenAtLogin(on)
        } catch {
            message = "macOS didn't let Splark change this. Check System Settings → General → Login Items."
        }
    }

    public func setShowCount(_ on: Bool) async { await services.setShowCount(on) }

    public func setSummariesPaused(_ paused: Bool) async { await services.setSummariesPaused(paused) }

    public func askToReset() { confirmingReset = true }
    public func cancelReset() { confirmingReset = false }

    /// Splark starts over even if a Keychain item wouldn't go: the engine has forgotten everything else, and a leftover
    /// token is replaced when that workspace connects again.
    public func confirmReset() async {
        confirmingReset = false
        try? await services.reset()
        onReset()
    }

    /// Previews and renders only: put the model in a state without going through the services.
    func preview(section: Section, message: String? = nil, working: String? = nil, pasting: String? = nil, removal: WorkspaceRow? = nil,
                 account: ChatGPTAccount? = nil, models: [String] = [], confirmingReset: Bool = false) {
        self.section = section
        self.message = message
        self.working = working
        self.pasting = pasting
        self.removal = removal
        self.account = account
        self.models = models
        self.confirmingReset = confirmingReset
    }

    // MARK: About

    public var version: String { "Version \(SplarkInfo.version) · Open source, MIT licence" }
    public func openRepository() { services.open(URL(string: "https://github.com/ivliag/splark")!) }
    public func openDoll() { services.open(URL(string: "https://github.com/xiaogdgenuine/Doll")!) }
}
```

Create `Sources/SplarkUI/Settings/SettingsView.swift`:

```swift
import SplarkKit
import SwiftUI

/// The Settings window's content (spec §4.5): four sections behind tabs in the title bar, in setup's look.
public struct SettingsView: View {
    let model: SettingsModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var channelsHeight: CGFloat = 0

    public init(model: SettingsModel) { self.model = model }

    public var body: some View {
        let palette = Palette(scheme)
        VStack(alignment: .leading, spacing: 0) {
            tabs(palette).frame(maxWidth: .infinity).frame(height: 28)
            VStack(alignment: .leading, spacing: 14) {
                if let message = model.message { MessageBox(level: .bright, markdown: message) }
                switch model.section {
                case .workspaces: if model.channelPicker != nil { channels(palette) } else { workspaces(palette) }
                case .chatgpt: chatgpt(palette)
                case .general: general(palette)
                case .about: about(palette)
                }
            }
            .padding(EdgeInsets(top: 18, leading: 28, bottom: 26, trailing: 28))
        }
        .frame(width: 520)
        .background(palette.window)
    }

    private func tabs(_ palette: Palette) -> some View {
        HStack(spacing: 4) {
            ForEach(SettingsModel.Section.allCases, id: \.self) { section in
                let selected = section == model.section
                Button { model.section = section } label: {
                    Text(section.rawValue).font(Theme.font(12, selected ? .semibold : .medium))
                        .foregroundStyle(selected ? palette.text : palette.secondary)
                        .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? palette.chip : Ink(0, opacity: 0)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
    }

    private func heading(_ text: String, _ palette: Palette) -> some View {
        Text(text).font(Theme.font(12, .semibold)).foregroundStyle(palette.secondary)
    }

    private func note(_ text: String, _ palette: Palette) -> some View {
        Text(text).font(Theme.font(11.5)).foregroundStyle(palette.tertiary).fixedSize(horizontal: false, vertical: true)
    }

    /// Asks before something that can't be undone: removing a workspace, resetting Splark.
    private func confirmation(_ title: String, _ detail: String, action: String, _ palette: Palette,
                              cancel: @escaping () -> Void, confirm: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.font(13, .semibold)).foregroundStyle(palette.text)
            RichText(markdown: detail, size: 12.5)
            HStack(spacing: 8) {
                Spacer()
                WindowButton(title: "Cancel", kind: .secondary, action: cancel)
                WindowButton(title: action, action: confirm)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.chip))
    }

    // MARK: Workspaces

    private func workspaces(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Card {
                    ForEach(Array(model.workspaceRows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { CardSeparator() }
                        workspaceRow(row, palette)
                    }
                    if !model.workspaceRows.isEmpty { CardSeparator() }
                    Button { model.addWorkspace() } label: {
                        Text("+ Add workspace").font(Theme.font(13, .medium)).foregroundStyle(palette.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let removal = model.removal {
                confirmation("Remove \(removal.name)?", model.removalNote, action: "Remove", palette,
                             cancel: { model.cancelRemoval() }, confirm: { Task { await model.confirmRemoval() } })
            }
            HStack(alignment: .top, spacing: 8) {
                SparkView(level: model.badgeLine.hasPrefix("Slack is open") ? .bright : .dimmed).foregroundStyle(palette.spark).padding(.top, 2)
                note(model.badgeLine, palette)
            }
        }
    }

    private func workspaceRow(_ row: WorkspaceRow, _ palette: Palette) -> some View {
        HStack(alignment: .top, spacing: 12) {
            InitialTile(text: row.pending == nil ? InitialTile.initials(row.name) : "?")
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name).font(Theme.font(13, .semibold)).foregroundStyle(palette.text)
                        Text("\(row.status.title) · \(row.status.detail)").font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        if row.canExcludeChannels { MiniButton(title: "Channels…") { Task { await model.editChannels(row) } } }
                        MiniButton(title: "Remove") { model.askToRemove(row) }
                    }
                }
                if model.working == row.id {
                    HStack(spacing: 8) {
                        CyclingSpark().foregroundStyle(palette.spark)
                        RichText(markdown: "Waiting for you to click **Allow** in your browser…", size: 12)
                        Spacer(minLength: 0)
                        MiniButton(title: "Cancel") { model.cancel() }
                    }
                } else if model.pasting == row.id {
                    HStack(spacing: 8) {
                        TokenField(placeholder: "Paste a new user token (xoxp-…)", text: Binding(get: { model.newToken }, set: { model.newToken = $0 })) {
                            Task { await model.savePastedToken() }
                        }
                        WindowButton(title: "Cancel", kind: .ghost) { model.cancelPasting() }
                        WindowButton(title: "Save", enabled: !model.newToken.isEmpty) { Task { await model.savePastedToken() } }
                    }
                } else if let action = row.action {
                    MiniButton(title: action.title) {
                        Task { await model.perform(action, on: row) }
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
    }

    // MARK: Excluded channels

    private func channels(_ palette: Palette) -> some View {
        let picker = model.channelPicker!
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Excluded channels in \(picker.name)").font(Theme.font(15, .semibold)).foregroundStyle(palette.text)
                note("Splark leaves these channels out. Direct messages are never excluded.", palette)
            }
            TokenField(placeholder: "Search channels", text: Binding(get: { model.channelPicker?.search ?? "" }, set: { model.channelPicker?.search = $0 }),
                       monospaced: false)
            if picker.channels.isEmpty {
                note("Channels appear here after Splark's first catch-up in \(picker.name).", palette).padding(.vertical, 8)
            } else {
                let list = Card {
                    ForEach(Array(picker.shown.enumerated()), id: \.element.id) { index, channel in
                        if index > 0 { CardSeparator() }
                        Button { model.toggleChannel(channel.id) } label: {
                            HStack(spacing: 10) {
                                Checkbox(on: picker.excluded.contains(channel.id))
                                Text(channel.title).font(Theme.font(13)).foregroundStyle(palette.text)
                                if channel.isPrivate { Text("private").font(Theme.font(11)).foregroundStyle(palette.tertiary) }
                                Spacer()
                            }
                            .padding(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if isSnapshot {
                    list
                } else {
                    ScrollView { list.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { channelsHeight = $0 } }
                        .scrollIndicators(.automatic)
                        .frame(height: min(channelsHeight, 300))
                }
            }
            HStack(spacing: 8) {
                note("\(picker.excluded.count) excluded", palette)
                Spacer()
                WindowButton(title: "Cancel", kind: .secondary) { model.cancelChannels() }
                WindowButton(title: "Save") { Task { await model.saveChannels() } }
            }
        }
    }

    // MARK: ChatGPT

    private func chatgpt(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Card {
                HStack(spacing: 12) {
                    InitialTile(text: String((model.account?.email ?? "?").prefix(1)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.account.map { $0.email ?? "Signed in" } ?? "Not signed in").font(Theme.font(13, .semibold)).foregroundStyle(palette.text)
                        Text(model.account.map { $0.canUsePlan ? "ChatGPT · summaries use your plan's usage" : "ChatGPT · this plan can't be used for summaries" }
                             ?? "Sign in to get summaries. Splark still ranks what's unread without them.")
                            .font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                    }
                    Spacer(minLength: 8)
                    if model.signingIn {
                        CyclingSpark().foregroundStyle(palette.spark)
                    } else if model.account == nil {
                        MiniButton(title: "Sign in with ChatGPT") { Task { await model.signIn() } }
                    } else {
                        MiniButton(title: "Sign out") { Task { await model.signOut() } }
                    }
                }
                .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
                if model.account != nil {
                    CardSeparator()
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Model").font(Theme.font(13)).foregroundStyle(palette.text)
                            Text("Recommended: \(model.recommendedModel ?? "the plan's first model")").font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                        }
                        Spacer()
                        ModelMenu(model: model)
                    }
                    .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
                }
                CardSeparator()
                SwitchRow(title: "Pause summaries", detail: "Splark keeps ranking what's unread, without summaries",
                          isOn: Binding(get: { model.summariesPaused }, set: { on in Task { await model.setSummariesPaused(on) } }))
            }
            note("Only conversations that changed are summarised. Messages go to OpenAI with storage turned off, and nowhere else.", palette)
        }
    }

    // MARK: General

    private func general(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Card {
                SwitchRow(title: "Open at login", isOn: Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }))
                CardSeparator()
                SwitchRow(title: "Show count next to the spark", detail: "How many items need you",
                          isOn: Binding(get: { model.showCount }, set: { on in Task { await model.setShowCount(on) } }))
            }
            if model.confirmingReset {
                confirmation("Reset Splark?", "Splark forgets **every workspace, token, setting and summary**, then starts setup again. Your private Slack apps stay until you delete them at api.slack.com/apps.",
                             action: "Reset", palette, cancel: { model.cancelReset() }, confirm: { Task { await model.confirmReset() } })
            } else {
                Card {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Reset Splark").font(Theme.font(13)).foregroundStyle(palette.text)
                            Text("Forget everything and start setup again").font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                        }
                        Spacer()
                        MiniButton(title: "Reset…") { model.askToReset() }
                    }
                    .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
                }
            }
        }
    }

    // MARK: About

    private func about(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            AppIconView(size: 64).padding(.top, 8).padding(.bottom, 10)
            Text("Splark").font(Theme.font(20, .semibold)).foregroundStyle(palette.text)
            Text(model.version).font(Theme.font(12)).foregroundStyle(palette.secondary).padding(.top, 2).padding(.bottom, 12)
            MiniButton(title: "github.com/ivliag/splark ↗") { model.openRepository() }.padding(.bottom, 18)
            RichText(markdown: "Mirroring Slack's Dock badge into the menu bar is an idea from **Doll**. The pixel art is inspired by 1-bit icon sheets.", size: 12)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            MiniButton(title: "Doll on GitHub ↗") { model.openDoll() }.padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The model picker: a menu of the plan's models, the recommended default first. Offscreen snapshots draw its label.
struct ModelMenu: View {
    let model: SettingsModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let palette = Palette(scheme)
        let label = HStack(spacing: 4) {
            Text(model.model ?? "Recommended").font(Theme.font(12, .medium))
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(palette.text)
        .padding(EdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 9))
        .background(RoundedRectangle(cornerRadius: 7).fill(palette.chip))
        if isSnapshot {
            label
        } else {
            Menu {
                Button("Recommended (\(model.recommendedModel ?? "first available"))") { Task { await model.chooseModel(nil) } }
                Divider()
                ForEach(model.models, id: \.self) { name in Button(name) { Task { await model.chooseModel(name) } } }
            } label: { label }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
        }
    }
}

/// A checkbox in the prototype's monochrome: a rounded square, filled with a tick when on.
struct Checkbox: View {
    let on: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme)
        RoundedRectangle(cornerRadius: 4)
            .fill(on ? palette.button : palette.field)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(on ? Ink(0, opacity: 0) : palette.fieldBorder, lineWidth: 1))
            .overlay { if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.buttonText) } }
            .frame(width: 16, height: 16)
            .accessibilityLabel(Text(on ? "Excluded" : "Included"))
    }
}
```

Create `Sources/SplarkUI/Settings/SettingsWindowController.swift`:

```swift
import AppKit
import SplarkKit
import SwiftUI

/// The real Settings services: the engine, WorkspaceSetup for Allow and pasted tokens, login items and the browser.
@MainActor public final class LiveSettingsServices: SettingsServices {
    private let engine: SplarkEngine
    private let setup: WorkspaceSetup
    private let loginItem: LoginItemControlling
    private let onAddWorkspace: () -> Void

    public init(engine: SplarkEngine, loginItem: LoginItemControlling, onAddWorkspace: @escaping () -> Void) {
        self.engine = engine
        self.setup = WorkspaceSetup(open: { url in Task { @MainActor in NSWorkspace.shared.open(url) } })
        self.loginItem = loginItem
        self.onAddWorkspace = onAddWorkspace
    }

    public var workspaces: [Workspace] { engine.workspaces }
    public var pendingApps: [SlackAppRegistration] { engine.pendingApps }
    public var syncStatus: [String: SyncStatus] { engine.syncStatus }
    public var badge: SlackBadge? { engine.badge }

    /// "Open at login" as macOS has it: the user may have changed it in System Settings.
    public var settings: SavedState.Settings {
        var settings = engine.settings
        settings.openAtLogin = loginItem.isEnabled
        return settings
    }

    public func channels(teamId: String) async -> [ChannelOption] { await engine.channels(teamId: teamId) }
    public func excludedChannels(teamId: String) -> Set<String> { engine.excludedChannels(teamId: teamId) }
    public func setExcluded(_ channels: Set<String>, teamId: String) async { await engine.setExcluded(channels, teamId: teamId) }

    public func reconnect(teamId: String) async throws {
        guard let app = engine.registration(for: teamId) else { throw ReconnectError.noSavedSignIn }
        try await engine.connect(try await setup.authorize(app))
    }

    public func finishConnecting(_ app: SlackAppRegistration) async throws {
        let connection = try await setup.authorize(app)
        try await engine.connect(connection)
        await engine.removePendingApp(app)
    }

    public func connect(userToken: String) async throws -> SlackConnection { try await setup.connect(userToken: userToken) }
    public func added(_ connection: SlackConnection) async throws { try await engine.connect(connection) }
    public func remove(teamId: String) async throws { try await engine.disconnect(teamId: teamId) }
    public func removePending(_ app: SlackAppRegistration) async { await engine.removePendingApp(app) }
    public func addWorkspace() { onAddWorkspace() }

    public func chatGPTAccount() async -> ChatGPTAccount? { await engine.chatGPTAccount() }
    public func models() async -> [String] { (try? await engine.availableModels()) ?? [] }
    public func setModel(_ model: String?) async { await engine.setModel(model) }
    public func signInToChatGPT() async throws {
        _ = try await engine.signInToChatGPT(open: { url in Task { @MainActor in NSWorkspace.shared.open(url) } })
    }
    public func signOutOfChatGPT() async throws { try await engine.signOutOfChatGPT() }
    public func setSummariesPaused(_ paused: Bool) async { await engine.setSummariesPaused(paused) }

    public func setOpenAtLogin(_ on: Bool) throws {
        try loginItem.setEnabled(on)
        Task { await engine.updateSettings { $0.openAtLogin = on } }
    }

    public func setShowCount(_ on: Bool) async { await engine.updateSettings { $0.showCount = on } }
    public func reset() async throws { try await engine.reset() }
    public func open(_ url: URL) { NSWorkspace.shared.open(url) }
}

/// The Settings window: 520 pt wide, the section tabs in its transparent title bar. It fits each section's height.
@MainActor public final class SettingsWindowController: FittedWindow {
    private let model: SettingsModel

    public init(model: SettingsModel) {
        self.model = model
        super.init(rootView: SettingsView(model: model), size: NSSize(width: 520, height: 360), title: "Splark Settings")
    }

    /// Shows a section, reading the ChatGPT account afresh.
    public func show(_ section: SettingsModel.Section) {
        model.section = section
        show()
        Task { await model.load() }
    }

    /// A closed window stops waiting for Allow, so the app's redirect port is free for the next try.
    override public func windowWillClose(_ notification: Notification) {
        model.cancel()
        super.windowWillClose(notification)
    }
}
```

In `Sources/splark-dev/RenderUICommand.swift`, replace:

```swift
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (name, view) in PanelGallery.states() + SetupGallery.states() {
        for scheme in [ColorScheme.light, .dark] {
```

with:

```swift
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (name, view) in PanelGallery.states() + SetupGallery.states() + SettingsGallery.states() {
        for scheme in [ColorScheme.light, .dark] {
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test`
Expected: PASS, `✔ Test run with 346 tests`. `swift build --build-tests` prints no warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/SplarkKit/Sync/SyncEngine.swift Sources/SplarkKit/Sync/SyncSchedule.swift Sources/SplarkUI/Components.swift Sources/SplarkUI/Fixtures.swift Sources/SplarkUI/Settings/SettingsModel.swift Sources/SplarkUI/Settings/SettingsView.swift Sources/SplarkUI/Settings/SettingsWindowController.swift Sources/splark-dev/RenderUICommand.swift Tests/SplarkUITests/SettingsModelTests.swift Tests/SplarkUITests/SettingsViewTests.swift
git commit -m "Add Settings: workspaces, ChatGPT, general and about" -m "Workspaces with their fixes, exclusions, ChatGPT account and model, the
switches, Reset and About, in a window that fits each section."
```

- [ ] **Step 6: Look at every section**

Run: `swift run splark-dev render-ui --out /tmp/ui`
Expected: Read `settings-workspaces-light.png`, `settings-channels-dark.png`, `settings-chatgpt-dark.png`, `settings-general-reset-light.png` and `settings-about-light.png`. No button text should wrap, and the rows should line up with setup's.

---

### Task 12: Run the app

`AppController` puts it together:
- **At launch:** it starts the engine, shows the spark, and opens setup when nothing is connected yet.
- **The spark** follows the inbox and the Show count switch, through `Watch`, a small observation helper.
- **The panel's content** is the live inbox. Its header line is computed every 30 seconds. Its height limit comes from `PanelController.layout`.
- **Action failures** that happen after the panel is done with them (a mark read Slack refused, a link that wouldn't open) become toasts.
- **Settings:** its "+ Add workspace" opens setup with only the Slack step. Reset returns to setup.
- **Quitting** sends pending mark-reads and saves.
- **The main menu** never shows, but it gives the windows ⌘V, ⌘C, ⌘A, ⌘Z and ⌘W. Without it, pasting a token doesn't work.

`AppDelegate` is reduced to creating the controller. `SPLARK_DEBUG_PANEL=1` opens the panel over the fixtures, with no Keychain or Slack, prints where the spark and the panel are, and quits.

**Files:**
- Create: `Sources/SplarkUI/AppController.swift`, `Sources/SplarkUI/Watch.swift`
- Modify: `Sources/Splark/AppDelegate.swift`, `Sources/SplarkUI/Fixtures.swift`, `Sources/SplarkUI/Setup/SetupModel.swift`, `Sources/SplarkUI/Setup/SetupView.swift`, `Sources/SplarkUI/StatusItemController.swift`
- Test: `Tests/SplarkUITests/AppControllerTests.swift`, `Tests/SplarkUITests/SetupModelTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–11.
- Produces:
  - `AppController(environment: = .live(), loginItem: = MainAppLoginItem())`, plus the internal `init(environment:loginItem:statusButton:)` for tests.
  - Its methods:
    - `launch()` and `terminate() async`;
    - `togglePanel()`;
    - `showSetup(addingWorkspace:)` and `showSettings(_:)`;
    - `static mainMenu() -> NSMenu`;
    - `debugReport() -> String`.
  - `AppController.withoutAccounts()` and `showFixtures()`, for debug runs. `Fixtures.fill(_:)`.
  - `SetupModel(services:addingWorkspace:)`. When adding a workspace there is no step bar, no Back, and the last button reads Done.
  - `final class Watch` (`init(read, onChange)`, `cancel()`).
  - `StatusItemController.button` and `summariesPaused` become readable, for tests.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SplarkUITests/AppControllerTests.swift`:

```swift
import AppKit
import Observation
import Testing
@testable import SplarkKit
@testable import SplarkUI

@MainActor final class FakeLoginItem: LoginItemControlling {
    var isEnabled = false
    func setEnabled(_ on: Bool) throws { isEnabled = on }
}

@MainActor @Observable final class Counter {
    var value = 0
}

@MainActor @Suite(.serialized) struct AppControllerTests {
    let stateStore = StateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("splark-\(UUID().uuidString)/state.json"))
    let secrets = InMemorySecretStore()

    /// An app over an empty or waiting state: no workspace is running, so Slack is never called.
    func app(waiting: Bool = false) throws -> AppController {
        _ = NSApplication.shared
        var state = SavedState()
        if waiting { state.pendingApps = [SlackAppRegistration(appId: "A7", clientId: "7.7", redirectPort: 53684)] }
        try stateStore.save(state)
        let environment = EngineEnvironment(
            secrets: secrets, state: stateStore, slack: { _ in fatalError("no workspace runs in these tests") }, chatGPT: ChatGPTSession(store: secrets),
            llm: nil, badges: nil, sync: SyncEngine.Config(), triage: Triage.Config(), now: { now }, open: { _ in true })
        return AppController(environment: environment, loginItem: FakeLoginItem(), statusButton: NSButton())
    }

    func directMessage() -> SyncUpdate {
        var update = SyncUpdate()
        update.upsert(ConversationSnapshot(key: ItemKey(teamId: "T1", channelId: "D1"), kind: .dm, title: "Marta Ruiz",
                                           unread: [SnapshotMessage(ts: SlackTS.ts(ago(60)), authorId: "U2", author: "Marta Ruiz", text: "can you approve?", mentionsMe: false)],
                                           context: [], moreUnread: false))
        return update
    }

    @Test func aWatchSeesTheValueNowAndEveryChange() async {
        let counter = Counter()
        var seen: [Int] = []
        let watch = Watch({ counter.value }) { seen.append($0) }
        #expect(seen == [0])
        counter.value = 1
        #expect(await eventually { seen == [0, 1] })
        counter.value = 2
        #expect(await eventually { seen == [0, 1, 2] })
        watch.cancel()
        counter.value = 3
        try? await Task.sleep(for: .milliseconds(100))
        #expect(seen == [0, 1, 2])
    }

    @Test func theFirstRunOpensSetup() async throws {
        let app = try app()
        app.launch()
        #expect(app.engine.isRunning)
        #expect(app.setup?.isVisible == true && app.setupModel?.step == .welcome)
        app.setup?.close()
        #expect(app.setup == nil)
        await app.terminate()
    }

    @Test func aWorkspaceWaitingForApprovalSkipsSetup() async throws {
        let app = try app(waiting: true)
        app.launch()
        #expect(app.setup == nil)
        await app.terminate()
        #expect(!app.engine.isRunning)
    }

    @Test func theSparkFollowsTheInboxAndTheCountSwitch() async throws {
        let app = try app(waiting: true)
        app.launch()
        app.engine.inbox.setWorkspaces([lumen])
        app.engine.inbox.apply(directMessage())
        #expect(await eventually { app.statusItem.button.title == " 1" })
        await app.engine.updateSettings { $0.showCount = false }
        #expect(await eventually { app.statusItem.button.title == "" })
        #expect(app.statusItem.button.accessibilityLabel() == "Splark: 1 needs you")
        await app.terminate()
    }

    @Test func theMenuPausesSummaries() async throws {
        let app = try app(waiting: true)
        app.launch()
        app.setSummariesPaused(true)
        #expect(await eventually { app.engine.settings.summariesPaused && app.statusItem.summariesPaused })
        await app.terminate()
    }

    @Test func aClickOnTheSparkTogglesThePanel() async throws {
        let app = try app(waiting: true)
        app.launch()
        app.togglePanel()
        #expect(app.panel.isShown)
        app.panelModel.escape()
        #expect(!app.panel.isShown)
        app.togglePanel()
        app.panelModel.startReply(item())
        app.togglePanel()
        #expect(!app.panel.isShown && app.panelModel.expanded == nil)   // reopened, it starts collapsed
        await app.terminate()
    }

    @Test func addingAWorkspaceFromSettingsOpensSetupAtSlack() async throws {
        let app = try app(waiting: true)
        app.launch()
        app.showSettings()
        #expect(app.settings?.isVisible == true)
        app.settingsModel?.addWorkspace()
        #expect(app.setupModel?.step == .slack && app.setupModel?.addingWorkspace == true)
        app.setup?.close()
        app.settings?.close()
        #expect(app.settings == nil)
        await app.terminate()
    }

    @Test func resettingGoesBackToSetup() async throws {
        let app = try app(waiting: true)
        app.launch()
        app.showSettings()
        await app.settingsModel?.confirmReset()
        #expect(app.settings == nil)
        #expect(app.setupModel?.step == .welcome && app.setupModel?.addingWorkspace == false)
        #expect(app.engine.isRunning && app.engine.pendingApps.isEmpty)
        app.setup?.close()
        await app.terminate()
    }

    @Test func theMainMenuGivesWindowsTheEditingShortcuts() {
        let items = AppController.mainMenu().items.flatMap { $0.submenu?.items ?? [] }
        let expected: [(String, Selector)] = [
            ("x", #selector(NSText.cut(_:))), ("c", #selector(NSText.copy(_:))), ("v", #selector(NSText.paste(_:))),
            ("a", #selector(NSText.selectAll(_:))), ("z", Selector(("undo:"))), ("w", #selector(NSWindow.performClose(_:))),
            ("q", #selector(NSApplication.terminate(_:))),
        ]
        for (key, action) in expected {
            #expect(items.contains { $0.keyEquivalent == key && $0.action == action }, "⌘\(key)")
        }
    }
}
```

Append to `Tests/SplarkUITests/SetupModelTests.swift`:

```swift

@MainActor @Suite struct AddingAWorkspaceTests {
    let services = FakeSetupServices()

    @Test func addingAWorkspaceIsOnlyTheSlackStep() async {
        let m = SetupModel(services: services, addingWorkspace: true)
        #expect(m.step == .slack && m.addingWorkspace)
        m.token = "xoxe.xoxp-config"
        await m.connect()
        #expect(m.canContinue)
        m.next()
        #expect(services.log == ["create xoxe.xoxp-config", "authorize 1.2", "added T1", "finish"])   // no switches: Settings has them
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift build --build-tests`
Expected: the build fails: `cannot find 'AppController' in scope`, `cannot find 'Watch' in scope`, `extra argument 'addingWorkspace' in call`

- [ ] **Step 3: Implement**

Replace all of `Sources/Splark/AppDelegate.swift` with:

```swift
import AppKit
import SplarkUI

/// Runs Splark's AppController, and lets it stop the engine before the app quits.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = AppController.mainMenu()
        if ProcessInfo.processInfo.environment["SPLARK_DEBUG_PANEL"] != nil {
            controller = AppController.withoutAccounts()
            controller.launch()
            controller.showFixtures()
            reportPanel()
        } else {
            controller = AppController()
            controller.launch()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await controller.terminate()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Opens the panel over the fixtures, prints where the spark and the panel are, and quits: a check from a
    /// terminal, without screen-recording permission.
    private func reportPanel() {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            controller.togglePanel()
            try? await Task.sleep(for: .seconds(1.5))
            print(controller.debugReport())
            exit(0)
        }
    }
}
```

Create `Sources/SplarkUI/AppController.swift`:

```swift
import AppKit
import SplarkKit
import SwiftUI

/// Runs Splark (spec §5.2): the engine, the spark in the menu bar, the panel under it, setup on first run, and Settings.
@MainActor public final class AppController {
    public let engine: SplarkEngine
    private(set) var statusItem: StatusItemController!
    private(set) var panel: PanelController!
    private(set) var panelModel: PanelModel!
    private(set) var setup: SetupWindowController?
    private(set) var setupModel: SetupModel?
    private(set) var settings: SettingsWindowController?
    private(set) var settingsModel: SettingsModel?
    private let loginItem: LoginItemControlling
    private var watches: [Watch] = []

    public convenience init(environment: EngineEnvironment = .live(), loginItem: LoginItemControlling = MainAppLoginItem()) {
        self.init(environment: environment, loginItem: loginItem, statusButton: nil)
    }

    /// `statusButton` stands in for the menu bar's in tests.
    init(environment: EngineEnvironment, loginItem: LoginItemControlling, statusButton: NSButton?) {
        engine = SplarkEngine(environment: environment)
        self.loginItem = loginItem
        let handlers = StatusItemController.Handlers(
            toggle: { [weak self] in self?.togglePanel() },
            refresh: { [weak self] in Task { await self?.engine.refreshNow() } },
            settings: { [weak self] in self?.showSettings() },
            pauseSummaries: { [weak self] in self?.setSummariesPaused($0) },
            quit: { NSApp.terminate(nil) })
        statusItem = statusButton.map { StatusItemController(button: $0, handlers: handlers) } ?? StatusItemController(handlers: handlers)
        panel = PanelController(anchor: { [weak self] in self?.statusItem.buttonFrameOnScreen })
        panelModel = PanelModel(actions: engine.actions, close: { [weak self] in self?.panel.close() },
                                openSlack: { NSWorkspace.shared.open(URL(string: "slack://open")!) },
                                openSettings: { [weak self] in self?.showSettings() })
        panel.onEscape = { [weak self] in self?.panelModel.escape() }
        panel.onClose = { [weak self] in self?.panelModel.panelClosed() }
    }

    /// Starts syncing, puts the spark in the menu bar, and opens setup when nothing is connected yet.
    public func launch() {
        engine.start()
        panel.setContent(LivePanel(engine: engine, model: panelModel, layout: panel.layout) { [weak self] in
            self?.panel.contentSizeChanged($0)
        })
        let engine = engine
        watches = [
            Watch({ (Presenter.statusItem(engine.inbox.summary, showCount: engine.settings.showCount), engine.settings.summariesPaused) }) { [weak self] state in
                self?.statusItem.show(state.0)
                self?.statusItem.setSummariesPaused(state.1)
            },
            Watch({ engine.actions.lastFailure }) { [weak self] failure in
                if let failure { self?.panelModel.showFailure(failure) }
            },
        ]
        if engine.workspaces.isEmpty && engine.pendingApps.isEmpty { showSetup() }
    }

    /// Before quitting: sends pending mark-reads and saves.
    public func terminate() async {
        watches.forEach { $0.cancel() }
        watches = []
        panel.close()
        await engine.stop()
    }

    public func togglePanel() { panel.toggle() }

    func setSummariesPaused(_ paused: Bool) { Task { await engine.setSummariesPaused(paused) } }

    // MARK: Windows

    /// First run, or after Reset: all four steps. From Settings' "+ Add workspace": only the Slack step.
    public func showSetup(addingWorkspace: Bool = false) {
        if let setup, setupModel?.addingWorkspace == addingWorkspace { return setup.show() }
        setup?.close()
        let services = LiveSetupServices(engine: engine, loginItem: loginItem, onFinish: { [weak self] in self?.setup?.close() })
        let model = SetupModel(services: services, addingWorkspace: addingWorkspace)
        let window = SetupWindowController(model: model)
        window.onClose = { [weak self, weak window] in
            guard let self, self.setup === window else { return }
            self.setup = nil
            self.setupModel = nil
        }
        setup = window
        setupModel = model
        window.show()
    }

    public func showSettings(_ section: SettingsModel.Section = .workspaces) {
        panel.close()
        if settings == nil {
            let services = LiveSettingsServices(engine: engine, loginItem: loginItem, onAddWorkspace: { [weak self] in self?.showSetup(addingWorkspace: true) })
            let model = SettingsModel(services: services, onReset: { [weak self] in self?.didReset() })
            let window = SettingsWindowController(model: model)
            window.onClose = { [weak self, weak window] in
                guard let self, self.settings === window else { return }
                self.settings = nil
                self.settingsModel = nil
            }
            settings = window
            settingsModel = model
        }
        settings?.show(section)
    }

    /// Reset stopped the engine and forgot everything: start again from setup.
    private func didReset() {
        settings?.close()
        setup?.close()
        engine.start()
        showSetup()
    }

    // MARK: Menus

    /// The app's main menu. It never shows (Splark has no Dock icon or menu bar of its own), but its key equivalents
    /// give the setup and Settings windows ⌘V, ⌘C, ⌘A, ⌘Z and ⌘W.
    public static func mainMenu() -> NSMenu {
        let main = NSMenu()
        func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }
        func add(_ title: String, _ items: [NSMenuItem]) {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            main.addItem(holder)
        }
        add("Splark", [item("Quit Splark", #selector(NSApplication.terminate(_:)), "q")])
        add("Edit", [item("Undo", Selector(("undo:")), "z"), item("Redo", Selector(("redo:")), "z", [.command, .shift]), .separator(),
                     item("Cut", #selector(NSText.cut(_:)), "x"), item("Copy", #selector(NSText.copy(_:)), "c"),
                     item("Paste", #selector(NSText.paste(_:)), "v"), item("Select All", #selector(NSText.selectAll(_:)), "a")])
        add("Window", [item("Close", #selector(NSWindow.performClose(_:)), "w")])
        return main
    }

    // MARK: Debugging

    /// Where the spark and the panel are: for `SPLARK_DEBUG_PANEL` runs, checked from a terminal without screen
    /// recording. (Opened without a click, the panel can't take the keyboard, so that isn't reported.)
    public func debugReport() -> String {
        """
        status item: \(statusItem.buttonFrameOnScreen.map { "\($0)" } ?? "no window")
        panel: shown=\(panel.isShown) frame=\(panel.window.frame) max height=\(panel.maxContentHeight)
        """
    }
}

/// The panel's content in the app: the engine's inbox and header line, with times kept fresh.
struct LivePanel: View {
    let engine: SplarkEngine
    let model: PanelModel
    let layout: PanelLayout   // the height limit, for the screen the panel last opened on
    let onSize: (CGSize) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            PanelView(inbox: engine.inbox,
                      status: Presenter.headerStatus(workspaces: engine.workspaces, sync: engine.syncStatus, triage: engine.triageState, now: context.date),
                      model: model, now: context.date, layout: .live(maxHeight: layout.maxHeight), onSize: onSize)
        }
    }
}
```

In `Sources/SplarkUI/Fixtures.swift`, replace:

```swift
    public static func inbox() -> InboxStore {
        let store = InboxStore()
        store.setWorkspaces(workspaces)
        var update = SyncUpdate()
```

with:

```swift
    public static func inbox() -> InboxStore {
        let store = InboxStore()
        fill(store)
        return store
    }

    /// Puts the prototype's conversations, with their summaries, into `store`.
    public static func fill(_ store: InboxStore) {
        store.setWorkspaces(workspaces)
        var update = SyncUpdate()
```

In `Sources/SplarkUI/Fixtures.swift`, replace:

```swift
        store.apply(results)
        return store
    }
```

with:

```swift
        store.apply(results)
    }
```

In `Sources/SplarkUI/Fixtures.swift`, replace:

```swift
            ("setup-done", view { $0.preview(step: .done, connected: lumen) }),
        ]
```

with:

```swift
            ("setup-done", view { $0.preview(step: .done, connected: lumen) }),
            ("setup-add-workspace", AnyView(SetupView(model: SetupModel(services: PreviewSetupServices(), addingWorkspace: true)))),
        ]
```

In `Sources/SplarkUI/Fixtures.swift`, replace:

```swift
            ("settings-about", view { $0.preview(section: .about) }),
        ]
    }
}
```

with:

```swift
            ("settings-about", view { $0.preview(section: .about) }),
        ]
    }
}

extension AppController {
    /// For `SPLARK_DEBUG_PANEL` runs: no Keychain, a throwaway state with an app waiting for approval (so setup stays
    /// closed), and no Slack. Call `showFixtures()` after `launch()`.
    public static func withoutAccounts() -> AppController {
        let secrets = InMemorySecretStore()
        let state = StateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("splark-debug-\(UUID().uuidString)/state.json"))
        var saved = SavedState()
        saved.pendingApps = [SlackAppRegistration(appId: nil, clientId: "debug", redirectPort: 53682)]
        try? state.save(saved)
        let environment = EngineEnvironment(
            secrets: secrets, state: state, slack: { _ in fatalError("debug runs have no workspaces") }, chatGPT: ChatGPTSession(store: secrets),
            llm: nil, badges: nil, sync: SyncEngine.Config(), triage: Triage.Config(), now: { Date() }, open: { _ in true })
        return AppController(environment: environment, loginItem: MainAppLoginItem(), statusButton: nil)
    }

    /// The prototype's conversations in the running engine's inbox.
    public func showFixtures() {
        Fixtures.fill(engine.inbox)
    }
}
```

In `Sources/SplarkUI/Setup/SetupModel.swift`, replace:

```swift
    public var step: Step = .welcome
    public var token = ""         // the pasted app configuration token
```

with:

```swift
    public var step: Step = .welcome
    public let addingWorkspace: Bool   // from Settings' "+ Add workspace": only the Slack step, then Done
    public var token = ""         // the pasted app configuration token
```

In `Sources/SplarkUI/Setup/SetupModel.swift`, replace:

```swift

    public init(services: SetupServices) { self.services = services }

```

with:

```swift

    public init(services: SetupServices, addingWorkspace: Bool = false) {
        self.services = services
        self.addingWorkspace = addingWorkspace
        if addingWorkspace { step = .slack }
    }

```

In `Sources/SplarkUI/Setup/SetupModel.swift`, replace:

```swift

    public func next() { step = Step(rawValue: step.rawValue + 1) ?? .done }
    public func back() { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
```

with:

```swift

    public func next() {
        if addingWorkspace { return services.finish() }
        step = Step(rawValue: step.rawValue + 1) ?? .done
    }
    public func back() { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
```

In `Sources/SplarkUI/Setup/SetupView.swift`, replace:

```swift
        HStack(spacing: 14) {
            ForEach(SetupModel.Step.allCases, id: \.self) { step in
                SparkView(level: step == model.step ? .bright : step.rawValue < model.step.rawValue ? .brighter : .dimmed)
```

with:

```swift
        HStack(spacing: 14) {
            ForEach(model.addingWorkspace ? [] : SetupModel.Step.allCases, id: \.self) { step in
                SparkView(level: step == model.step ? .bright : step.rawValue < model.step.rawValue ? .brighter : .dimmed)
```

In `Sources/SplarkUI/Setup/SetupView.swift`, replace:

```swift
        VStack(alignment: .leading, spacing: 0) {
            title("Connect Slack", palette)
            RichText(markdown: model.connected.isEmpty
```

with:

```swift
        VStack(alignment: .leading, spacing: 0) {
            title(model.addingWorkspace ? "Add a workspace" : "Connect Slack", palette)
            RichText(markdown: model.connected.isEmpty
```

In `Sources/SplarkUI/Setup/SetupView.swift`, replace:

```swift
                }
                WindowButton(title: "Back", kind: .secondary) { model.back() }
                WindowButton(title: "Continue", enabled: model.canContinue) { model.next() }
            }
```

with:

```swift
                }
                if !model.addingWorkspace { WindowButton(title: "Back", kind: .secondary) { model.back() } }
                WindowButton(title: model.addingWorkspace ? "Done" : "Continue", enabled: model.canContinue) { model.next() }
            }
```

In `Sources/SplarkUI/StatusItemController.swift`, replace:

```swift
    private let statusItem: NSStatusItem?
    private let button: NSButton
    private let handlers: Handlers
    private var summariesPaused = false

```

with:

```swift
    private let statusItem: NSStatusItem?
    let button: NSButton
    private let handlers: Handlers
    private(set) var summariesPaused = false

```

Create `Sources/SplarkUI/Watch.swift`:

```swift
import Observation

/// Calls `onChange` with what `read` returns now, then again after every change to the observable state it read.
@MainActor final class Watch {
    private var active = true

    init<Value>(_ read: @escaping @MainActor () -> Value, _ onChange: @escaping @MainActor (Value) -> Void) {
        track(read, onChange)
    }

    func cancel() { active = false }

    private func track<Value>(_ read: @escaping @MainActor () -> Value, _ onChange: @escaping @MainActor (Value) -> Void) {
        guard active else { return }
        // Observation calls back before the change lands: read again on the next turn of the main actor.
        let value = withObservationTracking(read) { [weak self] in
            Task { @MainActor in self?.track(read, onChange) }
        }
        onChange(value)
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test`
Expected: PASS, `✔ Test run with 356 tests`. `swift build --build-tests` prints no warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/Splark/AppDelegate.swift Sources/SplarkUI/AppController.swift Sources/SplarkUI/Fixtures.swift Sources/SplarkUI/Setup/SetupModel.swift Sources/SplarkUI/Setup/SetupView.swift Sources/SplarkUI/StatusItemController.swift Sources/SplarkUI/Watch.swift Tests/SplarkUITests/AppControllerTests.swift Tests/SplarkUITests/SetupModelTests.swift
git commit -m "Run the app: engine, spark, panel, setup and Settings together" -m "AppController starts the engine, follows the inbox with the spark, opens
setup on first run and Settings from the menu, and stops cleanly on quit."
```

- [ ] **Step 6: Check the real panel's geometry**

Run: `./scripts/build-app.sh debug && SPLARK_DEBUG_PANEL=1 build/Splark.app/Contents/MacOS/Splark`
Expected:
- Two lines. The panel is `shown=true` and 372 pt wide.
- Its top is 6 pt below the status item's bottom edge, and it is centred under the spark.
- Its height matches the offscreen render: `panel-light.png`'s height ÷ 2 − 48. That is 446 pt for the fixtures.

---

### Task 13: Ship it

What a release needs (spec §12):
- **`scripts/release.sh VERSION`** checks the version against `Info.plist` and `SplarkInfo`, builds the release app, verifies its signature, and zips it with `ditto`.
- **The release workflow** runs on `v*` tags: tests, the zip, and a *draft* release to review and publish. It refuses a toolchain older than Swift 6.2, which would quietly ship frosted glass instead of Liquid Glass.
- **The README** says how to install and how to open an unnotarised app on macOS 15+ and 14. It says what Splark sends to Slack and OpenAI (spec §8), why the Keychain asks again after updates, and how to remove Splark.
- **`docs/qa.md`** is the manual checklist to go through before tagging.

**Files:**
- Create: `.github/workflows/release.yml`, `docs/qa.md`, `scripts/release.sh`
- Modify: `README.md`
- Test: `Tests/SplarkKitTests/ReleaseScriptTests.swift`

**Interfaces:**
- Consumes: `build-app.sh` (Task 3).
- Produces:
  - `scripts/release.sh VERSION [--check]` writes `build/Splark-VERSION.zip`. A mismatched version prints "X doesn't match the app's version: …" and exits 1.
  - `.github/workflows/release.yml`.
  - `README.md` and `docs/qa.md`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SplarkKitTests/ReleaseScriptTests.swift`:

```swift
import Foundation
import Testing
@testable import SplarkKit

/// `scripts/release.sh` builds the zip a `v*` tag publishes; first it checks the tag against the app's version.
@Suite struct ReleaseScriptTests {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func release(_ arguments: String...) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("scripts/release.sh").path] + arguments
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }

    @Test func aTagMatchingTheAppsVersionPassesTheCheck() throws {
        let result = try release("v\(SplarkInfo.version)", "--check")
        #expect(result.status == 0)
        #expect(result.output == "\(SplarkInfo.version)\n")
    }

    @Test func refusesATagThatDoesntMatchTheAppsVersion() throws {
        let result = try release("v9.9.9", "--check")
        #expect(result.status == 1)
        #expect(result.output == "9.9.9 doesn't match the app's version: Support/Info.plist says \(SplarkInfo.version), SplarkInfo.swift says \(SplarkInfo.version).\n")
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift build --build-tests && swift test --filter 'ReleaseScriptTests'`
Expected: the build succeeds and the tests fail. Both fail with `No such file or directory`: the script doesn't exist yet.

- [ ] **Step 3: Implement**

Create `.github/workflows/release.yml`:

```yaml
name: Release
on:
  push:
    tags: ["v*"]

permissions:
  contents: write

jobs:
  release:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Toolchain
        # Liquid Glass needs the macOS 26 SDK (Swift 6.2 or later); an older toolchain would quietly ship frosted glass.
        run: |
          swift --version
          swift --version 2>&1 | grep -qE 'Swift version (6\.([2-9]|[1-9][0-9])|[7-9])' || { echo "Swift 6.2 or later is needed for Liquid Glass"; exit 1; }
      - name: Test
        run: swift test
      - name: Build the zip
        run: ./scripts/release.sh "$GITHUB_REF_NAME"
      - name: Draft the release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          gh release create "$GITHUB_REF_NAME" "build/Splark-$VERSION.zip" --draft --title "Splark $VERSION" --generate-notes \
            --notes "Download Splark-$VERSION.zip, unzip it and move Splark to Applications. It isn't notarised yet: see the README's Install section for opening it the first time."
```

Replace all of `README.md` with:

~~~markdown
# Splark

Slack, sorted by what needs you.

Splark is a small macOS menu-bar app. A pixel spark in the menu bar lights up when Slack needs you. Click it to see every unread conversation summarised in a line and sorted into three levels: **needs action**, **question for you** and **just comments**. Then reply, react or mark things as read without opening Slack.

> **Status: first release (0.1.0).** It isn't notarised yet, so the first launch takes one extra step (below). The design spec is in [`docs/superpowers/specs`](docs/superpowers/specs/2026-10-16-splark-design.md), and the interactive prototypes are in [`design/prototype`](design/prototype); open the HTML files in a browser.

## Install

Splark needs macOS 14 or later. Summaries need a ChatGPT Plus or Pro plan; without one, Splark still ranks what's unread.

1. Download `Splark-<version>.zip` from [Releases](https://github.com/ivliag/splark/releases), unzip it, and move **Splark** to **Applications**.
2. Open it once. Splark isn't notarised (that needs a paid Apple Developer ID), so macOS stops the first launch:
   - **macOS 15 and later:** open Splark and close the warning. Then open **System Settings → Privacy & Security**, scroll down to "Splark was blocked", and click **Open Anyway**.
   - **macOS 14:** right-click (or Control-click) Splark in Applications, choose **Open**, then click **Open** again.
3. Setup takes about two minutes:
   - **Slack:** paste a one-time token from api.slack.com/apps and click **Allow** in your browser. Splark creates a private Slack app that only you install. Repeat for each workspace.
   - **ChatGPT:** sign in with your ChatGPT account in the browser.

## Using it

- **The spark** is solid when something needs action, half-lit when questions are waiting, and faint when there's only chatter or nothing at all. The number next to it counts what needs you; turn it off in Settings → General.
- **Click the spark** to open the panel. Hover a row to reply, react (👀 ✅ 👍), open it in Slack, or mark it as read (you can undo for 4 seconds). Click a row to read the messages and reply. Chatter is folded into "Just comments" at the bottom. Esc closes the panel.
- **Right-click the spark** (or ⌥- or ⌃-click it) for Refresh now, Settings…, Pause summaries and Quit.
- **Settings** manages workspaces (reconnect, finish connecting after an admin's approval, excluded channels, remove), ChatGPT (account, model, pause), open at login, and Reset Splark.

## What Splark sends, and where

- **Slack:** Splark talks only to `slack.com`, through your own private Slack app. It reads the conversations you're in. It sends replies and reactions, and marks things read, only when you click.
- **OpenAI:** to summarise, Splark sends the unread messages of conversations that changed to OpenAI's Responses API under your ChatGPT account, with `store: false` so OpenAI doesn't keep them. For each conversation that is:
  - the messages' text (long ones cut short), their authors' names and when they were sent, plus up to three earlier messages for context;
  - the channel's or person's name, and the workspace's name;
  - your own display name and Slack member ID, so the model can tell what's aimed at you.

  Nothing else goes to OpenAI.
- **Nobody else:** there's no Splark server, and no analytics, crash reports or update checks.
- **On your Mac:** Slack and ChatGPT tokens are in your Keychain. `~/Library/Application Support/Splark/state.json` holds workspace names and IDs, excluded channels, settings, thread IDs and people's display names. Message text and summaries stay in memory and are gone when Splark quits.

## Keychain prompts after an update

Splark is signed ad hoc, so each new version looks like a different app to the Keychain. The first time a new version starts, macOS asks whether Splark may use its saved items: once for each workspace and once for ChatGPT. Enter your Mac password and click **Always Allow**. This stops once Splark has a Developer ID.

## Removing Splark

Open Settings → General → **Reset Splark**, which forgets every token and setting, then quit Splark and delete it from Applications. Your private Slack apps stay in Slack until you delete them: open [api.slack.com/apps](https://api.slack.com/apps), choose **Splark**, and click **Delete App**.

## Development

Requirements: macOS 14+, Xcode 16 or newer (Swift 6).

```bash
swift test                                      # all unit tests
./scripts/build-app.sh debug                    # builds build/Splark.app (ad-hoc signed)
open build/Splark.app
swift run splark-dev                            # developer commands (run it for the list)
swift run splark-dev inbox                      # the whole engine against your Slack and ChatGPT, printing the inbox
swift run splark-dev triage-eval                # score the triage evaluation set against your ChatGPT plan
swift run splark-dev render-ui --out .context/ui   # every panel, setup and Settings state as PNGs, light and dark
SPLARK_DEBUG_PANEL=1 build/Splark.app/Contents/MacOS/Splark   # opens the panel over sample data, prints where it is, quits
```

`splark-dev` keeps its tokens in the Keychain under the service `dev.splark.dev` and its state in `dev-state.json`, separate from the app. What the integration spikes found is in [`docs/spikes.md`](docs/spikes.md).

**Releasing:** set the version in `Support/Info.plist` and `Sources/SplarkKit/SplarkInfo.swift`, go through [`docs/qa.md`](docs/qa.md), then push a tag such as `v0.1.0`. GitHub Actions runs the tests, builds `Splark-0.1.0.zip` with `scripts/release.sh`, and drafts a release to review and publish.

## Credits

The idea of putting Slack's Dock badge into the menu bar comes from [Doll](https://github.com/xiaogdgenuine/Doll) by xiaogdgenuine. Splark is a separate project and contains no Doll code. The pixel art is inspired by 1-bit icon sheets.

## Licence

[MIT](LICENSE)
~~~

Create `docs/qa.md`:

```markdown
# Release QA

Go through this on a real Mac before tagging a release: macOS 26 for Liquid Glass, and macOS 14 when one is at hand. Use the zip that `scripts/release.sh VERSION` builds, not a debug build. Each line is something to do, then what should happen.

## Before you start

- [ ] Quit any running Splark. For a first-run pass, reset it first: Settings → General → Reset Splark (or delete `~/Library/Application Support/Splark/state.json` and the `dev.splark.Splark` Keychain items).
- [ ] Unzip the release into Applications and open it the way the README says. The setup window appears and the spark appears in the menu bar.

## Setup

- [ ] **Welcome:** the icon, "Splark" and three points. **Get started** goes to Connect Slack. The four sparks at the top show where you are.
- [ ] **Open api.slack.com/apps ↗** opens the browser. Generate a configuration token, paste it with ⌘V, and click **Connect**. You see "Creating your private Slack app…", then "Waiting for you to click Allow…", and the browser shows Slack's Allow page.
- [ ] Click **Allow**. The browser says you can close the tab; the workspace appears as "Connected" with its tile, and the field is empty.
- [ ] Paste an expired or mistyped token: the message explains, and the token stays in the field.
- [ ] Close the Allow tab without clicking: after a while you see "Slack didn't answer in time", and **Try again** reopens Allow without a new token.
- [ ] **+ Add another workspace** shows the form again. Connect a second workspace.
- [ ] **Having trouble?** shows the pasted-token fallback; **Use a setup token instead** comes back.
- [ ] **Sign in with ChatGPT** opens chatgpt.com. After signing in, the account shows with the usage note. **Continue**.
- [ ] **You're set:** both switches on. Turn off **Open at login**, then **Done**. The window closes and the spark starts catching up.

## The spark

- [ ] While catching up, the panel's second line says "Catching up… N of M conversations".
- [ ] The spark's brightness and count match the panel: solid with a count for something needing action, half-lit for questions, faint for chatter only.
- [ ] Post a DM to yourself from another account. Within seconds (Slack open) the count goes up.
- [ ] Quit Slack. New messages still arrive within a couple of minutes.
- [ ] Right-click, ⌥-click and ⌃-click each open the menu. **Refresh now** works, **Pause summaries** gets a checkmark, and **Settings…** opens Settings.

## The panel

- [ ] A click on the spark opens the panel under it, as tall as its content, on glass (macOS 26) or frosted material (macOS 14–15). A second click closes it.
- [ ] With many items, it stops at 70% of the screen and scrolls.
- [ ] Hover a row: the toolbar replaces the meta line. 👀 adds a reaction and shows it in the meta line; check that it appears in Slack.
- [ ] Click a row: the messages and a reply field. Type a reply and press Enter: it's sent (check Slack), and the row shows "replied". Esc collapses the row, and a second Esc closes the panel.
- [ ] Reply with Wi-Fi off: "Couldn't send. Try again", and the text is still there.
- [ ] Mark a row read with the ✓ circle: it goes, with "Marked as read" and **Undo** for 4 seconds. Undo brings it back and Slack still shows it unread. Without undo, Slack shows it read after the toast.
- [ ] **Just comments** expands; ✓✓ marks them all read.
- [ ] **Open in Slack** opens the right message in the Slack app and closes the panel.
- [ ] A click in another app closes the panel.
- [ ] With nothing unread: a dimmed spark and "Nothing unread in Slack."
- [ ] Switch the system between light and dark: the panel and the spark follow.

## Settings

- [ ] **Workspaces:** each shows "Connected · Synced Xm ago". The line under the list says whether Slack is open.
- [ ] **Channels…** lists your channels; search filters them. Exclude one, **Save**: its items leave the panel. Include it again: they come back.
- [ ] **+ Add workspace** opens "Add a workspace": connecting works the same way as in setup, and **Done** closes it.
- [ ] **Remove** asks first and mentions api.slack.com/apps. Removing takes the workspace's items out of the panel.
- [ ] **ChatGPT:** the account shows. The model menu lists the plan's models with the recommended one; choosing one sticks after a restart. **Pause summaries** shows "Summaries paused" in the panel. **Sign out** turns summaries off ("Summaries paused: sign in again"); **Sign in with ChatGPT** brings them back.
- [ ] **General:** Open at login on: macOS lists Splark in System Settings → General → Login Items. Show count off: the number goes, the spark stays.
- [ ] **About:** the version matches the release, and both links open.
- [ ] **Reset Splark** asks first, then the setup window opens and the panel is empty.
- [ ] ⌘W closes Settings and setup; ⌘V, ⌘C and ⌘A work in their fields.

## Restarts and updates

- [ ] Quit from the menu, then reopen: no setup, the workspaces reconnect, and the spark comes back within a minute.
- [ ] Install a newer build over it: macOS asks for Keychain access once per item. **Always Allow**, and everything works as before.
- [ ] Leave it running overnight: Slack tokens refresh (every 12 hours), and nothing asks to reconnect.
```

Create `scripts/release.sh`:

```bash
#!/usr/bin/env bash
# Builds build/Splark-VERSION.zip for GitHub Releases: the ad-hoc-signed Splark.app, zipped with ditto.
# Usage: scripts/release.sh VERSION [--check]
#   VERSION may start with "v" (a tag). It must match Support/Info.plist and SplarkInfo.swift.
#   --check stops after comparing the versions.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/release.sh VERSION [--check]}"
VERSION="${VERSION#v}"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)"
CODE_VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/SplarkKit/SplarkInfo.swift)"
if [[ "$VERSION" != "$PLIST_VERSION" || "$VERSION" != "$CODE_VERSION" ]]; then
  echo "$VERSION doesn't match the app's version: Support/Info.plist says $PLIST_VERSION, SplarkInfo.swift says $CODE_VERSION." >&2
  exit 1
fi
if [[ "${2:-}" == "--check" ]]; then
  echo "$VERSION"
  exit 0
fi
./scripts/build-app.sh release > /dev/null
codesign --verify --strict build/Splark.app
ZIP="build/Splark-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Splark.app "$ZIP"
shasum -a 256 "$ZIP"
```

Make it executable: `chmod +x scripts/release.sh`

- [ ] **Step 4: Run the tests and watch them pass**

Run: `swift test`
Expected: PASS, `✔ Test run with 358 tests`. `swift build --build-tests` prints no warnings.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml README.md Tests/SplarkKitTests/ReleaseScriptTests.swift docs/qa.md scripts/release.sh
git commit -m "Ship it: the release zip, its workflow, the README and the QA list" -m "release.sh builds the zip a v* tag publishes as a draft; the README covers
installing, what is sent where, Keychain prompts and removal."
```

- [ ] **Step 6: Build the zip**

Run: `./scripts/release.sh 0.1.0 && unzip -l build/Splark-0.1.0.zip | tail -1`
Expected: a sha256 line, then `17 files` and no `__MACOSX` entries.

---

### Task 14: Try it for real, then the PR

**Files:**
- Modify: `docs/spikes.md`, and anything the run shows is broken (each fix with a test)

**Interfaces:** none. This task runs the app on Ivan's real accounts and records what happened.

The steps need Ivan for clicks: a config token, Allow, ChatGPT sign-in and Keychain prompts. Tell him exactly what to click, one step at a time. Never read message text: ask him what he sees instead of reading the panel's content.

- [ ] **Step 1: Build and install the release zip**

Run: `./scripts/release.sh 0.1.0 && rm -rf /Applications/Splark.app && ditto -x -k build/Splark-0.1.0.zip /Applications && open /Applications/Splark.app`
Expected: the spark appears in the menu bar, and the setup window opens. A copy that wasn't downloaded isn't quarantined, so Gatekeeper doesn't ask.

- [ ] **Step 2: Go through `docs/qa.md` with Ivan**

Section by section: Setup, The spark, The panel, Settings, Restarts and updates (leave the overnight check for him). For each line, tell him what to do, and ask what he sees. Record anything that doesn't match, as one line each.

- [ ] **Step 3: Fix what the run found**

For each mismatch:
- write a test that reproduces it, watch it fail, fix it, and run `swift test`;
- for a look-and-feel problem a test can't catch, fix it, then rerun `swift run splark-dev render-ui --out /tmp/ui` and Read the changed state.

Commit each fix on its own, saying what it fixes.

- [ ] **Step 4: Record the run**

Append to `docs/spikes.md`:

```markdown

## 7. The app, live (Plan 3)

Fill in from Task 14.

- Setup on (workspaces): (how long; anything unclear or broken)
- The panel on macOS (version): (opening, height, glass, keyboard, Esc, reply, reactions, mark read and undo)
- Settings: (anything unclear or broken)
- Keychain prompts after reinstalling: (how many; Always Allow worked)
- **Decision:** (anything to change before 0.1.0 ships, or "none")
```

Then replace each parenthesis with what happened.

- [ ] **Step 5: Run everything one last time**

Run: `swift test && ./scripts/release.sh 0.1.0`
Expected: `✔ Test run with 358 tests` (more if Step 3 added tests), then the zip's sha256.

- [ ] **Step 6: Commit and push**

```bash
git add docs/spikes.md
git commit -m "Record the app's live run" -m "What setup, the panel and Settings did on real accounts."
git log -1 --format=%ae   # must print ivliag@gmail.com
git push -u origin HEAD
```

- [ ] **Step 7: Open the PR and hand off**

Use `superpowers:finishing-a-development-branch`. Ivan chose "Push and create a PR" last time. Summarise for him in five lines:
- what the app does now;
- what the live run found and fixed;
- the decisions above that he should check;
- how to release: merge, tag `v0.1.0`, review the draft release, publish;
- what's next: a Developer ID for notarisation, so the Keychain stops asking after updates.
