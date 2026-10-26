import Foundation

/// 서비스에 맞는 로그인 방법을 연다. ChatGPT·Grok은 공식 CLI의 브라우저 로그인, Claude·Cursor는 앱 안 로그인 창.
@MainActor
enum AccountLogin {
    static func start(for account: Account, store: UsageStore) {
        guard store.canUse(account.id) else { return }
        switch account.service {
        case .chatgpt: CodexLogin.start(for: account, store: store)
        case .claude, .cursor: LoginWindowController.show(for: account, store: store)
        case .grok: GrokLogin.start(for: account, store: store)
        // agy는 처음 실행할 때 브라우저로 Google 로그인을 받는다.
        case .antigravity: AccountOpen.open(account, store: store)
        // Grok Bot은 연결된 Cursor 계정 로그인을 쓴다.
        case .grokBot:
            if let cursor = store.accounts.first(where: { $0.id == account.linkedAccountID }) {
                LoginWindowController.show(for: cursor, store: store)
            }
        }
    }

    static func cancel(_ account: Account, store: UsageStore) {
        switch account.service {
        case .chatgpt: CodexLogin.cancel(account.id, store: store)
        case .grok: GrokLogin.cancel(account.id, store: store)
        case .claude, .cursor, .grokBot, .antigravity: break
        }
    }
}
