# ADR-0011: Keep a short detailed history and a long cycle ledger

- Status: Accepted
- Date: 2026-10-13, ledger added 2026-10-16

## Context

A single snapshot cannot say whether an account will run out before it resets, or which subscriptions go unused.

## Decision

- **Detailed history** (`history.json`): for each account and limit, store a sample when the value moves by more than 0.5% or 10 minutes pass. Keep 8 days. A drop of more than 0.5% in used share marks a reset and starts a new cycle.
- **Forecast:** a straight line through recent usage in the current cycle (last hour for 5-hour limits, last day otherwise). It needs at least 15 minutes of data, is shown only when it predicts running out *before* the reset, and is never computed from stale values.
- **Ledger** (`ledger.json`): when a cycle ends, keep only its peak usage and whether it ran out. Keep 400 days. This powers the monthly view: subscriptions you barely use, how often limits ran out, and recurring patterns.

## Consequences

- Linear forecasts miss sudden bursts or pauses.
- Fresh installs show "collecting" until enough history exists (3 days for the monthly view).
