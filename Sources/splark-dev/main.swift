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
