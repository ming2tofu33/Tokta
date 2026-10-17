# ADR-0017: Follow the system language, with Korean as the source

- Status: Accepted
- Date: 2026-10-15

## Decision

- Tokta follows the macOS or iOS system language: Korean on Korean systems, English everywhere else. There is no in-app language setting. Per-app language in System Settings works.
- The development language is Korean. Strings live in String Catalogs for the app, the widgets and the iPhone app.
- SwiftUI literals are localized automatically. Everything else uses `String(localized:)`.
- English copy is short and plain ("Use now", "Resets in 1h 11m"). Durations are abbreviated, which avoids plural forms.
- Korean particles that depend on the preceding word (은/는, 이/가) are chosen by `Josa`. English skips them.

## Consequences

- Command-line builds do not update the catalogs. Run `scripts/sync-strings.sh`, which also reports missing English strings.
- Many tests assert Korean text, so run them on a Korean system or pass `-testLanguage en` and expect those to differ.
