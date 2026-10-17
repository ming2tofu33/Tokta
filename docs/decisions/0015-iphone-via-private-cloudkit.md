# ADR-0015: The Mac reads, the iPhone displays, through the user's own iCloud

- Status: Accepted
- Date: 2026-10-15, stale-value handling updated 2026-10-17

## Context

People wanted to check their limits on the phone, including when the Mac is asleep. The phone cannot run the CLIs or hold the web sessions.

## Decision

- The Mac uploads the same data the widgets use to the user's **private** CloudKit database, overwriting a single record. It uploads only when something visible changes or 10 minutes pass. No sign-in data is ever uploaded: only account names, plans, remaining percentages, reset times, recommendations and moods.
- There is no Tokta server.
- The iPhone app and widgets display that record and wake on CloudKit silent pushes.
- When a reset time has passed since the Mac's last read, the iPhone shows **"needs check"** instead of guessing a refilled percentage, and does not recommend accounts from guessed values.
- The iCloud entitlement exists only in Release builds. `CloudSync.isAvailable` checks the entitlement first, because calling CloudKit without it crashes.

## Consequences

- The iPhone can be minutes behind the Mac, and is stale while the Mac is off.
- The iPhone cannot choose which account to open, because those sessions live on the Mac.
