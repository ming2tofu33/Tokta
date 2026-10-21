# Tokta

**Every AI account you pay for, in your Mac menu bar, with a tiny pixel friend who knows which one to use next.**

[한국어](README.ko.md)

<!-- TODO: hero GIF of the menu bar character (docs/images/hero.gif) -->

Tokta shows how much is left on each of your AI subscriptions — Claude, Codex (ChatGPT), Grok, Cursor and Antigravity — across as many accounts as you have. It picks the account to use right now, warns you before one runs out, and opens that account in one click.

## Features

- **Many accounts per service.** A work Claude, a personal Claude, a teammate's seat — each signs in separately and is tracked on its own.
- **"Use this now" card.** Sticks with the account you're using, and suggests a roomier account from the same service and group only when yours is running low or blocked.
- **Pixel characters.** Pick from seven 16×16 characters: a Mac window, battery, chip, mug, potion, slime or robot. Each one fills with light as your limits refill, and its face tells you how things are going. It shows up in the menu, the widgets and, if you like, the menu bar.
- **Alerts.** When a limit is running low or will run out within the hour, when its reset time arrives, and the day before a subscription renews.
- **Open in one click.** Opens the recommended account's signed-in window (Claude, Cursor) or CLI terminal (Codex, Grok).
- **Groups.** Organize accounts into your own groups, such as Work and Personal.
- **Usage history and forecasts.** See how fast each account is burning down.
- **Tokta window.** All accounts in one sortable list, today's timeline, and a monthly view of what you used and paid.
- **Subscriptions.** Track what you pay and when each plan renews.
- **Widgets and iPhone app.** Desktop widgets on the Mac, and an iPhone app and widgets synced through your own iCloud. The iPhone app isn't on the App Store yet, so you have to [build it yourself](#iphone) for now.
- **English and Korean.**

## Supported services

| Service | Multiple accounts | How Tokta reads usage | Needs |
|---|---|---|---|
| Claude | Yes | Per-account web sign-in | — |
| Codex (ChatGPT) | Yes | The Codex limit of your ChatGPT plan, via the Codex bundled with the ChatGPT desktop app | [ChatGPT desktop app](https://openai.com/chatgpt/download/) or the Codex CLI |
| Grok | Yes | Grok CLI sign-in and the xAI usage API | [Grok CLI](https://x.ai/build) |
| Cursor | Yes | Per-account cursor.com sign-in | — |
| Grok Bot | Follows your Cursor accounts | Your linked Cursor sign-in | — |
| Antigravity | One account | Antigravity CLI (`agy -p /usage`) | [Antigravity CLI](https://antigravity.google) |

None of these services offers an official usage API for consumer plans, so **any of them can break when a service changes its website or CLI**. If one breaks, please [open an issue](../../issues). [docs/services](docs/services/) explains exactly how each one is read.

## Install

### Mac

Requires **macOS 15** or later.

1. Download the latest `Tokta-x.y.z.dmg` from [Releases](../../releases). It is signed and notarized by Apple.
2. Drag Tokta into Applications and open it. Tokta lives in the menu bar and has no Dock icon.
3. Add accounts in **Settings → Accounts**.

### iPhone

The iPhone app and its widgets show what your Mac reads, synced through your own iCloud. It isn't on the App Store or TestFlight yet, so for now you need to build it yourself:

- An Apple Developer account, Xcode, and an iPhone on **iOS 18** or later.
- **Build both the Mac app and the iPhone app yourself, with the same team.** Sync uses an iCloud container that belongs to your team, so the Mac app from Releases can't talk to an iPhone app you built.
- The same Apple ID signed in to iCloud on both devices.

Steps:

1. Set up `Config/Local.xcconfig` with your team ID and bundle prefix, as described in [Build from source](#build-from-source).
2. Run `scripts/install.sh` to build and install the Mac app. iCloud sync is only enabled in Release builds, so a Debug build run from Xcode won't sync.
3. In Xcode, run the **ToktaPhone** scheme on your iPhone.

With automatic signing, Xcode registers the App IDs, App Group and iCloud container (`iCloud.<your prefix>`) the first time you build. If it doesn't, add them in the Apple Developer portal.

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
