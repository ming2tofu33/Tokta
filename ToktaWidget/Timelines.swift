import AppIntents
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let data: WidgetData?
    /// 작은 위젯에서 고른 서비스. nil이면 첫 서비스.
    var serviceID: String?
}

/// 앱이 써 둔 파일을 읽기만 한다. 앱이 새 값을 쓰면 다시 그리라고 알려주고,
/// 그렇지 않아도 15분마다 다시 그려 “몇 분 전”과 오래된 값 표시를 맞춘다.
struct UsageTimeline: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: .now, data: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: .now, data: context.isPreview ? (WidgetData.load()?.estimated(at: .now) ?? .sample) : WidgetData.load()?.estimated(at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = UsageEntry(date: .now, data: WidgetData.load()?.estimated(at: .now))
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct ServiceTimeline: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: .now, data: .sample, serviceID: "claude") }

    func snapshot(for configuration: SelectServiceIntent, in context: Context) async -> UsageEntry {
        UsageEntry(date: .now, data: context.isPreview ? (WidgetData.load()?.estimated(at: .now) ?? .sample) : WidgetData.load()?.estimated(at: .now), serviceID: configuration.service.serviceID)
    }

    func timeline(for configuration: SelectServiceIntent, in context: Context) async -> Timeline<UsageEntry> {
        let entry = UsageEntry(date: .now, data: WidgetData.load()?.estimated(at: .now), serviceID: configuration.service.serviceID)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60)))
    }
}

struct SelectServiceIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "서비스 고르기"
    static let description = IntentDescription("작은 위젯에 보여줄 서비스")

    @Parameter(title: "서비스", default: .automatic)
    var service: ServiceOption
}

enum ServiceOption: String, AppEnum {
    case automatic, claude, chatgpt, cursor, grokBot, grok, antigravity

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "서비스"
    static let caseDisplayRepresentations: [ServiceOption: DisplayRepresentation] = [
        .automatic: "메뉴 맨 위 서비스",
        .claude: "Claude",
        .chatgpt: "Codex",
        .cursor: "Cursor",
        .grokBot: "Grok Bot",
        .grok: "Grok",
        .antigravity: "Antigravity",
    ]

    var serviceID: String? { self == .automatic ? nil : rawValue }
}

extension WidgetData {
    /// 위젯 고르기 화면과 처음 놓을 때 보여주는 예시.
    static var sample: WidgetData {
        func row(_ service: String, _ name: String, _ label: String, _ remaining: Double, recommended: Bool = false) -> Row {
            let tone: BarTone = remaining > 0.5 ? .plenty : remaining > 0.2 ? .moderate : remaining > 0.05 ? .low : .critical
            let level: StatusLevel = remaining > 0.2 ? .normal : remaining > 0.05 ? .warning : .critical
            let mood: CharacterMood = level != .normal ? .squeeze : remaining > 0.5 ? .happy : .calm
            return Row(id: UUID(), serviceID: service, serviceName: name, label: label, plan: nil, remaining: remaining, level: level,
                       bars: [Bar(tone: tone, remaining: remaining)], isRecommended: recommended, problem: nil, observedAt: .now, mood: mood)
        }
        let claude = [row("claude", "Claude", String(localized: "메인"), 0.12), row("claude", "Claude", String(localized: "서브"), 0.7, recommended: true)]
        let chatgpt = [row("chatgpt", "Codex", String(localized: "개인"), 0.96, recommended: true), row("chatgpt", "Codex", String(localized: "회사"), 0.17)]
        let cursor = [row("cursor", "Cursor", "Cursor", 0.38)]
        return WidgetData(
            updatedAt: .now,
            palette: .indigo,
            sections: [Section(id: "claude", title: "Claude", rows: claude), Section(id: "chatgpt", title: "Codex", rows: chatgpt), Section(id: "cursor", title: "Cursor", rows: cursor)],
            services: [
                Service(id: "claude", name: "Claude", best: claude[1], roomyCount: 1, accountCount: 2),
                Service(id: "chatgpt", name: "Codex", best: chatgpt[0], roomyCount: 1, accountCount: 2),
                Service(id: "cursor", name: "Cursor", best: cursor[0], roomyCount: 1, accountCount: 1),
            ]
        )
    }
}
