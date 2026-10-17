import Foundation

/// 공식 Antigravity CLI(`agy`)에 사용량을 물어 Antigravity 한도를 읽는다.
/// 2026-06-18부터 Google이 개인 계정의 Gemini CLI·Code Assist를 끝내고 Antigravity로 옮겨서, 개인이 숫자로 볼 수 있는 Gemini 한도는 이것이다.
/// `agy -p /usage`는 모델에 묻지 않는 명령이라 한도를 쓰지 않는다. 로그인과 토큰은 agy가 키체인에 두고 관리하며 Tokta는 건드리지 않는다.
/// 이 Mac의 agy 로그인 하나만 쓴다.
struct AntigravityProvider: UsageProvider {
    func fetchUsage(for account: Account) async throws -> UsageSnapshot {
        guard let binary = AntigravityCLI.binary else { throw UsageError.failed(RequiredApp.missingMessage(for: .antigravity)) }
        let process = ChildProcess(
            executable: binary,
            arguments: ["-p", "/usage", "--output-format", "json", "--print-timeout", "30s"],
            capturesOutput: true
        )
        _ = try await process.run(timeout: .seconds(40))
        return UsageSnapshot(windows: try Self.windows(from: process.output), observedAt: .now)
    }

    /// 2026-10-14 agy 1.3.4 응답: `command.data.groups[]`(`name`) → `buckets[]`(`id`, `window`, `remaining_fraction` 0...1, `reset_time`).
    /// 무료 개인 계정은 그룹마다 주간 구간 하나. 로그인 전이거나 실패하면 `status`가 SUCCESS가 아니거나 출력이 비어 있다.
    static func windows(from data: Data) throws -> [UsageWindow] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw UsageError.failed(String(localized: "Antigravity CLI가 응답하지 않습니다. 터미널에서 agy로 로그인했는지 확인하세요"))
        }
        guard root["status"] as? String == "SUCCESS" else {
            throw UsageError.failed(String(localized: "Antigravity 사용량을 읽지 못했습니다. 터미널에서 agy로 다시 로그인하세요"))
        }
        let groups = ((root["command"] as? [String: Any])?["data"] as? [String: Any])?["groups"] as? [[String: Any]] ?? []
        let windows = groups.flatMap { group -> [UsageWindow] in
            let groupName = shortGroupName(group["name"] as? String ?? "")
            return (group["buckets"] as? [[String: Any]] ?? []).compactMap { bucket in
                guard let remaining = (bucket["remaining_fraction"] as? NSNumber)?.doubleValue else { return nil }
                return UsageWindow(
                    id: bucket["id"] as? String ?? "\(groupName)-\(bucket["window"] as? String ?? "")",
                    title: [groupName, windowName(bucket["window"] as? String, fallback: bucket["name"] as? String)].filter { !$0.isEmpty }.joined(separator: " "),
                    used: min(1, max(0, 1 - remaining)),
                    resetsAt: (bucket["reset_time"] as? String).flatMap(Date.lenientISO8601)
                )
            }
        }
        guard !windows.isEmpty else { throw UsageError.failed(String(localized: "Antigravity 사용량 응답에 한도 정보가 없습니다")) }
        return windows
    }

    /// "Gemini Models" → "Gemini", "Claude and GPT models" → "Claude·GPT".
    static func shortGroupName(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.hasPrefix("gemini") { return "Gemini" }
        if lower.contains("claude"), lower.contains("gpt") { return "Claude·GPT" }
        return name.replacingOccurrences(of: " models", with: "", options: .caseInsensitive)
    }

    static func windowName(_ window: String?, fallback: String?) -> String {
        switch window?.lowercased() {
        case "weekly": String(localized: "주간")
        case "daily": String(localized: "일일")
        case "session", "5h", "five_hour", "hourly": String(localized: "5시간")
        default: fallback ?? ""
        }
    }
}

enum AntigravityCLI {
    static var binary: URL? { Executables.find("agy") }
}
