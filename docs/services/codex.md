# Codex (ChatGPT)

| | |
|---|---|
| Accounts | Many: the machine's default Codex login, plus one dedicated login per extra account |
| Method | Official Codex executable, `app-server` JSON-RPC over stdio |
| Requires | The ChatGPT desktop app (which bundles Codex) or the Codex CLI |
| Code | `Tokta/Providers/CodexProvider.swift`, `CodexLogin.swift`, `Executables.swift` |
| Decisions | [ADR-0002](../decisions/0002-official-tools-own-sign-in.md), [ADR-0005](../decisions/0005-services-by-subscription.md), [ADR-0006](../decisions/0006-isolated-cli-logins.md) |

## What it shows

The **Codex limit** of a ChatGPT subscription. ChatGPT's web chat limit is not exposed as a number, so this is the only measurable limit. It is displayed as "Codex". The stored service id is `chatgpt`.

| Plan | Observed limits |
|---|---|
| Pro | One weekly window (`windowDurationMins: 10080`), no 5-hour window |
| Plus and others | Not verified. A 300-minute window is displayed if it appears |

- Reset times come from `resetsAt` (Unix seconds).
- `rateLimitResetCredits.availableCount`, if present, is shown as "N limit resets left".

## How it is read

Tokta starts `codex app-server --listen stdio://` and sends line-delimited JSON-RPC. Codex owns sign-in and token refresh.

1. `initialize`, then the `initialized` notification
2. `account/read` with params `{}`. Passing `{refreshToken: false}` gets no reply.
3. `account/rateLimits/read`

The process is killed after 20 seconds. Tokta ignores `SIGPIPE`, so a crashing child cannot take the app down.

Executable lookup order: `PATH` (including the login shell's), then `~/.local/bin`, `/opt/homebrew/bin` and similar, then `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`, then `/Applications/Codex.app/...`.

```json
{"rateLimitsByLimitId": {"codex": {
  "primary": {"usedPercent": 4, "windowDurationMins": 10080, "resetsAt": 1792472315},
  "secondary": null, "planType": "pro",
  "credits": {"hasCredits": true, "balance": "..."}}},
 "rateLimitResetCredits": {"availableCount": 2, "credits": []}}
```

## Multiple accounts

| Kind | Login location |
|---|---|
| Default | `~/.codex`, shared with the Codex app and CLI. At most one per Tokta install |
| Dedicated | `~/Library/Application Support/Tokta/codex/<account-id>/`, with `cli_auth_credentials_store = "file"` |

A dedicated account that is not signed in yet never falls back to the default login.

Sign-in flow:

1. Start Codex with `CODEX_HOME` set to the account folder. It may run for up to 5 minutes.
2. Call `account/login/start` with `{type: "chatgpt"}`. Tokta opens `authUrl` only if it is `https` on an OpenAI sign-in domain.
3. Wait for the `account/login/completed` notification, then read usage immediately.

Only one sign-in runs at a time, because Codex uses a fixed local callback port.

## Verified responses

| Date | Account | Notes |
|---|---|---|
| 2026-10-13 | Pro | Format above |
| 2026-10-13 | Empty folder, not signed in | `account/read` returns `account: null`. `account/login/start` returns an `auth.openai.com` URL |

Tests: `CodexParsingTests`.
