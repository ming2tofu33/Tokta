# Cursor and Grok Bot

| | |
|---|---|
| Accounts | Many, each with its own cursor.com web session. Grok Bot entries are linked to a Cursor account |
| Method | Hidden web view + cursor.com internal JSON endpoints |
| Code | `Tokta/Providers/CursorProvider.swift`, `GrokBotProvider.swift`, `WebSessions.swift` |
| Decisions | [ADR-0003](../decisions/0003-web-sessions-per-account.md), [ADR-0007](../decisions/0007-grok-bot-separate-service.md) |

## What it shows

**Cursor**

| Limit | Response | Resets |
|---|---|---|
| Cursor models | `individualUsage.plan.autoPercentUsed` | `billingCycleEnd` |
| Other models | `individualUsage.plan.apiPercentUsed` | `billingCycleEnd` |
| Plan (only if neither above is present) | `totalPercentUsed`, or `used / limit` | `billingCycleEnd` |

- The plan name comes from `membershipType`.
- `billingCycleEnd` is also used as the renewal date. That is correct for monthly plans and may be wrong for yearly ones.
- Team and inactive plans are rejected. Only individual plans are supported.

**Grok Bot**

The Grok Bot app (bundle ID `com.anysphere.sand`) is made by Anysphere, and its limit lives on the Cursor account. It is unrelated to the xAI [Grok](grok.md) subscription.

| Limit | Response | Resets |
|---|---|---|
| Weekly | `get-sand-usage-status` → `usagePercent`, when `includedLimitZero == false` (older responses: `hasNonZeroIncludedLimit`) | `nextResetTimestampUtc` |
| Trial | Same field, during a trial with no included limit | — |

A Grok Bot entry is created automatically when a Cursor account reports a Grok Bot limit. If the Grok Bot read fails, the Cursor numbers still show.

## Sign-in

The sign-in window opens `https://cursor.com/dashboard`. Signed-out users are redirected through `/api/auth/login` to `authenticator.cursor.sh`. When the window returns to the dashboard, Tokta tries to read usage. Google sign-in is blocked in embedded web views, so use GitHub or email.

## How it is read

A hidden web view loads `https://cursor.com/robots.txt` and runs `fetch` inside it:

1. `GET /api/auth/me` returns the email. **A 204 with an empty body means signed out.**
2. `GET /api/usage-summary`
3. `POST /api/dashboard/get-sand-usage-status` with body `{}`. If this fails, reading continues.

## Verified responses

| Date | Account | Notes |
|---|---|---|
| 2026-10-13 | Personal | Cursor models, other models and Grok Bot weekly all shown |
| 2026-10-13 | Signed out (curl) | `robots.txt` 200, `/api/auth/me` 204, `/api/usage-summary` 401, `/dashboard` 307 to `/api/auth/login` |
| 2026-10-15 | Personal | Grok Bot read through the linked Cursor session |

Tests: `CursorTests`.
