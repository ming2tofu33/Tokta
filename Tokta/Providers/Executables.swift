import Foundation

enum Executables {
    /// GUI 앱은 셸의 PATH를 물려받지 않으므로 CLI가 흔히 설치되는 위치를 직접 찾는다.
    static var searchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // mise·asdf로 설치한 Node의 CLI(npm -g)는 shims 폴더에 생긴다.
        let common = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.volta/bin",
                      "\(home)/.local/share/mise/shims", "\(home)/.asdf/shims", "/usr/bin", "/bin"]
        // 그 밖의 위치(npm prefix를 바꾼 경우 등)는 사용자 로그인 셸의 PATH에서 찾는다. 터미널에서 실행되면 Tokta도 찾는다.
        return common + loginShellPath.filter { !common.contains($0) }
    }

    /// 사용자 로그인 셸이 쓰는 PATH. 앱이 켜진 뒤 처음 필요할 때 한 번만 묻는다.
    static let loginShellPath: [String] = {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "printf %s \"$PATH\""]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        // 셸 설정이 멈춰도 앱이 기다리지 않게 2초까지만.
        let deadline = Date.now.addingTimeInterval(2)
        while process.isRunning, Date.now < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { process.terminate(); return [] }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return parsePath(text)
    }()

    static func parsePath(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") && seen.insert($0).inserted }
    }

    /// npm으로 설치한 CLI가 node를 찾을 수 있도록 PATH를 넓힌 환경.
    static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = (searchPaths + [environment["PATH"] ?? ""]).joined(separator: ":")
        return environment
    }

    static func find(_ name: String, fallbacks: [String] = []) -> URL? {
        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return ((pathDirectories + searchPaths).map { "\($0)/\(name)" } + fallbacks)
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }
}

/// 끝날 때까지 기다리는 자식 프로세스. 시간이 지나거나 `terminate()`하면 끈다.
/// 출력은 버리고, `capturesOutput`이면 표준 출력을 임시 파일에 받아 `output`으로 준다(파이프가 차서 멈추는 일이 없게).
final class ChildProcess: @unchecked Sendable {
    private let process = Process()
    private let outputFile: URL?

    var output: Data { outputFile.flatMap { try? Data(contentsOf: $0) } ?? Data() }

    init(executable: URL, arguments: [String], environment: [String: String] = [:], capturesOutput: Bool = false) {
        outputFile = capturesOutput ? FileManager.default.temporaryDirectory.appending(path: "tokta-\(UUID().uuidString).out") : nil
        process.executableURL = executable
        process.arguments = arguments
        process.environment = Executables.environment.merging(environment) { $1 }
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        if let outputFile, FileManager.default.createFile(atPath: outputFile.path, contents: nil),
           let handle = try? FileHandle(forWritingTo: outputFile) {
            process.standardOutput = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
        }
    }

    deinit {
        if let outputFile { try? FileManager.default.removeItem(at: outputFile) }
    }

    /// 종료 코드를 돌려준다.
    func run(timeout: Duration) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.terminate()
            }
        }
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}

/// 줄 단위 JSON-RPC로 대화하는 자식 프로세스. 시간 안에 끝나지 않으면 강제로 종료한다.
final class JSONLineProcess: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private var lines: AsyncLineSequence<FileHandle.AsyncBytes>.AsyncIterator
    private var nextID = 0

    init(executable: URL, arguments: [String], environment: [String: String] = [:], timeout: Duration = .seconds(20)) throws {
        // 상대 프로세스가 먼저 죽었을 때 쓰기 때문에 앱이 같이 죽지 않게 한다.
        signal(SIGPIPE, SIG_IGN)
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = Executables.environment.merging(environment) { $1 }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        lines = output.fileHandleForReading.bytes.lines.makeAsyncIterator()
        try process.run()
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.terminate()
        }
    }

    deinit { terminate() }

    /// 요청을 보내고 같은 id의 응답 `result`를 JSON으로 돌려준다. 그 사이 알림은 무시한다.
    func request(_ method: String, params: [String: Any] = [:]) async throws -> Data {
        nextID += 1
        let id = nextID
        try send(["id": id, "method": method, "params": params])
        while let line = try await lines.next() {
            guard let message = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  message["id"] as? Int == id else { continue }
            if message["error"] != nil { throw RPCError.failed(method) }
            return try JSONSerialization.data(withJSONObject: message["result"] ?? NSNull(), options: .fragmentsAllowed)
        }
        throw RPCError.closed
    }

    /// 요청 없이 들어오는 알림 중 `method`가 일치하는 첫 알림의 `params`를 기다린다.
    func notification(_ method: String) async throws -> [String: Any] {
        while let line = try await lines.next() {
            guard let message = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  message["method"] as? String == method else { continue }
            return message["params"] as? [String: Any] ?? [:]
        }
        throw RPCError.closed
    }

    func notify(_ method: String) throws {
        try send(["method": method])
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    private func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    enum RPCError: Error {
        case failed(String)
        case closed
    }
}
