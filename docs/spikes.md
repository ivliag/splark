# Spike results

What the spec's §13 risks turned out to be, measured on real accounts. Plans 2 and 3 build on this file.

## 2. Badge via lsappinfo

- macOS version: 26.5.1
- Unread channel activity, no mentions: `lsappinfo info -only StatusLabel -app com.tinyspeck.slackmacgap` returned `"label"="•"` → parses as `dot` (observed 2026-10-16 09:5x)
- Everything read: `splark-dev badge` → `none` (2026-10-16 10:19)
- DM or mention arrives: pending (human checkpoint)
- macOS "Badge application icon" off: pending (human checkpoint)
- Slack quit: pending (human checkpoint)
- **Decision:** pending the three checks above
