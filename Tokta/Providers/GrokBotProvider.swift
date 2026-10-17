import Foundation

/// Grok Bot 주간 한도. Grok Bot은 Cursor 회사 앱이라 한도가 Cursor 계정에 붙어 있어서,
/// 연결된 Cursor 계정의 cursor.com 로그인(`linkedAccountID`)으로 읽는다. 따로 로그인하지 않는다.
/// Cursor 한도와 섞으면 Grok Bot을 다 썼을 때 Cursor까지 빠듯해 보여서 따로 보여준다.
struct GrokBotProvider: UsageProvider {
    func fetchUsage(for account: Account) async throws -> UsageSnapshot {
        guard let cursorID = account.linkedAccountID else {
            throw UsageError.failed(String(localized: "연결된 Cursor 계정이 없습니다"))
        }
        return try await Self.read(cursorID)
    }

    @MainActor
    static func read(_ cursorID: Account.ID) async throws -> UsageSnapshot {
        let browser = HiddenBrowser(accountID: cursorID)
        try await browser.open(URL(string: "https://cursor.com/robots.txt")!)
        let sand = try await CursorProvider.data(browser, "/api/dashboard/get-sand-usage-status", jsonBody: "{}")
        guard let window = CursorProvider.grokBotWindow(sand, now: .now) else {
            throw UsageError.failed(String(localized: "이 Cursor 계정에는 Grok Bot 한도가 없습니다"))
        }
        return UsageSnapshot(windows: [window], observedAt: .now)
    }

    static let bundleID = "com.anysphere.sand"
}
