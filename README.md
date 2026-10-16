# Splark

Slack, sorted by what needs you.

Splark is a small macOS menu-bar app. A pixel spark in the menu bar lights up when Slack needs you. Click it to see every unread conversation summarised in a line and sorted into three levels: **needs action**, **question for you** and **just comments**. Then reply, react or mark things as read without opening Slack.

> **Status: early development.** Nothing to install yet. The foundation and the Slack and ChatGPT integrations are proven ([`docs/spikes.md`](docs/spikes.md)); the engine and the panel come next. The design spec is in [`docs/superpowers/specs`](docs/superpowers/specs/2026-10-16-splark-design.md), and the interactive prototypes are in [`design/prototype`](design/prototype); open the HTML files in a browser.

## How it works

- **Slack:** Splark reads Slack through a private Slack app that you create in your own workspace during setup (paste one token, click Allow). Nothing is shared with other users, and there's no Splark server.
- **Summaries:** you sign in with your ChatGPT subscription ("Sign in with ChatGPT"). Only unread messages from conversations that changed are sent, with storage turned off.
- **Your data:** tokens live in your Mac's Keychain. Message text stays in memory.

## Development

Requirements: macOS 14+, Xcode 16 or newer (Swift 6).

```bash
swift test                          # all unit tests
./scripts/build-app.sh debug        # builds build/Splark.app (ad-hoc signed)
open build/Splark.app
swift run splark-dev                # developer commands: badge, slack-connect, slack-probe, chatgpt-login, chatgpt-probe
```

`splark-dev` keeps its tokens in the Keychain under the service `dev.splark.dev`, separate from the app. What the integration spikes found is in [`docs/spikes.md`](docs/spikes.md).

## Credits

The idea of putting Slack's Dock badge into the menu bar comes from [Doll](https://github.com/xiaogdgenuine/Doll) by xiaogdgenuine. Splark is a separate project and contains no Doll code.

## Licence

[MIT](LICENSE)
