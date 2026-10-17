import Foundation

/// 서비스 하나의 사용량을 읽어오는 수집기. 서비스마다 하나씩 구현한다.
protocol UsageProvider: Sendable {
    func fetchUsage(for account: Account) async throws -> UsageSnapshot
}

struct ProviderRegistry: Sendable {
    var providers: [Service: any UsageProvider]

    func provider(for service: Service) -> (any UsageProvider)? { providers[service] }

    static let live = ProviderRegistry(providers: [
        .chatgpt: CodexProvider(),
        .claude: ClaudeWebProvider(),
        .grok: GrokProvider(),
        .grokBot: GrokBotProvider(),
        .antigravity: AntigravityProvider(),
        .cursor: CursorProvider(),
    ])
}
