# Decisions

Short records of why Tokta works the way it does. Each one lists the context, the decision and its consequences. When a later decision replaces an earlier one, the earlier record says so.

| # | Decision |
|---|---|
| [0001](0001-native-swift.md) | Build a native Swift app, not Electron |
| [0002](0002-official-tools-own-sign-in.md) | Let official tools own sign-in and tokens |
| [0003](0003-web-sessions-per-account.md) | Read Claude and Cursor through per-account web sessions |
| [0004](0004-no-google-sign-in-workarounds.md) | Do not work around Google's embedded sign-in block |
| [0005](0005-services-by-subscription.md) | Name services by subscription, and show Codex limits as "Codex" |
| [0006](0006-isolated-cli-logins.md) | Isolate CLI sign-ins per account |
| [0007](0007-grok-bot-separate-service.md) | Show Grok Bot as its own service, linked to a Cursor account |
| [0008](0008-antigravity-instead-of-gemini.md) | Read Google model limits through Antigravity, not Gemini CLI |
| [0009](0009-reference-account-and-alternatives.md) | Recommend from a reference account, and suggest alternatives only when needed |
| [0010](0010-few-actionable-alerts.md) | Send three kinds of alerts, decided on the Mac |
| [0011](0011-history-and-forecasts.md) | Keep a short detailed history and a long cycle ledger |
| [0012](0012-menu-glance-window-analysis.md) | The menu is for a glance, and the Tokta window is for analysis |
| [0013](0013-pixel-character.md) | A pixel character that is also a gauge |
| [0014](0014-widgets-draw-only.md) | The app decides, and widgets only draw |
| [0015](0015-iphone-via-private-cloudkit.md) | The Mac reads, the iPhone displays, through the user's own iCloud |
| [0016](0016-subscriptions-and-renewals.md) | Track subscription cost manually, and fetch renewal dates where possible |
| [0017](0017-localization.md) | Follow the system language, with Korean as the source |
| [0018](0018-open-source-mit.md) | Open source under MIT |

## Adding a decision

Copy the format of an existing record, take the next number, and add a row above. Write it in English.
