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
