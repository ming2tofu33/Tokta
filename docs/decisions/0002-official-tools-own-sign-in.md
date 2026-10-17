# ADR-0002: Let official tools own sign-in and tokens

- Status: Accepted
- Date: 2026-10-13

## Context

Several services expose usage only to their own CLI or app. Reading those tools' token files directly is easy, but refreshing a token behind the tool's back can rotate the refresh token and sign the user out of the real CLI. Reading another app's encrypted storage breaks on every update.

## Decision

When a service has an official CLI or app, Tokta asks that tool and never writes or refreshes its tokens:

- **Codex (ChatGPT):** run the official `codex app-server` and ask over JSON-RPC. Codex handles sign-in and refresh.
- **Grok:** read the Grok CLI's current access token. When it is about to expire, run `grok models` so the CLI refreshes itself, then read again.
- **Antigravity:** run `agy -p /usage --output-format json`. Tokta never sees the token.

Tokta does not read other apps' private stores (for example, the Claude desktop app or the Cursor app).

## Consequences

- Codex, Grok and Antigravity require their official app or CLI to be installed. Settings shows whether each one is installed, with a download link.
- If a CLI changes its commands or output, that service breaks until Tokta is updated.
- Tokta can find CLIs installed through version managers because it also asks the login shell for its `PATH` once (`Executables.loginShellPath`).
