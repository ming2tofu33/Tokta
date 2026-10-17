import Foundation

/// claude.ai와 Claude Code OAuth API가 같이 쓰는 사용량 응답을 읽는다.
enum ClaudeUsageParser {
    private static let keyedWindows = [
        ("five_hour", String(localized: "5시간")),
        ("seven_day", String(localized: "주간")),
        ("seven_day_opus", String(localized: "주간 · Opus")),
        ("seven_day_sonnet", String(localized: "주간 · Sonnet")),
        ("seven_day_fable", String(localized: "주간 · Fable")),
    ]

    static func windows(from data: Data) throws -> [UsageWindow] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw UsageError.failed(String(localized: "Claude 사용량 응답 형식이 바뀌었습니다"))
        }
        var windows = keyedWindows.compactMap { key, title in
            window(id: key, title: title, from: root[key] as? [String: Any], valueKey: "utilization")
        }
        // 새 응답 형식은 `limits` 배열로 내려온다. 같은 구간이면 이쪽 값을 우선한다.
        for limit in root["limits"] as? [[String: Any]] ?? [] {
            let id: String, title: String
            switch limit["kind"] as? String {
            case "session":
                (id, title) = ("five_hour", String(localized: "5시간"))
            case "weekly_all":
                (id, title) = ("seven_day", String(localized: "주간"))
            case "weekly_scoped":
                let scope = limit["scope"] as? [String: Any], model = scope?["model"] as? [String: Any]
                guard let name = model?["display_name"] as? String, !name.isEmpty else { continue }
                let slug = name.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
                (id, title) = ("seven_day_\(slug)", String(localized: "주간 · \(name)"))
            default:
                continue
            }
            guard let parsed = window(id: id, title: title, from: limit, valueKey: limit["percent"] != nil ? "percent" : "utilization") else { continue }
            if let index = windows.firstIndex(where: { $0.id == id }) { windows[index] = parsed } else { windows.append(parsed) }
        }
        guard !windows.isEmpty else { throw UsageError.failed(String(localized: "Claude 사용량 응답에 한도 정보가 없습니다")) }
        return windows
    }

    private static func window(id: String, title: String, from object: [String: Any]?, valueKey: String) -> UsageWindow? {
        guard let percent = (object?[valueKey] as? NSNumber)?.doubleValue, (0...100).contains(percent) else { return nil }
        return UsageWindow(id: id, title: title, used: percent / 100, resetsAt: (object?["resets_at"] as? String).flatMap(Date.lenientISO8601))
    }

    /// `subscription_details`(2026-10-13 확인): `next_charge_date`("2026-11-10"), `billing_interval`, `currency`, `status`, `plan_ending_at`.
    /// 카드 정보(`payment_method`)는 읽지 않는다. 활성 구독이 아니면 nil.
    static func billing(from data: Data, calendar: Calendar = .current) -> DetectedBilling? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              ["active", "trialing", "past_due"].contains(root["status"] as? String ?? "") else { return nil }
        let day = (root["next_charge_date"] as? String).flatMap { localDay($0, calendar: calendar) }
        guard let next = day ?? (root["next_charge_at"] as? String).flatMap(Date.lenientISO8601) else { return nil }
        let cycle: Subscription.Cycle? = switch (root["billing_interval"] as? String)?.lowercased() {
        case "monthly", "month": .monthly
        case "yearly", "annual", "annually", "year": .yearly
        default: nil
        }
        let ends = (root["plan_ending_at"] as? String).flatMap { Date.lenientISO8601($0) ?? localDay($0, calendar: calendar) }
        return DetectedBilling(nextCharge: next, cycle: cycle, currency: (root["currency"] as? String)?.uppercased(), endsAt: ends)
    }

    /// "2026-11-10" 같은 날짜만 있는 값을 이 Mac 시간대의 그날 0시로 읽는다.
    private static func localDay(_ string: String, calendar: Calendar) -> Date? {
        let parts = string.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// 채팅을 쓸 수 있는 조직 중 claude.ai에서 마지막으로 연 조직을 고른다. 하나뿐이면 그 조직.
    /// 관계없는 조직을 임의로 고르지 않도록 애매하면 실패한다.
    static func organization(from data: Data, activeID: String?) throws -> (id: String, plan: String?) {
        guard let organizations = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            throw UsageError.failed(String(localized: "Claude 조직 정보를 읽지 못했습니다"))
        }
        let chat = organizations.filter { ($0["capabilities"] as? [String])?.contains("chat") == true }
        let candidates = chat.isEmpty ? organizations : chat
        let selected = candidates.first { $0["uuid"] as? String == activeID } ?? (candidates.count == 1 ? candidates[0] : nil)
        guard let selected, let id = selected["uuid"] as? String, id.range(of: #"^[\w-]+$"#, options: .regularExpression) != nil else {
            throw UsageError.failed(String(localized: "사용할 Claude 조직을 고를 수 없습니다. 로그인 창에서 조직을 한 번 열어주세요"))
        }
        let capabilities = selected["capabilities"] as? [String] ?? []
        let plan = capabilities.contains("claude_max") ? "Max" : capabilities.contains("claude_pro") ? "Pro" : nil
        return (id, plan)
    }
}
