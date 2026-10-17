# Grok

| | |
|---|---|
| Accounts | Many: the machine's default Grok CLI login, plus one dedicated login per extra account |
| Method | Grok CLI access token, then the xAI usage endpoint |
| Requires | Grok CLI (`~/.grok/bin/grok`) |
| Code | `Tokta/Providers/GrokProvider.swift`, `GrokLogin.swift` |
| Decisions | [ADR-0002](../decisions/0002-official-tools-own-sign-in.md), [ADR-0006](../decisions/0006-isolated-cli-logins.md) |

## What it shows

The unified xAI subscription limit shared by Grok web, the apps and the Grok CLI. **Grok Bot is a different product with its own limit.** See [Cursor](cursor.md).

- A weekly window (`USAGE_PERIOD_TYPE_WEEKLY`) that resets at `currentPeriod.end`.
- `creditUsagePercent` is **omitted when nothing was used this week**. For unified-billing users with a valid period, Tokta treats a missing value as 0%, as the official CLI does.
- Non-weekly periods are shown as "billing period". If `monthlyLimit` and `used` are present, their ratio is used.
- The response has no plan name.
- Team principals (`principal_type: Team`) are rejected.

## Sign-in and tokens

- Tokta reads only `key`, `email` and `expires_at` from the `https://auth.x.ai::<id>` entry in `$GROK_HOME/auth.json`.
- Tokens last a few hours. Within 5 minutes of expiry, Tokta runs `grok models`, a light command that requires sign-in, so the CLI refreshes the token itself. Then Tokta reads again. **Tokta never writes the token.**
- Not yet verified: whether `grok models` refreshes an *already expired* token. If it does not, the card says the Grok sign-in expired.

| Kind | Login location |
|---|---|
| Default | `~/.grok`, shared with the terminal `grok` |
| Dedicated | `~/Library/Application Support/Tokta/grok/<account-id>/`, created with `grok login --oauth` |

## How it is read

```
GET https://cli-chat-proxy.grok.com/v1/billing?format=credits
Authorization: Bearer <key>
x-xai-token-auth: xai-grok-cli
```

```json
{"config": {
  "currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY", "start": "...", "end": "..."},
  "onDemandCap": {"val": 0}, "onDemandUsed": {"val": 0},
  "isUnifiedBillingUser": true, "prepaidBalance": {"val": 0},
  "billingPeriodStart": "...", "billingPeriodEnd": "..."}}
```

On-demand and prepaid fields are received but not shown.

## Verified responses

| Date | Account | Notes |
|---|---|---|
| 2026-10-13 | Paid personal | Format above. Weekly window, unused that week |

Tests: `GrokTests`.
