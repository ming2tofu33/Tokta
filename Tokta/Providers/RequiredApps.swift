import Foundation

/// ChatGPT·Grok은 공식 프로그램의 로그인으로 사용량을 읽어서 그 프로그램이 설치돼 있어야 한다.
enum RequiredApp {
    struct Requirement: Equatable {
        let name: String
        /// 이름에 맞는 조사(이/가)를 붙인 형태. 예: "ChatGPT 데스크톱 앱이", "Grok CLI가"
        let subject: String
        let purpose: String
        let downloadURL: URL
    }

    static func requirement(for service: Service) -> Requirement? {
        switch service {
        case .chatgpt:
            Requirement(name: String(localized: "ChatGPT 데스크톱 앱"), subject: String(localized: "ChatGPT 데스크톱 앱이"), purpose: String(localized: "앱 안에 들어 있는 Codex로 로그인하고 사용량을 읽습니다"), downloadURL: URL(string: "https://openai.com/chatgpt/download/")!)
        case .grok:
            Requirement(name: "Grok CLI", subject: String(localized: "Grok CLI가"), purpose: String(localized: "Grok CLI로 로그인하고 사용량을 읽습니다"), downloadURL: URL(string: "https://x.ai/build")!)
        case .antigravity:
            Requirement(name: "Antigravity CLI", subject: String(localized: "Antigravity CLI가"), purpose: String(localized: "Antigravity CLI(agy)로 로그인하고 사용량을 읽습니다"), downloadURL: URL(string: "https://antigravity.google")!)
        case .claude, .cursor, .grokBot:
            nil
        }
    }

    static func isInstalled(for service: Service) -> Bool {
        switch service {
        case .chatgpt: Executables.find("codex", fallbacks: CodexProvider.bundledPaths) != nil
        case .grok: GrokCLI.binary != nil
        case .antigravity: AntigravityCLI.binary != nil
        case .claude, .cursor, .grokBot: true
        }
    }

    /// 카드에 보여줄 오류 문구.
    static func missingMessage(for service: Service) -> String {
        guard let requirement = requirement(for: service) else { return String(localized: "필요한 프로그램을 찾지 못했습니다") }
        return String(localized: "\(requirement.subject) 설치돼 있지 않습니다. 설치한 뒤 다시 시도하세요")
    }
}
