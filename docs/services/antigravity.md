# Antigravity

| | |
|---|---|
| Accounts | One: the machine's `agy` sign-in |
| Method | `agy -p /usage --output-format json` |
| Requires | Antigravity CLI (`curl -fsSL https://antigravity.google/cli \| bash`, installs `~/.local/bin/agy`) |
| Code | `Tokta/Providers/AntigravityProvider.swift` |
| Decision | [ADR-0008](../decisions/0008-antigravity-instead-of-gemini.md) |

## What it shows

Google Antigravity's model limits. Since Google ended Gemini CLI access for individual tiers on 2026-06-18, this is the only Gemini limit an individual can read as a number. It is not the gemini.google.com chat limit.

Limits are shared per group:

- **Gemini**: Gemini Flash and Pro
- **Claude and GPT**: Claude Opus and Sonnet, and GPT-OSS

They are labeled "Gemini weekly" and "Claude and GPT weekly". A session window, if one appears on paid tiers, is labeled the same way. That case is not verified yet.

## Sign-in and tokens

- Run `agy` in a terminal. It signs in with Google through the system browser, so the embedded sign-in block does not apply.
- `agy` keeps its token in the macOS keychain. **Tokta never reads it.** It only asks `agy` for usage.
- In Tokta: Settings → Accounts → "Connect this Mac's sign-in" → Antigravity.

## How it is read

Tokta runs `agy -p /usage --output-format json --print-timeout 30s` from the home folder, with a 40-second limit. `/usage` does not call a model, so it uses no tokens.

Tokta does not call the running app's local `GetUserStatus` server or Google's cloud quota API. Both need port and CSRF-token discovery or another app's OAuth client.

```json
{"status": "SUCCESS", "usage": {"total_tokens": 0},
 "command": {"name": "usage", "data": {"groups": [
   {"name": "Gemini Models", "buckets": [{"id": "gemini-weekly", "window": "weekly",
     "remaining_fraction": 1, "reset_time": "2026-10-20T16:11:04Z"}]},
   {"name": "Claude and GPT models", "buckets": [{"id": "3p-weekly", "window": "weekly",
     "remaining_fraction": 1, "reset_time": "..."}]}]}}}
```

## Known risks

- Antigravity has been reported to return `remaining_fraction: 1` regardless of usage (antigravity-cli issue #387). Not yet confirmed by watching the number drop after real use.
- Multiple accounts are not supported. It is unknown whether `agy` supports separate config folders.

## Verified responses

| Date | Account | Notes |
|---|---|---|
| 2026-10-14 | Free personal, agy 1.3.4 | Format above. Two groups, each with one weekly window |

Tests: `AntigravityTests.realResponse`.
