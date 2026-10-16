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

## 1. Private Slack app with PKCE

Run 2026-10-16 against the Twain workspace (211 conversations).

- apps.manifest.create with `pkce_enabled` + `http://localhost:53682/slack/callback`: **worked** (app A0C9LFCEJQK).
- Authorize in the browser + `oauth.v2.access` with `code_verifier` and no client secret: **worked**.
- Token: **rotating**, even though the manifest says `token_rotation_enabled: false`. The user token starts `xoxe.xoxp-`, `expires_in` is 43200 (12 h), and a refresh token is returned. Slack's PKCE docs say PKCE refresh tokens expire after 30 days.
- `last_read` for DMs that were never opened is `"0000000000.000000"`, and `conversations.history` rejects it as `oldest` with `invalid_ts_oldest`.
- **Decision:** the config-token flow stays the main path. Plan 2 must:
  1. Store the refresh token, `client_id` and token expiry with each workspace, and refresh before expiry with `oauth.v2.access grant_type=refresh_token`. The first Plan 2 task verifies the refresh live. If a no-secret refresh is refused, store the user's own app `client_secret` (returned by apps.manifest.create) in the Keychain and refresh with it.
  2. Ask the user to re-authorise (Allow only, same app, no new config token) when the refresh token has expired.
  3. Treat a zero `last_read` as "nothing read". For DMs, rely on `unread_count_display`; skip the history call when it is 0.

## 4. Mention sweep

- `search.messages "<@U04KS7K15LH>"`: total 2557, results across channels, group DMs and threads. `"@ivan.liagushkin"` returned the same total.
- **Decision:** Plan 2 uses `<@USERID>`, sorted by timestamp, and only looks at results newer than the last sweep.

## 5. Internal-app rate limits

- `conversations.history` asked for 100 messages and got 100, `has_more=true`. That's not the 15-message clamp.
- 3 rapid history calls took 0.5 s, so there's no 1-per-minute clamp.
- `users.conversations`: 211 conversations in 0.3 s (2 pages).
- **Decision:** normal Tier 3 limits. The spec's schedule stands.
