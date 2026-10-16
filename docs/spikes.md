# Spike results

What the spec's §13 risks turned out to be, measured on real accounts. Plans 2 and 3 build on this file.

## 2. Badge via lsappinfo

- macOS version: 26.5.1
- Unread channel activity, no mentions: `lsappinfo info -only StatusLabel -app com.tinyspeck.slackmacgap` returned `"label"="•"` → parses as `dot` (observed 2026-10-16 09:5x)
- Everything read: `splark-dev badge` → `none` (2026-10-16 10:19)
- (After the final review, `SlackBadge.none` was renamed `.clear`; the readings below are as printed at the time.)
- DM or mention arrives: `10:46:52  count(1)`. Read it: `10:47:13  none`. Both picked up within the 2 s poll.
- macOS "Badge application icon" off (2026-10-16 15:48–15:52, run by Ivan): `lsappinfo` kept reporting Slack's badge, `count(1)` → `count(2)` → `count(3)` → `count(2)` → `count(1)` → `clear`, as messages arrived and were read. The StatusLabel is Slack's own badge, not what macOS shows in the Dock.
- Slack quit: not exercised against the real app. A unit test covers that `current()` is nil when Slack isn't running.
- **Decision:** the badge signal works for clear / dot / count on macOS 26.5.1, with macOS badges on or off, and is used as a trigger. It stays optional, as the spec says: schedule-only polling when it's unavailable, and Settings shows whether it's available. Plan 2 still lets a clear badge clear thread items only after a lit one has been seen since Slack started. That is a cheap safeguard for a badge that never lights up.

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

### Token refresh (2026-10-16, before Plan 2)

Run with `splark-dev slack-reauth` (Allow only, same app A0C9LFCEJQK, no config token) and then `splark-dev slack-refresh`, twice.

- `oauth.v2.access` with `grant_type=refresh_token`, `client_id` and `refresh_token`, and **no client secret**: **worked**. The new token passed `auth.test`.
- The refresh response is **top-level**, not under `authed_user`: `access_token`, `refresh_token`, `expires_in` (43200), `token_type`, `user_id`, `scope`, `team`. It also warns `superfluous_charset` about the `charset=utf-8` in our Content-Type; this is harmless.
- **Each refresh issues a new refresh token.** The previous refresh token was still accepted once afterwards, and using it didn't invalidate the newer one: refreshing again with the stored token worked.
- **The previous access token stays valid** right after a refresh.
- **Decision:** refresh without a client secret, so Splark never stores one. Refresh when the token is within 30 minutes of expiry, or on a `token_expired` error. Save the new token and refresh token to the Keychain before using them. A crash between refreshing and saving is recoverable, because the old refresh token still works. The user is asked to re-authorise only when the refresh itself fails with `invalid_refresh_token`.

## 4. Mention sweep

- `search.messages "<@U04KS7K15LH>"`: total 2557, results across channels, group DMs and threads. `"@ivan.liagushkin"` returned the same total.
- **Decision:** Plan 2 uses `<@USERID>`, sorted by timestamp, and only looks at results newer than the last sweep.

## 5. Internal-app rate limits

- `conversations.history` asked for 100 messages and got 100, `has_more=true`. That's not the 15-message clamp.
- 3 rapid history calls took 0.5 s, so there's no 1-per-minute clamp.
- `users.conversations`: 211 conversations in 0.3 s (2 pages).
- **Decision:** normal Tier 3 limits. The spec's schedule stands.

## 3. Sign in with ChatGPT

Run 2026-10-16 with a personal ChatGPT account.

- **Dynamic registration** (`client_id=dynamic_agent_client`):
  - It worked once `ext_agent_host_id` was a lowercase `urn:uuid:…`.
  - A bare uppercase UUID was rejected: `{"error":{"message":"Invalid authorize request","param":"ext_agent_host_id","code":"invalid_authorize_request"}}`.
- **Callback query keys:** `client_id`, `code`, `scope`, `state`. The issued `client_id` (`oaiapp_…`) arrives in the callback.
- **Granted scopes** include `chatgpt.tokens.use.direct`. The plan level (Plus or Pro) isn't reported in the callback or token response.
- **Tokens:** the access token lasts 1 hour, and a refresh token is returned.
- **`GET /v1/models`** with a plan token returns `{"models":[{"slug","visibility","supported_in_api",…}]}`, not `{"data":[{"id"}]}`.
  - Listed: `gpt-6-luna` ("Fast and affordable model for easier tasks"), `gpt-5.6-luna` and `gpt-5.6-terra`.
  - Hidden: `gpt-reserve` and `codex-auto-review`.
- **`POST /v1/responses`** with a plan token rejects a string `input` with "Input must be a list". `input` must be `[{"type":"message","role":"user","content":[{"type":"input_text","text":…}]}]`.
- **Output:**
  - With a `json_schema`, gpt-6-luna answered in 2.5 s: `{"lead":"Approve the rollback now; checkout is failing for EU cards.","level":"action"}`.
  - Without a schema it took 3.4 s and returned valid JSON, but with keys of its own choosing.
- **Decision:** Plan 2 uses `text.format` json_schema. Its default triage model is the first available of `gpt-6-luna`, then `gpt-5.6-luna`, then the first listed model. Credentials refresh before the 1-hour expiry.

## Menu-bar shell (Plan 1, Task 3)

- The human confirmed with a screenshot (2026-10-16 10:30): the bright pixel spark with "5" shows in the menu bar.
