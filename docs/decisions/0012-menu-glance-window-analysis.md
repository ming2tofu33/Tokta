# ADR-0012: The menu is for a glance, and the Tokta window is for analysis

- Status: Accepted
- Date: 2026-10-16

## Context

A redesign moved a summary sentence, rings, service icons and trend lines into the menu. In use, it became harder to see at a glance what was left.

## Decision

- The **menu** shows remaining limits: the top card plus one row per account, with a bar for each limit. Analysis is removed from it.
- The **Tokta window** (⌘O) holds everything else: all accounts with sorting and details, today's timeline, the monthly view, and first-run setup.
- The menu keeps a few links: the Tokta window, this month's subscription total, and a warning mark when an account needs attention.

## Consequences

- A new install with no accounts opens the Tokta window for first-run setup. Setup moves to the next step only after the first successful read.
