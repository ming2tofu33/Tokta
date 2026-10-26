import Foundation

/// ChatGPT 구독의 Codex 한도를 공식 Codex CLI의 `app-server` RPC로 읽는다. 로그인과 토큰 갱신은 Codex가 맡는다.
/// ChatGPT 웹은 일반 채팅 한도를 숫자로 내주지 않아서 구독에서 숫자로 볼 수 있는 한도는 이것뿐이다.
struct CodexProvider: UsageProvider {
    static let bundledPaths = [
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
        "/Applications/Codex.app/Contents/Resources/codex",
    ]

    func fetchUsage(for account: Account) async throws -> UsageSnapshot {
        // 전용 로그인을 쓰는 계정이 아직 로그인 전이면 기본 로그인으로 대신 읽지 않는다.
        let home = account.usesSystemLogin ? nil : CodexHomes.directory(for: account.id)
        if let home, !CodexHomes.isLoggedIn(home) { throw UsageError.needsLogin }
        let rpc = try Self.start(home: home)
        defer { rpc.terminate() }
        do {
            try await Self.initialize(rpc)
            let login = try JSONDecoder().decode(AccountResponse.self, from: try await rpc.request("account/read"))
            guard let user = login.account, user.type == "chatgpt" else {
                throw UsageError.failed(String(localized: "Codex에 ChatGPT 계정으로 로그인하세요"))
            }
            let limits = try await rpc.request("account/rateLimits/read")
            var snapshot = UsageSnapshot(windows: try Self.windows(from: limits), plan: user.planType?.capitalized, observedAt: .now, loginEmail: user.email)
            snapshot.limitResetsLeft = Self.limitResetsLeft(from: limits)
            rpc.terminate()
            try await rpc.waitForExit()
            return snapshot
        } catch {
            rpc.terminate()
            try await rpc.waitForExit()
            guard let error = error as? JSONLineProcess.RPCError else { throw error }
            switch error {
            case .closed: throw UsageError.failed(String(localized: "Codex가 응답하지 않습니다. 버전과 로그인 상태를 확인하세요"))
            case .failed(let method): throw UsageError.failed(String(localized: "Codex 조회에 실패했습니다 (\(method))"))
            }
        }
    }

    /// `home`이 nil이면 기본 `~/.codex` 로그인을 쓴다.
    static func start(home: URL?, timeout: Duration = .seconds(20)) throws -> JSONLineProcess {
        guard let binary = Executables.find("codex", fallbacks: bundledPaths) else {
            throw UsageError.failed(RequiredApp.missingMessage(for: .chatgpt))
        }
        return try JSONLineProcess(
            executable: binary,
            arguments: ["app-server", "--listen", "stdio://"],
            environment: home.map { ["CODEX_HOME": $0.path] } ?? [:],
            timeout: timeout
        )
    }

    static func initialize(_ rpc: JSONLineProcess) async throws {
        _ = try await rpc.request("initialize", params: ["clientInfo": ["name": "tokta", "version": "0.1.0"], "capabilities": [String: Any]()])
        try rpc.notify("initialized")
    }

    static func windows(from data: Data) throws -> [UsageWindow] {
        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: data)
        guard let limits = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits else {
            throw UsageError.failed(String(localized: "Codex 한도 정보가 응답에 없습니다"))
        }
        let windows = [limits.primary, limits.secondary].compactMap { $0 }.map { window in
            UsageWindow(
                id: window.windowDurationMins.map { "\($0)m" } ?? "window",
                title: title(minutes: window.windowDurationMins),
                used: window.usedPercent / 100,
                resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: $0) }
            )
        }
        guard !windows.isEmpty else { throw UsageError.failed(String(localized: "Codex 한도 정보가 응답에 없습니다")) }
        return windows
    }

    /// 한도를 바로 초기화할 수 있는 남은 횟수. 없거나 형식이 달라도 한도 표시는 막지 않는다.
    static func limitResetsLeft(from data: Data) -> Int? {
        (try? JSONDecoder().decode(RateLimitsResponse.self, from: data))?.rateLimitResetCredits?.availableCount
    }

    private static func title(minutes: Int?) -> String {
        switch minutes {
        case 300: String(localized: "Codex 5시간")
        case 10080: String(localized: "Codex 주간")
        case let minutes? where minutes % 1440 == 0: String(localized: "Codex \(minutes / 1440)일")
        case let minutes? where minutes % 60 == 0: String(localized: "Codex \(minutes / 60)시간")
        case let minutes?: String(localized: "Codex \(minutes)분")
        case nil: "Codex"
        }
    }

    private struct AccountResponse: Decodable {
        struct User: Decodable {
            let type: String
            let email: String?
            let planType: String?
        }
        let account: User?
    }

    private struct RateLimitsResponse: Decodable {
        struct Limits: Decodable {
            let primary: Window?
            let secondary: Window?
        }
        struct Window: Decodable {
            let usedPercent: Double
            let windowDurationMins: Int?
            let resetsAt: TimeInterval?
        }
        struct ResetCredits: Decodable {
            let availableCount: Int?
        }
        let rateLimits: Limits?
        let rateLimitsByLimitId: [String: Limits]?
        let rateLimitResetCredits: ResetCredits?
    }
}
