import AppKit

/// 계정 전용 로그인 폴더를 환경 변수로 넘겨 공식 CLI를 터미널에서 연다.
/// 그 터미널 창에서는 CLI를 끝낸 뒤에도 같은 환경이 남아서, 다시 실행해도 그 계정으로 돈다.
enum TerminalLaunch {
    static func open(_ binary: URL, environment: [String: String], title: String, scriptName: String) throws {
        let directory = UsageStore.defaultDirectory.appending(path: "launch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = directory.appending(path: "\(scriptName).command")
        try script(binary: binary, environment: environment, title: title).write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        // .command 파일은 기본으로 터미널이 연다.
        guard NSWorkspace.shared.open(file) else { throw UsageError.failed(String(localized: "터미널을 열지 못했습니다")) }
    }

    static func script(binary: URL, environment: [String: String], title: String) -> String {
        var lines = [
            "#!/bin/zsh -l",
            // 터미널 탭 제목
            "printf '\\033]0;%s\\007' \(quote(title))",
        ]
        lines += environment.sorted { $0.key < $1.key }.map { "export \($0.key)=\(quote($0.value))" }
        lines += [
            "cd ~",
            quote(binary.path),
            "exec /bin/zsh -l",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// 작은따옴표로 감싸서 셸이 아무것도 해석하지 않게 한다.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
