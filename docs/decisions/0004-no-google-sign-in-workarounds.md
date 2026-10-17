# ADR-0004: Do not work around Google's embedded sign-in block

- Status: Accepted
- Date: 2026-10-13

## Context

Google blocks Google-account sign-in inside embedded web views, because an app could capture the password. Users see "This browser or app may not be secure." Tokta's Claude and Cursor sign-in windows are embedded web views.

## Decision

Tokta never disguises its web view as a browser to get past this. Instead:

- **Claude:** accounts are keyed by email, so a Google-created account can sign in with "Continue with email" using the same address. When the window reaches a Google sign-in page, Tokta shows a large warning and a button to go back.
- **Cursor:** use GitHub or email sign-in.
- **Codex, Grok, Antigravity:** their CLIs sign in through the system browser, so the block does not apply. Tokta warns that the browser may already be signed in to a different account and offers to copy the sign-in link for a private window.

## Consequences

- Some users need one extra step the first time.
- Tokta warns when the same account is added twice to one service.
