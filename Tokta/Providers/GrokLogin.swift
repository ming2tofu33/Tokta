import Foundation

/// 공식 `grok login --oauth`로 계정 전용 폴더에 로그인한다. 브라우저는 CLI가 연다.
@MainActor
enum GrokLogin {
    private static var running: (id: Account.ID, process: ChildProcess)?

    static func start(for account: Account, store: UsageStore) {
        if let running { cancel(running.id, store: store) }
        store.setLoggingIn(account.id, true)
        Task {
            do {
                let snapshot = try await signIn(account)
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
        self.running = nil
        running.process.terminate()
        store.setLoggingIn(id, false)
    }

    private static func signIn(_ account: Account) async throws -> UsageSnapshot {
        guard let binary = GrokCLI.binary else {
            throw UsageError.failed(RequiredApp.missingMessage(for: .grok))
        }
        let home = try GrokHomes.prepare(for: account.id)
        let process = ChildProcess(executable: binary, arguments: ["login", "--oauth"], environment: ["GROK_HOME": home.path])
        running = (account.id, process)
        let status = try await process.run(timeout: .seconds(300))
        guard running?.id == account.id else { throw CancellationError() }
        running = nil
        guard status == 0 else { throw UsageError.failed(String(localized: "Grok 로그인이 완료되지 않았습니다. 다시 시도하세요")) }
        var loggedIn = account
        loggedIn.usesSystemLogin = false
        return try await GrokProvider().fetchUsage(for: loggedIn)
    }
}
