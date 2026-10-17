# ADR-0003: Read Claude and Cursor through per-account web sessions

- Status: Accepted
- Date: 2026-10-13

## Context

Tokta first read Claude usage through the Claude Code CLI's keychain login. On machines that only use Claude Code inside the Claude desktop app, that login does not exist. The alternatives were signing in to the CLI separately (one account only) or reading the desktop app's encrypted storage (fragile, and another app's data).

Claude's subscription limit is shared by claude.ai, the desktop app and Claude Code, so the claude.ai account's usage *is* the Claude Code usage. Cursor has the same shape.

## Decision

- Each Claude or Cursor account gets its own WebKit data store. The user signs in once in a Tokta window.
- To read usage, Tokta loads a lightweight same-origin page (`/robots.txt`) in a hidden web view and calls the site's own JSON endpoints with `fetch` from inside the page. The request looks exactly like the site's own, so cookies and bot checks pass normally.
- If an account changes mid-read (for example, the user signed in to a different account), the result is discarded.
- Deleting an account deletes its data store.

## Consequences

- Unlimited accounts per service, with no cookie mixing.
- The same session powers "open this account": a Tokta window already signed in as that account.
- Google sign-in does not work inside these windows. See [ADR-0004](0004-no-google-sign-in-workarounds.md).
- The internal endpoints are unofficial and can change at any time. See [services](../services/).
