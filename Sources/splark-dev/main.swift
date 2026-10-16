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
  chatgpt-probe [--model M]           list models and send a tiny structured request (--raw-models dumps /v1/models)
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
