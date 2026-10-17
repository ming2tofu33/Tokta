# ADR-0009: Recommend from a reference account, and suggest alternatives only when needed

- Status: Accepted (supersedes the first "most room wins" recommendation from 2026-10-14)
- Date: 2026-10-17

## Context

The first version of the top card always showed the account with the most room left. People with several accounts found it jumpy: the suggested account changed whenever the numbers moved, even when the account they were using was fine. Pinning an account also seemed to switch the recommendation off entirely.

## Decision

The card is built around a **reference account**, picked in this order:

1. The pinned account.
2. Within the pinned service, or else the last service opened from Tokta, the account most recently opened from Tokta.
3. The first account of that service.

The reference account does not change when numbers move. An **alternative** is suggested only when the reference account is below the warning line, will run out within the hour, or cannot be used. The alternative must:

- belong to the same service and the same group,
- be readable (no error, no stale value, already checked),
- have more than 10 percentage points more room, unless the reference account is fully blocked.

Tokta never suggests switching to a different service.

## Consequences

- The card stays put during normal use and speaks up only when it matters.
- The menu bar number and color follow the reference account's tightest limit. They show "—" when the value is missing, stale or failed.
- With a single account, the card still shows each limit with its reset time.
