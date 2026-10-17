# ADR-0007: Show Grok Bot as its own service, linked to a Cursor account

- Status: Accepted
- Date: 2026-10-15

## Context

Despite the name, the Grok Bot app is made by Anysphere (Cursor), and its weekly limit lives on the Cursor account, not on the xAI Grok subscription. It was first shown as a third bar inside the Cursor row. That hid it, and it also made a whole Cursor account look exhausted whenever Grok Bot ran out.

## Decision

- `grokBot` is a separate service. Each Grok Bot account is linked to a Cursor account (`Account.linkedAccountID`) and read with that Cursor account's session, so there is no second sign-in.
- It appears automatically the first time a Cursor account reports a Grok Bot limit, using the same name and group.
- Deleting the Grok Bot entry hides it for good. Deleting the Cursor account deletes its Grok Bot entry too.

## Consequences

- Cursor rows show only Cursor limits, and recommendations for Cursor are no longer affected by Grok Bot.
