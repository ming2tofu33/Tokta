import AppKit

/// ChatGPT 계정마다 따로 두는 Codex 로그인 폴더(CODEX_HOME). 기본 `~/.codex`와 섞이지 않는다.
enum CodexHomes {
    static func directory(for id: Account.ID) -> URL {
        UsageStore.defaultDirectory.appending(path: "codex/\(id.uuidString)", directoryHint: .isDirectory)
    }

    static func isLoggedIn(_ home: URL) -> Bool {
        FileManager.default.fileExists(atPath: home.appending(path: "auth.json").path)
    }

    /// 로그인 정보를 키체인 대신 이 폴더의 파일에 두게 해서 계정끼리 섞이지 않게 한다. 갱신은 Codex가 맡는다.
    static func prepare(for id: Account.ID) throws -> URL {
        let home = directory(for: id)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let config = home.appending(path: "config.toml")
        if !FileManager.default.fileExists(atPath: config.path) {
            try Data("cli_auth_credentials_store = \"file\"\n".utf8).write(to: config)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        }
        return home
    }

    static func remove(for id: Account.ID) {
        try? FileManager.default.removeItem(at: directory(for: id))
    }
}

/// 공식 Codex 로그인 흐름으로 계정 전용 폴더에 ChatGPT 로그인을 만든다.
/// 브라우저에서 로그인을 마치면 Codex가 알림을 보내고, 그 계정의 사용량을 바로 읽는다.
@MainActor
enum CodexLogin {
    private static var running: (id: Account.ID, rpc: JSONLineProcess)?
    private static let allowedHosts: Set<String> = ["auth.openai.com", "auth0.openai.com", "chatgpt.com", "auth.chatgpt.com"]

    static func start(for account: Account, store: UsageStore) {
        // Codex 로그인은 같은 로컬 포트로 결과를 받아서 한 번에 하나만 진행한다.
        if let running { cancel(running.id, store: store) }
        store.setLoggingIn(account.id, true)
        Task {
            do {
                let snapshot = try await signIn(account) { store.setLoginURL($0, for: account.id) }
                store.record(snapshot, for: account.id)
            } catch is CancellationError {
            } catch {
                store.reportError(error.localizedDescription, for: account.id)
            }
            store.setLoggingIn(account.id, false)
        }
    }

    static func cancel(_ id: Account.ID, store: UsageStore) {
        guard let running, running.id == id else { return }
        running.rpc.terminate()
        self.running = nil
        store.setLoggingIn(id, false)
    }

    private static func signIn(_ account: Account, showURL: (URL?) -> Void) async throws -> UsageSnapshot {
        let home = try CodexHomes.prepare(for: account.id)
        let rpc = try CodexProvider.start(home: home, timeout: .seconds(300))
        running = (account.id, rpc)
        defer {
            rpc.terminate()
            showURL(nil)
            if running?.id == account.id { running = nil }
        }
        do {
            try await CodexProvider.initialize(rpc)
            let started = try JSONSerialization.jsonObject(with: try await rpc.request("account/login/start", params: ["type": "chatgpt"])) as? [String: Any]
            guard let link = started?["authUrl"] as? String, let url = URL(string: link),
                  url.scheme == "https", let host = url.host(), allowedHosts.contains(host) else {
                throw UsageError.failed(String(localized: "Codex 로그인 주소를 확인할 수 없습니다"))
            }
            showURL(url)
            NSWorkspace.shared.open(url)
            let completed = try await rpc.notification("account/login/completed")
            guard completed["success"] as? Bool == true else {
                throw UsageError.failed(String(localized: "ChatGPT 로그인이 완료되지 않았습니다"))
            }
        } catch JSONLineProcess.RPCError.closed {
            // 취소했거나 5분 안에 로그인을 마치지 않았다.
            if running?.id != account.id { throw CancellationError() }
            throw UsageError.failed(String(localized: "ChatGPT 로그인 시간이 지났습니다. 다시 시도하세요"))
        } catch JSONLineProcess.RPCError.failed {
            throw UsageError.failed(String(localized: "Codex 로그인을 시작하지 못했습니다. Codex를 최신 버전으로 업데이트하세요"))
        }
        rpc.terminate()
        var loggedIn = account
        loggedIn.usesSystemLogin = false
        return try await CodexProvider().fetchUsage(for: loggedIn)
    }
}
