# Claude

| | |
|---|---|
| Accounts | Many, each with its own claude.ai web session |
| Method | Hidden web view + claude.ai internal JSON endpoints |
| Code | `Tokta/Providers/ClaudeWebProvider.swift`, `ClaudeUsageParser.swift`, `WebSessions.swift`, `Tokta/UI/LoginWindow.swift` |
| Decision | [ADR-0003](../decisions/0003-web-sessions-per-account.md) |

## What it shows

The Claude subscription limit. claude.ai, the desktop app and Claude Code share it, so Claude Code usage is included.

| Limit | Response key |
|---|---|
| 5-hour session | `five_hour` or `limits[].kind = session` |
| Weekly | `seven_day` or `limits[].kind = weekly_all` |
| Weekly, per model | `seven_day_opus`, `seven_day_sonnet`, ... or `limits[].kind = weekly_scoped`. Depends on plan |

- The plan shows **Max** if the organization has the `claude_max` capability, or **Pro** for `claude_pro`.
- Reset times come from `resets_at`. Its fractional seconds vary in length, so Tokta truncates to whole seconds.

## Sign-in

- Each account has its own `WKWebsiteDataStore(forIdentifier:)`. Deleting the account deletes the store.
- The sign-in window opens `https://claude.ai/login` in that store. After each navigation, and every 4 seconds, Tokta tries to read usage, and closes the window on success.
- Google sign-in is blocked in embedded web views. Use "Continue with email" with the same address. See [ADR-0004](../decisions/0004-no-google-sign-in-workarounds.md).

## How it is read

A hidden web view loads `https://claude.ai/robots.txt`, the lightest same-origin page, and runs `fetch` inside it:

1. `GET /api/account` returns the email and uuid.
2. `GET /api/organizations` returns the organizations. Tokta picks the chat-capable one matching the `lastActiveOrg` cookie, or the only one. If the choice is ambiguous, it fails rather than guessing.
3. `GET /api/organizations/{id}/usage`
4. `GET /api/organizations/{id}/subscription_details` returns the renewal date. If this fails, reading continues.
5. `GET /api/account` again. If the account changed during the read, the result is discarded.

Errors: 401 or 403 means sign-in needed, 429 means rate limited, and a non-JSON response means a security check is needed.

## Verified responses

| Date | Account | Notes |
|---|---|---|
| 2026-10-13 | Personal and Max | Both the keyed format and the `limits` array format are parsed |
| 2026-10-13 | Five accounts in one Team organization | Only `owner` and `primary_owner` can read `subscription_details`. `user` members get 403 `permission_error`, so they reuse an owner's date |
| 2026-10-13 | Two owner accounts | `subscription_details` has `next_charge_date`, `billing_interval`, `currency`, `status` and `plan_ending_at`. Payment method fields are never read |

Tests: `ClaudeParsingTests`.
