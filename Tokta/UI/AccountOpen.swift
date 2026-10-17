import AppKit

/// 계정을 “그 계정으로” 연다. Tokta가 계정마다 따로 들고 있는 로그인을 그대로 쓴다.
/// Claude·Cursor는 그 계정이 로그인된 Tokta 창, ChatGPT·Grok은 그 계정 로그인 폴더로 CLI를 띄운 터미널.
@MainActor
enum AccountOpen {
    /// `label`을 주면 "회사 계정으로 열기"처럼 계정 이름을 넣는다.
    static func title(for service: Service, label: String? = nil) -> String {
        let who = label.map { String(localized: "\($0) 계정으로") } ?? String(localized: "이 계정으로")
        return switch service {
        case .claude, .cursor: String(localized: "\(who) 열기")
        case .chatgpt: String(localized: "\(who) Codex 열기")
        case .grok: String(localized: "\(who) Grok CLI 열기")
        case .antigravity: String(localized: "Antigravity CLI 열기")
        case .grokBot: String(localized: "Grok Bot 열기")
        }
    }

    static func help(for service: Service) -> String {
        service == .claude || service == .cursor
            ? String(localized: "이 계정으로 로그인된 창을 Tokta에서 엽니다. 브라우저 로그인은 바꾸지 않아요.")
            : String(localized: "이 계정 로그인으로 터미널에서 실행합니다.")
    }

    static func open(_ account: Account, store: UsageStore) {
        store.noteOpened(account)
        do {
            switch account.service {
            case .claude, .cursor:
                AccountWindowController.show(for: account, store: store)
            case .chatgpt:
                guard let binary = Executables.find("codex", fallbacks: CodexProvider.bundledPaths) else {
                    throw UsageError.failed(RequiredApp.missingMessage(for: .chatgpt))
                }
                let environment = account.usesSystemLogin ? [:] : ["CODEX_HOME": CodexHomes.directory(for: account.id).path]
                try TerminalLaunch.open(binary, environment: environment, title: "Codex · \(account.displayLabel)", scriptName: account.id.uuidString)
            case .grok:
                guard let binary = GrokCLI.binary else { throw UsageError.failed(RequiredApp.missingMessage(for: .grok)) }
                let environment = account.usesSystemLogin ? [:] : ["GROK_HOME": GrokHomes.directory(for: account.id).path]
                try TerminalLaunch.open(binary, environment: environment, title: "Grok · \(account.displayLabel)", scriptName: account.id.uuidString)
            case .antigravity:
                guard let binary = AntigravityCLI.binary else { throw UsageError.failed(RequiredApp.missingMessage(for: .antigravity)) }
                try TerminalLaunch.open(binary, environment: [:], title: "Antigravity CLI", scriptName: account.id.uuidString)
            case .grokBot:
                // Grok Bot 앱을 연다. 앱 안의 로그인은 Tokta가 고를 수 없다. 앱이 없으면 한도가 붙은 Cursor 대시보드.
                if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: GrokBotProvider.bundleID) {
                    NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
                } else {
                    NSWorkspace.shared.open(account.service.homeURL)
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "\(account.displayLabel) 계정을 열지 못했습니다")
            alert.informativeText = error.localizedDescription
            NSApp.activate()
            alert.runModal()
        }
    }
}
