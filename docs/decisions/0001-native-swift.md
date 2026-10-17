# ADR-0001: Build a native Swift app, not Electron

- Status: Accepted
- Date: 2026-10-13

## Context

Tokta started as an Electron widget (AI-Tracker). The first plan was to ship Electron, measure demand and rewrite later. Almost every competing Mac usage tracker is native, and an Electron menu bar app costs about 150 MB and carries a poor reputation for something that sits in the menu bar all day.

## Decision

Rewrite from scratch in Swift and SwiftUI, as a new repository. The Electron code is used only as a reference for each service's endpoints and response formats.

The name Tokta comes from **Tok**en + quo**ta**.

## Consequences

- Native WebKit gives one isolated cookie store per account (`WKWebsiteDataStore(forIdentifier:)`), which makes multiple accounts per service possible without a browser extension. See [ADR-0003](0003-web-sessions-per-account.md).
- Widgets, App Groups, CloudKit and an iPhone app became possible later with shared Swift code.
- Supported platforms are macOS 15+ and iOS 18+.
