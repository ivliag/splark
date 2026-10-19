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
- [ ] With nothing connected (after Reset, or setup closed early), a click on the spark brings setup to the front instead of an empty panel.
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
- [ ] Open a channel's message and click **Mute**: its items leave the panel and the count, and "Muted #channel" offers **Undo**. Undo brings them back. Settings → **Channels…** shows it ticked. A DM has no Mute.
- [ ] A click in another app closes the panel.
- [ ] With nothing unread: a dimmed spark and "Nothing unread in Slack."
- [ ] Switch the system between light and dark: the panel and the spark follow.

## Settings

- [ ] Settings opens on **General**; the tabs read About, General, Slack, OpenAI.
- [ ] **About:** the version matches the release, and both links open.
- [ ] **General:** Open at login on: macOS lists Splark in System Settings → General → Login Items. Show count off: the number goes, the spark stays.
- [ ] **Slack:** each workspace shows "Connected · Synced Xm ago". The line under the list says whether Slack is open.
- [ ] **Channels…** lists your channels; search filters them. Mute one, **Save**: its items leave the panel. Unmute it: they come back.
- [ ] **+ Add workspace** opens "Add a workspace": connecting works the same way as in setup, and **Done** closes it.
- [ ] **Remove** asks first and mentions api.slack.com/apps. Removing takes the workspace's items out of the panel.
- [ ] **OpenAI:** the account shows. The model menu lists the plan's models with the recommended one; choosing one sticks after a restart. **Pause summaries** shows "Summaries paused" in the panel. **Sign out** turns summaries off ("Summaries paused: sign in again"); **Sign in with ChatGPT** brings them back.
- [ ] **Reset Splark** asks first, then the setup window opens and the panel is empty.
- [ ] ⌘W closes Settings and setup; ⌘V, ⌘C and ⌘A work in their fields.

## Restarts and updates

- [ ] Quit from the menu, then reopen: no setup, the workspaces reconnect, and the spark comes back within a minute.
- [ ] Install a newer build over it: macOS asks for Keychain access once per item. **Always Allow**, and everything works as before.
- [ ] Leave it running overnight: Slack tokens refresh (every 12 hours), and nothing asks to reconnect.
