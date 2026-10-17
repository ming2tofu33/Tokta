import Foundation

/// 계정별 cursor.com 로그인으로 Cursor 플랜 한도를 읽는다.
/// Grok Bot(`/Applications/Grok Bot.app`, com.anysphere.sand)은 Cursor가 만든 앱이고 한도도 Cursor 계정에 붙어 있다.
/// Grok Bot 한도는 따로 보여주려고 `GrokBotProvider`가 같은 로그인으로 읽는다. 여기서는 있는지만 알려준다.
struct CursorProvider: UsageProvider {
    static let loginURL = URL(string: "https://cursor.com/dashboard")!

    func fetchUsage(for account: Account) async throws -> UsageSnapshot {
        try await Self.read(account.id)
    }

    @MainActor
    static func read(_ accountID: Account.ID) async throws -> UsageSnapshot {
        let browser = HiddenBrowser(accountID: accountID)
        try await browser.open(URL(string: "https://cursor.com/robots.txt")!)
        let me = try object(try await data(browser, "/api/auth/me"))
        guard let email = me["email"] as? String else { throw UsageError.needsLogin }
        let summary = try await data(browser, "/api/usage-summary")
        // Grok Bot이 없는 계정도 있어서 이 조회가 실패해도 Cursor 숫자는 보여준다.
        let sand = try? await data(browser, "/api/dashboard/get-sand-usage-status", jsonBody: "{}")
        let usage = try usage(summary: summary)
        var snapshot = UsageSnapshot(windows: usage.windows, plan: usage.plan, observedAt: .now, loginEmail: email)
        snapshot.billing = billing(summary: summary)
        snapshot.hasGrokBot = sand.map { grokBotWindow($0, now: .now) != nil }
        return snapshot
    }

    /// AI-Tracker `electron/providers/local.js`의 `parseCursor`·`parseGrokBot` 해석을 옮겼다.
    static func usage(summary: Data) throws -> (windows: [UsageWindow], plan: String?) {
        let root = try object(summary)
        guard let plan = (root["individualUsage"] as? [String: Any])?["plan"] as? [String: Any], plan["enabled"] as? Bool != false else {
            throw UsageError.failed(String(localized: "개인 Cursor 플랜 한도를 확인할 수 없습니다"))
        }
        let reset = date(root["billingCycleEnd"])
        var windows = [
            window("cursor_models", String(localized: "Cursor 모델"), plan["autoPercentUsed"], reset),
            window("other_models", String(localized: "기타 모델"), plan["apiPercentUsed"], reset),
        ].compactMap { $0 }
        if windows.isEmpty {
            var total = (plan["totalPercentUsed"] as? NSNumber)?.doubleValue
            if total == nil, let used = (plan["used"] as? NSNumber)?.doubleValue, let limit = (plan["limit"] as? NSNumber)?.doubleValue, limit > 0 {
                total = used / limit * 100
            }
            if let plan = window("plan", String(localized: "플랜"), total.map { $0 as NSNumber }, reset) { windows.append(plan) }
        }
        guard !windows.isEmpty else { throw UsageError.failed(String(localized: "Cursor 사용량 응답에 한도 정보가 없습니다")) }
        return (windows, (root["membershipType"] as? String)?.capitalized)
    }

    /// 사용 주기 끝(`billingCycleEnd`)을 다음 결제일로 본다. 월 구독 기준이고, 연 구독이면 결제일과 다를 수 있다.
    static func billing(summary: Data) -> DetectedBilling? {
        guard let root = try? object(summary), let end = date(root["billingCycleEnd"]) else { return nil }
        return DetectedBilling(nextCharge: end)
    }

    /// 포함 한도가 있으면 주간, 없으면 체험 기간일 때만 보여준다.
    static func grokBotWindow(_ data: Data, now: Date) -> UsageWindow? {
        guard let status = try? object(data) else { return nil }
        let included = status["includedLimitZero"] as? Bool == false
            || (status["includedLimitZero"] == nil && status["hasNonZeroIncludedLimit"] as? Bool == true)
        let trial = !included && (date(status["sandTrialExpiresAt"]).map { $0 > now } ?? false)
        guard included || trial else { return nil }
        return window("grok_bot", trial ? String(localized: "체험") : String(localized: "주간"), status["usagePercent"], trial ? nil : date(status["nextResetTimestampUtc"]))
    }

    static func window(_ id: String, _ title: String, _ percent: Any?, _ reset: Date?) -> UsageWindow? {
        guard let value = (percent as? NSNumber)?.doubleValue, (0...100).contains(value) else { return nil }
        return UsageWindow(id: id, title: title, used: value / 100, resetsAt: reset)
    }

    /// ISO 문자열, 초·밀리초 숫자(문자열 포함)를 모두 받는다.
    static func date(_ value: Any?) -> Date? {
        if let string = value as? String {
            if let date = Date.lenientISO8601(string) { return date }
            guard let number = Double(string) else { return nil }
            return date(number as NSNumber)
        }
        guard let number = (value as? NSNumber)?.doubleValue, number > 0 else { return nil }
        return Date(timeIntervalSince1970: number > 1e12 ? number / 1000 : number)
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw UsageError.failed(String(localized: "Cursor 응답 형식이 바뀌었습니다"))
        }
        return object
    }

    @MainActor
    static func data(_ browser: HiddenBrowser, _ path: String, jsonBody: String? = nil) async throws -> Data {
        let (status, body) = try await browser.get(path, jsonBody: jsonBody)
        switch status {
        case 200: return Data(body.utf8)
        // 로그인 전 `/api/auth/me`는 401이 아니라 빈 204를 준다(2026-10-13 확인).
        case 204, 401, 403: throw UsageError.needsLogin
        case 429: throw UsageError.failed(String(localized: "Cursor 조회 제한입니다. 잠시 후 다시 확인하세요"))
        default: throw UsageError.failed(String(localized: "Cursor 응답 오류 (HTTP \(status))"))
        }
    }
}
