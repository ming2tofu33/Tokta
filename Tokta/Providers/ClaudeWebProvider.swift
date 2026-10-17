import Foundation

/// 계정별 claude.ai 로그인으로 구독 사용량을 읽는다. Claude 앱·웹·Claude Code가 모두 이 한도를 같이 쓴다.
struct ClaudeWebProvider: UsageProvider {
    static let loginURL = URL(string: "https://claude.ai/login")!

    func fetchUsage(for account: Account) async throws -> UsageSnapshot {
        try await Self.read(account.id)
    }

    @MainActor
    static func read(_ accountID: Account.ID) async throws -> UsageSnapshot {
        let browser = HiddenBrowser(accountID: accountID)
        // 같은 출처에서 fetch하기 위해 가장 가벼운 페이지를 연다.
        try await browser.open(URL(string: "https://claude.ai/robots.txt")!)

        let before = try await json(browser, "/api/account")
        guard let email = before["email_address"] as? String ?? before["email"] as? String, let userID = before["uuid"] as? String else {
            throw UsageError.needsLogin
        }
        let activeOrganization = await WebSessions.cookie(named: "lastActiveOrg", domain: "claude.ai", for: accountID)
        let organization = try ClaudeUsageParser.organization(from: try await data(browser, "/api/organizations"), activeID: activeOrganization)
        let windows = try ClaudeUsageParser.windows(from: try await data(browser, "/api/organizations/\(organization.id)/usage"))
        // 결제 정보는 있으면 쓰고, 못 읽어도 사용량은 보여준다.
        // Team의 일반 멤버는 403을 받는다. 그때는 같은 조직 관리자 계정의 값을 쓴다(UsageStore.detectedBilling).
        var billing = (try? await data(browser, "/api/organizations/\(organization.id)/subscription_details")).flatMap { ClaudeUsageParser.billing(from: $0) }
        billing?.organizationID = organization.id

        // 조회 도중 다른 계정으로 바뀌었으면 숫자를 버린다.
        let after = try await json(browser, "/api/account")
        guard after["uuid"] as? String == userID else { throw UsageError.failed(String(localized: "조회 중 로그인 계정이 바뀌었습니다. 다시 새로고침하세요")) }

        var snapshot = UsageSnapshot(windows: windows, plan: organization.plan, observedAt: .now, loginEmail: email)
        snapshot.billing = billing
        snapshot.organizationID = organization.id
        return snapshot
    }

    @MainActor
    private static func data(_ browser: HiddenBrowser, _ path: String) async throws -> Data {
        let (status, body) = try await browser.get(path)
        switch status {
        case 200:
            guard (try? JSONSerialization.jsonObject(with: Data(body.utf8))) != nil else {
                throw UsageError.failed(String(localized: "Claude 보안 확인이 필요합니다. 로그인 창을 열어주세요"))
            }
            return Data(body.utf8)
        case 401, 403: throw UsageError.needsLogin
        case 429: throw UsageError.failed(String(localized: "Claude 조회 제한입니다. 잠시 후 다시 확인하세요"))
        default: throw UsageError.failed(String(localized: "Claude 응답 오류 (HTTP \(status))"))
        }
    }

    @MainActor
    private static func json(_ browser: HiddenBrowser, _ path: String) async throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: try await data(browser, path)) as? [String: Any] else {
            throw UsageError.failed(String(localized: "Claude 계정 정보를 읽지 못했습니다"))
        }
        return object
    }
}
