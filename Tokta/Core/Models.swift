import Foundation

enum Service: String, Codable, CaseIterable, Identifiable, Sendable {
    case chatgpt
    case claude
    case grok
    case cursor
    case grokBot
    case antigravity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        // 실제로 읽는 건 Codex 한도라 화면 이름은 Codex. 저장 id(chatgpt)는 그대로.
        case .chatgpt: "Codex"
        case .claude: "Claude"
        case .grok: "Grok"
        case .cursor: "Cursor"
        case .grokBot: "Grok Bot"
        case .antigravity: "Antigravity"
        }
    }

    /// 카드를 누르면 여는 곳.
    var homeURL: URL {
        switch self {
        case .chatgpt: URL(string: "https://chatgpt.com")!
        case .claude: URL(string: "https://claude.ai/new")!
        case .grok: URL(string: "https://grok.com")!
        case .cursor: URL(string: "https://cursor.com/dashboard")!
        // Grok Bot은 앱이라 웹 주소는 한도가 붙은 Cursor 대시보드로.
        case .grokBot: URL(string: "https://cursor.com/dashboard")!
        case .antigravity: URL(string: "https://antigravity.google")!
        }
    }

    /// 서비스가 직접 보여주는 사용량 페이지.
    var usageURL: URL {
        switch self {
        case .chatgpt: URL(string: "https://chatgpt.com/codex/cloud/settings/analytics")!
        case .claude: URL(string: "https://claude.ai/settings/usage")!
        case .grok: URL(string: "https://grok.com/?_s=usage")!
        case .cursor: URL(string: "https://cursor.com/dashboard/spending")!
        case .grokBot: URL(string: "https://cursor.com/dashboard/spending")!
        // Antigravity는 사용량 페이지가 없다. 앱·CLI 안에서만 보여준다.
        case .antigravity: URL(string: "https://antigravity.google")!
        }
    }

    /// 설정의 계정 추가 목록에 넣는지. Antigravity는 이 Mac의 agy 로그인 하나만 쓰고,
    /// Grok Bot은 Cursor 계정에 딸려 저절로 생긴다.
    var supportsMultipleAccounts: Bool { self != .antigravity && self != .grokBot }

    /// 이 Mac의 CLI 로그인을 그대로 연결할 수 있는 서비스.
    var hasSystemLogin: Bool { self == .chatgpt || self == .grok || self == .antigravity }

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // 초기 버전에서 Codex로 저장한 계정은 같은 구독인 ChatGPT로 옮긴다.
        // Gemini(CLI)로 추가한 계정은 Google이 개인 계정을 옮긴 Antigravity로 옮긴다.
        let renamed = ["codex": "chatgpt", "gemini": "antigravity"][raw] ?? raw
        guard let service = Service(rawValue: renamed) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: String(localized: "지원하지 않는 서비스: \(raw)")))
        }
        self = service
    }
}

struct Account: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var service: Service
    var label: String
    var email: String?
    var groupID: AccountGroup.ID?
    /// CLI로 로그인하는 서비스(ChatGPT는 Codex, Grok은 Grok CLI)에서 이 Mac의 기본 로그인(`~/.codex`, `~/.grok`)을 쓰는지.
    /// 아니면 계정 전용 로그인 폴더를 쓴다.
    var usesSystemLogin = false
    /// 구독료와 결제일. 입력하지 않으면 nil.
    var subscription: Subscription?
    /// Grok Bot 계정이 한도를 읽는 Cursor 계정. Grok Bot은 Cursor 회사 앱이라 그 로그인을 같이 쓴다.
    var linkedAccountID: Account.ID?
    /// Cursor 계정: 딸린 Grok Bot 계정을 사용자가 지웠으면 다시 만들지 않는다.
    var hidesGrokBot = false
}

extension Account {
    /// 이름을 다 지운 채로 두면 메뉴·알림에는 "이름 없음"으로 보인다.
    var displayLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? String(localized: "이름 없음") : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case id, service, label, email, groupID, usesSystemLogin, subscription, linkedAccountID, hidesGrokBot
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        service = try container.decode(Service.self, forKey: .service)
        label = try container.decode(String.self, forKey: .label)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        groupID = try container.decodeIfPresent(AccountGroup.ID.self, forKey: .groupID)
        // 다중 계정 전에 만든 ChatGPT 계정은 기본 Codex 로그인을 쓰고 있었다.
        usesSystemLogin = try container.decodeIfPresent(Bool.self, forKey: .usesSystemLogin) ?? (service == .chatgpt)
        subscription = try container.decodeIfPresent(Subscription.self, forKey: .subscription)
        linkedAccountID = try container.decodeIfPresent(Account.ID.self, forKey: .linkedAccountID)
        hidesGrokBot = try container.decodeIfPresent(Bool.self, forKey: .hidesGrokBot) ?? false
    }
}

/// 사용자가 이름을 붙여 계정을 묶는 단위. 서비스가 달라도 같은 그룹에 넣을 수 있다.
struct AccountGroup: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
}

/// 메뉴에 보이는 묶음 하나. 그룹이 있으면 그룹별, 없으면 서비스별이다.
struct AccountSection: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let accounts: [Account]
    /// 서비스가 섞인 묶음이면 카드마다 서비스 이름을 같이 보여준다.
    let showsService: Bool
}

extension Date {
    /// `2025-11-04T04:59:59.943648+00:00`처럼 소수점 자릿수가 일정하지 않은 ISO 8601을 초 단위로 잘라서 읽는다.
    static func lenientISO8601(_ string: String) -> Date? {
        let trimmed = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}

/// 5시간 세션, 주간 한도처럼 따로 리셋되는 사용량 구간 하나.
struct UsageWindow: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var title: String
    /// 사용한 비율, 0...1
    var used: Double
    var resetsAt: Date?

    var remaining: Double { min(1, max(0, 1 - used)) }
}

struct UsageSnapshot: Codable, Hashable, Sendable {
    var windows: [UsageWindow]
    var plan: String?
    var observedAt: Date
    /// 실제로 로그인돼 있는 계정. 별칭에 적은 이메일과 맞는지 확인하는 데 쓴다.
    var loginEmail: String?
    /// 한도를 바로 초기화할 수 있는 남은 횟수. 지금은 Codex만 준다.
    var limitResetsLeft: Int?
    /// 서비스가 알려준 다음 결제일. 지금은 Claude와 Cursor만 준다.
    var billing: DetectedBilling?
    /// 이 계정이 쓰는 조직. 같은 조직 계정끼리 결제일을 나눠 쓰는 데 쓴다. 지금은 Claude만.
    var organizationID: String?
    /// Cursor: 이 계정에 Grok Bot 한도가 있는지. 있으면 Grok Bot 계정을 따로 만든다.
    var hasGrokBot: Bool?

    /// 남은 비율이 가장 적은 구간. 실제로 더 쓸 수 있는 양은 이 구간이 정한다.
    var bottleneck: UsageWindow? { windows.min { $0.remaining < $1.remaining } }

    /// 자동 갱신(5분, 빠듯하면 2분)이 몇 번 실패해야 넘는 시간. 이보다 오래된 값은 흐리게 보여준다.
    static let staleAfter: TimeInterval = 15 * 60

    func isStale(at now: Date) -> Bool { now.timeIntervalSince(observedAt) > Self.staleAfter }
}

enum UsageError: LocalizedError, Equatable, Sendable {
    case needsLogin
    case notSupported
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .needsLogin: String(localized: "로그인이 필요합니다")
        case .notSupported: String(localized: "아직 지원하지 않는 서비스입니다")
        case .failed(let message): message
        }
    }
}
