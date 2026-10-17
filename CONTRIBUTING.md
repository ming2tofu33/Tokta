# Contributing

Thanks for helping. Tokta is a personal project maintained in spare time, so replies may take a while. Small, focused changes are the easiest to review.

## Reporting a broken service

Services change their websites and CLIs without notice, so this is the most common and most useful kind of report. Use the **Service broke** issue template and include:

- The service and your plan (for example, Claude Max or Codex via ChatGPT Plus).
- The exact message shown on the account's card.
- If you can, the response shape **with every value replaced**. Never paste tokens, cookies, emails or account IDs.

[docs/services](docs/services/) explains how each service is read, which usually points at what changed.

Security problems go through [SECURITY.md](SECURITY.md), not public issues.

## Building

See [Build from source](README.md#build-from-source). You don't need an Apple Developer account to build and run the Mac app. Widgets and iPhone sync need one.

## Running tests

Many tests check Korean UI text, so run them with Korean as the test language:

```bash
xcodebuild test -project Tokta.xcodeproj -scheme Tokta -destination 'platform=macOS' -testLanguage ko -testRegion KR
```

With an English system language and no `-testLanguage ko`, the tests that check text will fail.

## Making changes

- **Read [docs/decisions](docs/decisions/) first** if your change touches sign-in, tokens, data storage or iCloud. Those decisions are deliberate. For example, Tokta never writes or refreshes another tool's tokens ([ADR-0002](docs/decisions/0002-official-tools-own-sign-in.md)), and it never works around Google's embedded sign-in block ([ADR-0004](docs/decisions/0004-no-google-sign-in-workarounds.md)).
- **UI text:** write Korean strings in code (`Text("…")`, or `String(localized: "…")` outside SwiftUI views), then run `scripts/sync-strings.sh` and fill in the English translation it reports as missing. Keep English short and plain.
- **Tests:** add or update tests next to the change. Parsers should be tested with a real response shape, values removed.
- **Commits:** one logical change per commit, with a message that says what changed and why.

### Adding a service

1. Implement `UsageProvider` in `Tokta/Providers/`.
2. Add a case to `Service` only once the provider works end to end.
3. Add parser tests with a real response shape.
4. Write `docs/services/<service>.md` using the same sections as the existing pages.

### Adding a character

1. Add a 16×16 map to `design/pixel-character-v6/sprites.py` that follows the rules at the top of that file. The face must sit inside the gauge area.
2. Run `python3 design/pixel-character-v6/sprites.py design/pixel-character-v6` and check `sheet.html`.
3. Add the same map to `Shared/PixelCharacters.swift`. `PixelCharacterTests` checks that the app's pixels match the generated PNGs.

## License

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE), the same as the rest of the project.
