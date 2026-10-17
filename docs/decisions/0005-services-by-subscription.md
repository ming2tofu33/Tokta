# ADR-0005: Name services by subscription, and show Codex limits as "Codex"

- Status: Accepted
- Date: 2026-10-13, display name updated 2026-10-17

## Context

Early builds listed Claude, Claude Code, ChatGPT and Codex separately. Claude Code shares the Claude subscription limit, and Codex limits come from the ChatGPT subscription. ChatGPT's web chat limit is not exposed as a number anywhere.

## Decision

- One service per subscription. Claude Code usage is part of **Claude**.
- The ChatGPT subscription is shown as **Codex**, because the only number Tokta can read is the Codex limit. The stored identifier stays `chatgpt` for compatibility.
- A service is added to `Service` only once a working provider exists.

## Consequences

- Fewer, clearer rows, and no double counting.
- Users who never use Codex still see their ChatGPT subscription through its Codex limit, which is the closest available signal.
