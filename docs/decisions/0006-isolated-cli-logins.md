# ADR-0006: Isolate CLI sign-ins per account

- Status: Accepted
- Date: 2026-10-13

## Context

Codex and Grok are signed in through their CLIs, which normally store one login per machine. Tokta needs one login per account.

## Decision

- Each extra account gets its own folder under `~/Library/Application Support/Tokta/`, passed to the CLI as `CODEX_HOME` or `GROK_HOME`. Folders are created with mode 700.
- For Codex, the folder's `config.toml` sets `cli_auth_credentials_store = "file"`, so credentials stay in that folder instead of the shared keychain item.
- One account per service may use the machine's default login (`~/.codex`, `~/.grok`). Tokta never deletes the default login.
- **An account whose dedicated folder is not signed in yet never falls back to the default login.** Otherwise one account could silently show another account's numbers.
- Only one CLI sign-in runs at a time, because they share a local callback port.

## Consequences

- "Open this account" for Codex and Grok opens a terminal with that account's `CODEX_HOME` or `GROK_HOME` already set.
- Deleting an account deletes its folder.
