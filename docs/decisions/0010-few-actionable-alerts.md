# ADR-0010: Send three kinds of alerts, decided on the Mac

- Status: Accepted
- Date: 2026-10-13, simplified 2026-10-15, defaults updated 2026-10-17

## Context

Claude's 5-hour limit resets several times a day, so alerting on every reset trains people to turn alerts off. Early builds had two threshold levels, a separate forecast alert, a reset alert and a renewal alert, delivered by both the Mac and the iPhone. That was too many.

## Decision

There are three alerts:

1. **Running low.** Sent once per cycle when a limit falls below the warning line (20% by default) *or* is forecast to run out within the hour. The threshold and forecast alerts were merged into this one.
2. **Reset time reached.** Sent at the scheduled reset time, and only for limits that triggered "running low" in that cycle. It is worded as a scheduled reset, because Tokta has not re-read the value yet.
3. **Renewal tomorrow.** Sent at 9 AM the day before a subscription renews.

Rules:

- The Mac decides every alert. The user picks one destination: this Mac (default), iPhone, or both. iPhone alerts travel inside the synced data, and the iPhone only delivers them.
- Reset alerts are scheduled as local notifications, so they arrive even if Tokta is closed.
- Each account, limit and cycle alerts at most once. Sent state is persisted in `alerts.json` so restarts do not repeat alerts.
- "Running low" alerts include actions, such as opening a roomier account in the same service.
- Polling goes from every 5 minutes to every 2 minutes while any limit is below the line.
- No quiet hours. macOS Focus handles that.

## Consequences

- The 5% level is no longer an alert. It is only a color in the UI.
