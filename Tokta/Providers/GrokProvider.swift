import Foundation

/// 공식 Grok CLI 로그인으로 xAI 구독 사용량(Grok 웹·앱·CLI 공통)을 읽는다.
/// 로그인 토큰은 몇 시간이면 만료되는데, 갱신은 Tokta가 직접 하지 않고 CLI 명령을 한 번 실행해 CLI가 하게 한다.
struct GrokProvider: UsageProvider {
    static let billingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!

    func fetchUsage(for account: Account) async throws -> UsageSnapshot {
        let home = account.usesSystemLogin ? GrokHomes.system : GrokHomes.directory(for: account.id)
        guard FileManager.default.fileExists(atPath: GrokHomes.authFile(in: home).path) else {
            throw account.usesSystemLogin ? UsageError.failed(String(localized: "이 Mac의 Grok CLI에 로그인돼 있지 않습니다")) : UsageError.needsLogin
        }
        var auth = try Auth.load(from: home)
        if auth.expiresSoon {
            try await GrokCLI.refreshLogin(home: home)
            auth = try Auth.load(from: home)
            guard !auth.expiresSoon else {
                throw UsageError.failed(String(localized: "Grok 로그인이 만료됐습니다. 다시 로그인하세요"))
            }
        }
        var request = URLRequest(url: Self.billingURL, timeoutInterval: 15)
        request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401, 403: throw UsageError.needsLogin
        case let status: throw UsageError.failed(String(localized: "Grok 사용량 서버 오류 (HTTP \(status))"))
        }
        return UsageSnapshot(windows: try Self.windows(from: data), observedAt: .now, loginEmail: auth.email)
    }

    /// 2026-10-13 응답: `config.currentPeriod {type, start, end}`. 사용 비율(`creditUsagePercent`)은 하나도 안 썼으면 빠진다.
    static func windows(from data: Data) throws -> [UsageWindow] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let config = root["config"] as? [String: Any] else {
            throw UsageError.failed(String(localized: "Grok 사용량 응답 형식이 바뀌었습니다"))
        }
        let period = config["currentPeriod"] as? [String: Any]
        let start = (period?["start"] as? String).flatMap(Date.lenientISO8601)
        let reset = (period?["end"] as? String ?? config["billingPeriodEnd"] as? String).flatMap(Date.lenientISO8601)

        var used = (config["creditUsagePercent"] as? NSNumber)?.doubleValue
        if used == nil, let limit = ((config["monthlyLimit"] as? [String: Any])?["val"] as? NSNumber)?.doubleValue, limit > 0 {
            used = (((config["used"] as? [String: Any])?["val"] as? NSNumber)?.doubleValue ?? 0) / limit * 100
        }
        // 공식 CLI도 통합 구독 사용자의 빠진 비율을 0으로 본다. 기간이 제대로 있을 때만 받아들인다.
        if used == nil, config["isUnifiedBillingUser"] as? Bool == true, start != nil, reset != nil {
            used = 0
        }
        guard let used, (0...100).contains(used) else {
            throw UsageError.failed(String(localized: "Grok 사용량 응답에 한도 정보가 없습니다"))
        }
        let title = period?["type"] as? String == "USAGE_PERIOD_TYPE_WEEKLY" ? String(localized: "주간") : String(localized: "구독 기간")
        return [UsageWindow(id: "period", title: title, used: used / 100, resetsAt: reset)]
    }

    struct Auth {
        let token: String
        let email: String?
        let expiresAt: Date?

        /// 5분 안에 만료되면 미리 갱신한다.
        var expiresSoon: Bool { expiresAt.map { $0 < .now.addingTimeInterval(300) } ?? false }

        static func load(from home: URL) throws -> Auth {
            guard let data = try? Data(contentsOf: GrokHomes.authFile(in: home)) else { throw UsageError.needsLogin }
            return try decode(data)
        }

        /// auth.json은 `"https://auth.x.ai::<id>"` 키 아래에 로그인 정보를 둔다.
        static func decode(_ data: Data) throws -> Auth {
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard let entry = root.first(where: { $0.key.hasPrefix("https://auth.x.ai::") && (($0.value as? [String: Any])?["key"] as? String)?.isEmpty == false })?.value as? [String: Any],
                  let token = entry["key"] as? String else {
                throw UsageError.needsLogin
            }
            if (entry["principal_type"] as? String)?.lowercased() == "team" {
                throw UsageError.failed(String(localized: "개인 Grok 계정으로 로그인하세요"))
            }
            return Auth(token: token, email: entry["email"] as? String, expiresAt: (entry["expires_at"] as? String).flatMap(Date.lenientISO8601))
        }
    }
}

/// Grok CLI 로그인 폴더(GROK_HOME). 기본은 `~/.grok`, 추가 계정은 Tokta 전용 폴더.
enum GrokHomes {
    static var system: URL {
        ProcessInfo.processInfo.environment["GROK_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".grok", directoryHint: .isDirectory)
    }

    static func directory(for id: Account.ID) -> URL {
        UsageStore.defaultDirectory.appending(path: "grok/\(id.uuidString)", directoryHint: .isDirectory)
    }

    static func authFile(in home: URL) -> URL { home.appending(path: "auth.json") }

    static func prepare(for id: Account.ID) throws -> URL {
        let home = directory(for: id)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return home
    }

    static func remove(for id: Account.ID) throws {
        let directory = directory(for: id)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}

enum GrokCLI {
    static var binary: URL? {
        Executables.find("grok", fallbacks: [GrokHomes.system.appending(path: "bin/grok").path])
    }

    /// 로그인이 필요한 가벼운 명령을 실행해 CLI가 만료된 토큰을 스스로 갱신하게 한다.
    static func refreshLogin(home: URL) async throws {
        guard let binary else { throw UsageError.failed(RequiredApp.missingMessage(for: .grok)) }
        _ = try await ChildProcess(executable: binary, arguments: ["models"], environment: ["GROK_HOME": home.path]).run(timeout: .seconds(20))
    }
}
