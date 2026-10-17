# Tokta

**Every AI account you pay for, in your Mac menu bar, with a tiny pixel friend who knows which one to use next.**

[한국어](README.ko.md)

<!-- TODO: hero GIF of the menu bar character (docs/images/hero.gif) -->

Tokta shows how much is left on each of your AI subscriptions — Claude, Codex (ChatGPT), Grok, Cursor and Antigravity — across as many accounts as you have. It picks the account to use right now, warns you before one runs out, and opens that account in one click.

## Features

- **Many accounts per service.** A work Claude, a personal Claude, a teammate's seat — each signs in separately and is tracked on its own.
- **"Use this now" card.** Compares every account's tightest limit and recommends the one with the most room.
- **Pixel character.** A 16×16 little Mac window in your menu bar. Its screen fills with light as your limits refill, and its face tells you how things are going.
- **Alerts.** Running low, about to run out within the hour, and back after a reset.
- **Open in one click.** Opens the recommended account's signed-in window (Claude, Cursor) or CLI terminal (Codex, Grok).
- **Groups.** Organize accounts into your own groups, such as Work and Personal.
- **Usage history and forecasts.** See how fast each account is burning down.
- **Subscriptions.** Track what you pay and when each plan renews.
- **Widgets and iPhone app.** Desktop widgets on the Mac, and an iPhone app and widgets synced through your own iCloud.
- **English and Korean.**

## Supported services

| Service | Multiple accounts | How Tokta reads usage | Needs |
|---|---|---|---|
| Claude | Yes | Per-account web sign-in | — |
| Codex (ChatGPT) | Yes | The Codex limit of your ChatGPT plan, via the Codex bundled with the ChatGPT desktop app | [ChatGPT desktop app](https://openai.com/chatgpt/download/) |
| Grok | Yes | Grok CLI sign-in and the xAI usage API | [Grok CLI](https://x.ai/build) |
| Cursor | Yes | Per-account cursor.com sign-in | — |
| Grok Bot | Follows your Cursor accounts | Your linked Cursor sign-in | — |
| Antigravity | One account | Antigravity CLI (`agy -p /usage`) | [Antigravity CLI](https://antigravity.google) |

None of these services offers an official usage API for consumer plans, so **any of them can break when a service changes its website or CLI**. If one breaks, please [open an issue](../../issues). [docs/services](docs/services/) explains exactly how each one is read.

## Install

Requires **macOS 15** or later. The iPhone app requires **iOS 18**.

1. Download the latest `Tokta-x.y.z.dmg` from [Releases](../../releases).
2. Drag Tokta into Applications and open it. Tokta lives in the menu bar and has no Dock icon.
3. Add accounts in **Settings → Accounts**.

## Where your data lives

Tokta has no server.

- **Sign-ins** stay on your Mac. Each account's web session is kept in its own separate WebKit store. Codex, Grok and Antigravity use the sign-in of their official apps or CLIs.
- **Usage numbers and settings** are stored locally on your Mac.
- **iCloud sync** (for the iPhone app) uploads only account names, plans, remaining percentages and reset times to your own private iCloud database. Sign-in data is never uploaded.

Removing an account also deletes its sign-in cookies and cache.

## Build from source

Developed with Xcode 27.

```bash
git clone https://github.com/ming2tofu33/Tokta.git
cd Tokta
cp Config/Local.example.xcconfig Config/Local.xcconfig
```

Edit `Config/Local.xcconfig`:

```
DEVELOPMENT_TEAM = ABCDE12345          // your Apple Developer team ID
TOKTA_BUNDLE_PREFIX = com.example.tokta // an identifier prefix you own
```

Then open `Tokta.xcodeproj` and run the **Tokta** scheme.

No Apple Developer account? Skip `Local.xcconfig` and just run the scheme. The Mac app builds and runs with local signing. Widgets and iPhone sync need a team ID. The App Group, iCloud container and bundle IDs for every target are derived from these two values in `Config/Tokta.xcconfig`.

`scripts/install.sh` builds a Release copy and installs it into `/Applications`. `scripts/release.sh` signs it with Developer ID, notarizes it and makes a DMG.

## Contributing

Tokta is a personal project maintained in spare time, so replies may take a while. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to report a broken service, run the tests and add a service or character. Report security problems privately as described in [SECURITY.md](SECURITY.md).

Issues and pull requests are welcome, especially:

- **A service broke.** Include the service, your plan and the exact error shown on the card.
- **A new service.** Providers live in `Tokta/Providers/`, and each one implements `UsageProvider`. See [docs/services](docs/services/README.md#adding-a-service).

[docs/decisions](docs/decisions/) records why Tokta works the way it does. Read it before changing how sign-in or data storage works.

## Disclaimer

Tokta is an independent project. It is not affiliated with, endorsed by or sponsored by Anthropic, OpenAI, xAI, Anysphere (Cursor) or Google. Tokta reads usage through unofficial paths that may stop working at any time. Make sure your use complies with each service's terms.

The service logos in `Tokta/Assets.xcassets` are trademarks of their respective owners and are not covered by the MIT License.

## License

[MIT](LICENSE) © 2026 Domin Kim
