# Services

How Tokta reads each service. **None of these paths is an official public API**, so any of them can break when a service changes its website or CLI.

| Service | Accounts | How usage is read | Code |
|---|---|---|---|
| [Claude](claude.md) | Many | Per-account claude.ai web session | `ClaudeWebProvider.swift` |
| [Codex (ChatGPT)](codex.md) | Many | Official `codex app-server` JSON-RPC | `CodexProvider.swift` |
| [Grok](grok.md) | Many | Grok CLI sign-in + xAI usage API | `GrokProvider.swift` |
| [Cursor and Grok Bot](cursor.md) | Many | Per-account cursor.com web session | `CursorProvider.swift`, `GrokBotProvider.swift` |
| [Antigravity](antigravity.md) | One | `agy -p /usage` | `AntigravityProvider.swift` |

Code paths are relative to `Tokta/Providers/`.

## When a service breaks

1. Open an issue with the service, your plan, and the exact error shown on the card.
2. If you can, capture the response shape with the values removed. Never paste tokens, cookies or emails.
3. Update the service's parser and its tests. Real response shapes live in `ToktaTests`.
4. Add a row to the service's **Verified responses** table.

## Adding a service

Implement `UsageProvider` (`Tokta/Providers/UsageProvider.swift`), add a case to `Service` only once the provider works, and write a page here using the same sections: what it shows, limits, sign-in, how it is read, verified responses and known risks.
