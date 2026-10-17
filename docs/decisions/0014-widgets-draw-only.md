# ADR-0014: The app decides, and widgets only draw

- Status: Accepted
- Date: 2026-10-14

## Context

Widget extensions are sandboxed and short-lived. They cannot sign in to services or run CLIs.

## Decision

- Each time the app reads usage, it writes `widget.json` into the shared App Group container. Recommendations, color levels, character moods and errors are all decided in the app.
- The app reloads widget timelines only when the visible content changes. Widgets also redraw every 15 minutes to keep "N minutes ago" and staleness correct.
- Tapping a widget opens `tokta://open/<account-id>`, and the app opens that account.

## Consequences

- If the app is not running, widgets keep the last value and fade it out as it ages.
- The App Group identifier comes from `Config/Tokta.xcconfig`. See [ADR-0018](0018-open-source-mit.md).
