# ADR-0018: Open source under MIT

- Status: Accepted
- Date: 2026-10-17

## Context

Selling Tokta was considered and rejected:

- The people who need it most, developers with several AI subscriptions, can build their own.
- An app that holds sign-in sessions for many services carries security responsibility that is hard to take on as a paid product.
- Usage is read through unofficial paths that break when services change.

## Decision

- Publish the source under the MIT License.
- Keep machine-specific signing out of the repository. `Config/Tokta.xcconfig` defines the bundle prefix, App Group and iCloud container for every target. Each developer sets `DEVELOPMENT_TEAM`, and optionally `TOKTA_BUNDLE_PREFIX`, in a gitignored `Config/Local.xcconfig`. Swift reads the identifiers from Info.plist (`Shared/BuildConfig.swift`).
- Service logos come from LobeHub Icons (MIT) and are used only to identify each service. They remain trademarks of their owners and are not covered by Tokta's license.
- The README states that Tokta is independent of every service it reads.

## Consequences

- Anyone can audit what Tokta does with sign-in sessions.
- Contributors can fix a broken service without waiting for a release.
