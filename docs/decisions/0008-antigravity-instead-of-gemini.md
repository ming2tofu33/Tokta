# ADR-0008: Read Google model limits through Antigravity, not Gemini CLI

- Status: Accepted
- Date: 2026-10-14

## Context

Tokta briefly read Gemini limits through the Gemini CLI login and the Code Assist quota API. Google ended Gemini CLI and Code Assist access for all individual tiers (free, AI Pro and AI Ultra) on 2026-06-18 and moved those users to Antigravity. The Gemini app's own chat limit is not exposed as a number.

The options for Antigravity were its CLI, the running app's local server (which needs port and CSRF-token discovery), or Google's cloud API (which needs another app's OAuth client).

## Decision

- Use `agy -p /usage --output-format json`. The `/usage` command does not call a model, so it costs no quota, and it follows [ADR-0002](0002-official-tools-own-sign-in.md).
- Name the service **Antigravity**, not Gemini, because its limits cover Gemini as well as Claude and GPT model groups. Existing Gemini accounts migrate automatically.
- One account only, because `agy` has no known per-account config folder.

## Consequences

- The Gemini CLI provider was removed. The login-shell `PATH` lookup built for it stayed.
- Antigravity has been reported to return `remaining_fraction: 1` regardless of usage. See [the Antigravity service doc](../services/antigravity.md).
