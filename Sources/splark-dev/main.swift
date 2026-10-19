import Foundation
import SplarkKit

// splark-dev: developer commands that exercise SplarkKit against real accounts (spec §13 spikes).

let usage = """
usage: splark-dev <command>
  badge [--seconds N]                 watch Slack's Dock badge
  slack-connect [--manual]            copy an app configuration token (or, with --manual, a user token), then run:
                                      creates your private Slack app and connects it
  slack-reauth [--client-id ID] [--port P]  re-authorise the existing app (Allow only)
  slack-refresh                       refresh the stored token now
  slack-probe [--team T]              run the Slack spike checks against the connected workspace
  slack-muted [--team T]              check whether a user token can read which channels are muted
  slack-manifest-url                  print the manual "create from manifest" link (fallback)
  chatgpt-login                       Sign in with ChatGPT
  chatgpt-probe [--model M]           list models and send a tiny structured request
  inbox [--minutes N] [--no-text]     run the whole engine against your Slack and ChatGPT, printing the inbox
  triage-eval [--model M]             score the triage evaluation set against your ChatGPT plan
  make-icon OUT.icns                  render the app icon at every size and pack it with iconutil
  render-ui [--out DIR]               render every UI state with fixture data to PNGs (light and dark)
"""

do {
    switch args.first {
    case "badge": await badgeCommand()
    case "slack-connect": try await slackConnectCommand()
    case "slack-probe": try await slackProbeCommand()
    case "slack-muted": try await slackMutedCommand()
    case "slack-manifest-url": print(try SlackAppManifest.createFromManifestURL())
    case "slack-reauth": try await slackReauthCommand()
    case "slack-refresh": try await slackRefreshCommand()
    case "chatgpt-login": try await chatgptLoginCommand()
    case "chatgpt-probe": try await chatgptProbeCommand()
    case "inbox": try await inboxCommand()
    case "triage-eval": try await triageEvalCommand()
    case "make-icon": try makeIconCommand()
    case "render-ui": try renderUICommand()
    default: print(usage)
    }
} catch {
    fail("\(error)")
}
