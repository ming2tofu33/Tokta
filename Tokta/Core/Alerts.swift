import Foundation

/// 알림을 받을 곳. 맥이 판단하고, iPhone으로 보낼 알림은 iCloud로 넘긴다.
enum AlertDestination: String, Codable, CaseIterable, Sendable {
    case iPhone, mac, both

    var onMac: Bool { self != .iPhone }
    var onPhone: Bool { self != .mac }
}

/// 알림은 세 가지: 곧 바닥나요(`lowEnabled`) · 다시 찼어요(`resetEnabled`) · 내일 결제(`renewalEnabled`).
struct AlertSettings: Codable, Equatable, Sendable {
    /// 곧 바닥나요: 기준선(`warning`) 아래로 내려가거나 이 속도면 1시간 안에 바닥날 때, 한 주기에 한 번.
    var lowEnabled = true
    /// 다시 찼어요: 기준선 아래로 내려갔던 한도의 리셋 시각에.
    var resetEnabled = true
    /// 예전 설정(소진 예측 따로 켜기). 지금은 `lowEnabled`가 같이 맡아서 쓰지 않는다.
    var forecastEnabled = true
    /// 내일 결제: 구독 결제 전날 오전 9시.
    var renewalEnabled = true
    /// 남은 비율 기준선. 알림은 첫째(가장 높은 값)만 쓰고, 둘째(5%)는 메뉴 색(빨강)에만 쓴다.
    var thresholds: [Double] = [0.2, 0.05]
    // 새로 쓰는 사람은 Mac으로 받고, iPhone 수신을 확인한 뒤 고른다(2026-10-17 기획서). 저장된 설정은 그대로.
    var destination: AlertDestination = .mac

    var warning: Double { thresholds.max() ?? 0 }
    var critical: Double { thresholds.min() ?? 0 }

    init() {}

    /// 나중에 생긴 설정은 저장 파일에 없으면 기본값을 쓴다.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AlertSettings()
        lowEnabled = try container.decodeIfPresent(Bool.self, forKey: .lowEnabled) ?? defaults.lowEnabled
        resetEnabled = try container.decodeIfPresent(Bool.self, forKey: .resetEnabled) ?? defaults.resetEnabled
        forecastEnabled = try container.decodeIfPresent(Bool.self, forKey: .forecastEnabled) ?? defaults.forecastEnabled
        renewalEnabled = try container.decodeIfPresent(Bool.self, forKey: .renewalEnabled) ?? defaults.renewalEnabled
        thresholds = try container.decodeIfPresent([Double].self, forKey: .thresholds) ?? defaults.thresholds
        destination = try container.decodeIfPresent(AlertDestination.self, forKey: .destination) ?? defaults.destination
    }
}

struct AlertMessage: Equatable, Sendable {
    var id: String
    var title: String
    var body: String
    /// 알림에 붙는 버튼. 첫 번째는 배너를 눌렀을 때도 실행한다.
    var actions: [AlertAction] = []
}

/// 알림 버튼. 누르면 `tokta://` 주소를 연다(그 계정으로 열기, Tokta 창).
struct AlertAction: Equatable, Sendable {
    var title: String
    var url: URL

    static func open(_ account: Account, title: String? = nil) -> AlertAction {
        AlertAction(title: title ?? String(localized: "\(account.displayLabel) 계정으로 열기"), url: WidgetData.openURL(for: account.id))
    }

    static var monthReport: AlertAction {
        AlertAction(title: String(localized: "이번 달 보기"), url: URL(string: "tokta://window/month")!)
    }
}

enum AlertEvent: Equatable, Sendable {
    case notify(AlertMessage)
    /// 정해진 시각에 보낼 알림. 같은 id로 다시 예약하면 이전 예약을 바꾼다.
    case schedule(AlertMessage, at: Date)
    case cancel(id: String)
}

/// 알림을 실제로 보내는 쪽. 앱에서는 macOS 알림 센터, 테스트에서는 기록용 객체.
@MainActor
protocol AlertDelivering: AnyObject {
    func handle(_ event: AlertEvent)
    func requestAuthorization() async -> Bool
}

extension StatusLevel {
    /// 알림 기준선과 같은 기준. 메뉴바 아이콘과 메뉴 막대 색이 같이 쓴다.
    init(remaining: Double, settings: AlertSettings) {
        if remaining <= settings.critical { self = .critical }
        else if remaining <= settings.warning { self = .warning }
        else { self = .normal }
    }
}

enum AlertPlanner {
    /// 새 사용량을 보고 보낼 알림을 정한다.
    /// `state`는 "계정|구간"마다 기준선 아래로 내려가 있는지(값은 기준선). 리셋 시각 값은 조회마다 조금씩 흔들려서,
    /// 남은 비율이 기준선 위로 다시 올라간 것을 보고 리셋됐다고 판단하고 기록을 지운다.
    /// `forecasted`: 이번 주기에 이미 소진 예측으로 “곧 바닥나요”를 보낸 구간. 같은 주기에 두 번 보내지 않는다.
    static func plan(
        accounts: [Account],
        snapshots: [Account.ID: UsageSnapshot],
        settings: AlertSettings,
        state: inout [String: Double],
        forecasted: Set<String> = [],
        unavailable: Set<Account.ID> = [],
        now: Date = .now
    ) -> [AlertEvent] {
        var events: [AlertEvent] = []
        var seen = Set<String>()
        for account in accounts {
            guard let snapshot = snapshots[account.id] else {
                // 아직 못 읽은 계정은 이전 기록을 그대로 둔다.
                seen.formUnion(state.keys.filter { $0.hasPrefix(account.id.uuidString) })
                continue
            }
            for window in snapshot.windows {
                let key = "\(account.id.uuidString)|\(window.id)"
                seen.insert(key)
                let level = settings.warning
                guard window.remaining <= level else {
                    if state.removeValue(forKey: key) != nil { events.append(.cancel(id: resetID(key))) }
                    continue
                }
                if state[key] == nil {
                    state[key] = level
                    if settings.lowEnabled && !forecasted.contains(key) {
                        events.append(.notify(lowMessage(key: key, level: level, account: account, window: window, accounts: accounts, snapshots: snapshots, settings: settings, unavailable: unavailable, now: now)))
                    }
                }
                if settings.resetEnabled, let resetsAt = window.resetsAt, resetsAt > now {
                    events.append(.schedule(AlertMessage(id: resetID(key), title: title(account), body: String(localized: "\(window.title) 한도 리셋 예정 시각이에요"), actions: [.open(account)]), at: resetsAt))
                }
            }
        }
        for key in state.keys where !seen.contains(key) {
            state[key] = nil
            events.append(.cancel(id: resetID(key)))
        }
        return events
    }

    static func resetID(_ key: String) -> String { "reset|\(key)" }

    /// 서비스마다 가장 여유 있는 계정을 고르고, 그중 가장 빠듯한 서비스를 기준으로 아이콘 상태를 정한다.
    static func statusLevel(accounts: [Account], snapshots: [Account.ID: UsageSnapshot], settings: AlertSettings) -> StatusLevel {
        guard let tightest = tightestRemaining(accounts: accounts, snapshots: snapshots) else { return .normal }
        return StatusLevel(remaining: tightest, settings: settings)
    }

    /// 서비스마다 가장 여유 있는 계정의 남은 비율 중 가장 작은 값. 메뉴바 아이콘 색과 숫자가 쓴다.
    static func tightestRemaining(accounts: [Account], snapshots: [Account.ID: UsageSnapshot]) -> Double? {
        Service.allCases.compactMap { service in
            accounts.filter { $0.service == service }.compactMap { snapshots[$0.id]?.bottleneck?.remaining }.max()
        }.min()
    }

    /// 이 속도면 1시간 안에 바닥나는 구간을 주기마다 한 번 알린다. `sent`에는 보낸 알림 id(주기 시작 시각 포함)를 담는다.
    static func planForecasts(
        accounts: [Account],
        snapshots: [Account.ID: UsageSnapshot],
        history: UsageHistory,
        settings: AlertSettings,
        sent: inout Set<String>,
        state: [String: Double] = [:],
        unavailable: Set<Account.ID> = [],
        now: Date = .now
    ) -> [AlertEvent] {
        // 8일이 지난 주기의 기록은 버린다.
        sent = sent.filter { id in
            guard let start = id.split(separator: "|").last.flatMap({ TimeInterval($0) }) else { return false }
            return now.timeIntervalSince1970 - start < UsageHistory.keepFor
        }
        // “곧 바닥나요” 하나로 합쳤다: 기준선 알림을 이미 보낸 구간은 예측 알림을 보내지 않는다.
        guard settings.lowEnabled else { return [] }
        var events: [AlertEvent] = []
        for account in accounts {
            guard let snapshot = snapshots[account.id], !snapshot.isStale(at: now) else { continue }
            for window in snapshot.windows {
                guard state["\(account.id.uuidString)|\(window.id)"] == nil else { continue }
                let cycle = history.currentCycle(account: account.id, window: window.id)
                guard let start = cycle.first?.t,
                      let exhausts = Forecaster.exhaustion(cycle: cycle, window: window, observedAt: snapshot.observedAt),
                      exhausts.timeIntervalSince(now) <= 3600 else { continue }
                let id = "forecast|\(UsageHistory.key(account.id, window.id))|\(Int(start.timeIntervalSince1970))"
                guard sent.insert(id).inserted else { continue }
                var body = String(localized: "\(CharacterMood.squeeze.emoticon) \(window.title) \(ForecastText.string(exhaustsAt: exhausts, now: now)) · \(percent(window.remaining)) 남음")
                let alternative = suggestion(for: account, accounts: accounts, snapshots: snapshots, settings: settings, unavailable: unavailable, now: now)
                if let alternative { body += "\n\(alternative.text)" }
                events.append(.notify(AlertMessage(id: id, title: title(account), body: body, actions: actions(for: account, alternative: alternative?.account))))
            }
        }
        return events
    }

    static func renewalID(_ account: Account.ID) -> String { "renewal|\(account.uuidString)" }

    /// 구독료를 입력한 계정마다 다음 결제 전날 오전 9시 알림을 예약한다. 끄거나 구독을 지우면 예약을 취소한다.
    /// 결제일을 아는 계정(직접 입력 또는 서비스에서 가져옴)마다 다음 결제 전날 오전 9시 알림을 예약한다.
    /// 끄거나, 결제일을 모르거나, 해지해서 끝나는 구독이면 예약을 취소한다.
    /// 같은 조직의 결제일을 여러 계정이 나눠 쓰면 알림은 조직마다 한 번만 보낸다(금액을 적은 계정을 먼저).
    static func planRenewals(accounts: [Account], detected: [Account.ID: DetectedBilling] = [:], settings: AlertSettings, now: Date = .now, calendar: Calendar = .current) -> [AlertEvent] {
        var announcedOrganizations = Set<String>()
        let ordered = accounts.filter { $0.subscription != nil } + accounts.filter { $0.subscription == nil }
        let events = ordered.map { account -> (Account.ID, AlertEvent) in
            let id = renewalID(account.id)
            guard settings.renewalEnabled,
                  var renewal = Renewal.resolve(subscription: account.subscription, detected: detected[account.id], now: now, calendar: calendar),
                  !renewal.isEnding else { return (account.id, .cancel(id: id)) }
            if renewal.isDetected, let organization = detected[account.id]?.organizationID {
                guard announcedOrganizations.insert(organization).inserted else { return (account.id, .cancel(id: id)) }
            }
            var fire = reminderTime(before: renewal.date, calendar: calendar)
            // 이번 알림 시각이 지났으면 그다음 결제를 예약한다. 서비스에서 가져온 날짜는 그다음을 모르니 건너뛴다.
            if fire <= now {
                guard let next = account.subscription?.nextRenewal(onOrAfter: calendar.date(byAdding: .day, value: 1, to: renewal.date) ?? renewal.date, calendar: calendar) else { return (account.id, .cancel(id: id)) }
                renewal.date = next
                fire = reminderTime(before: next, calendar: calendar)
            }
            var body = String(localized: "내일 결제 예정")
            if let subscription = account.subscription {
                body = String(localized: "내일 \(MoneyText.string(subscription.amount, currency: subscription.currency)) 결제 예정 (\(subscription.cycle == .monthly ? "매월" : "매년"))")
            }
            return (account.id, .schedule(AlertMessage(id: id, title: title(account), body: body, actions: [.monthReport]), at: fire))
        }
        // 원래 계정 순서대로 돌려준다.
        let byAccount = Dictionary(uniqueKeysWithValues: events)
        return accounts.compactMap { byAccount[$0.id] }
    }

    private static func reminderTime(before renewal: Date, calendar: Calendar) -> Date {
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: renewal) ?? renewal
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayBefore) ?? dayBefore
    }

    private static func lowMessage(key: String, level: Double, account: Account, window: UsageWindow, accounts: [Account], snapshots: [Account.ID: UsageSnapshot], settings: AlertSettings, unavailable: Set<Account.ID>, now: Date) -> AlertMessage {
        // 캐릭터 얼굴을 앞에: 다 썼으면 -_-, 아니면 >_<
        let face = window.remaining <= 0 ? CharacterMood.sleep : .squeeze
        var body = String(localized: "\(face.emoticon) \(window.title) \(percent(window.remaining)) 남음")
        if let resetsAt = window.resetsAt { body += " · \(ResetText.string(until: resetsAt, now: now))" }
        let alternative = suggestion(for: account, accounts: accounts, snapshots: snapshots, settings: settings, unavailable: unavailable, now: now)
        if let alternative { body += "\n\(alternative.text)" }
        return AlertMessage(id: "low|\(key)|\(Int((level * 100).rounded()))", title: title(account), body: body, actions: actions(for: account, alternative: alternative?.account))
    }

    /// 같은 서비스에 넉넉한 계정이 있으면 바꿔 쓰라고 알려준다.
    private static func suggestion(for account: Account, accounts: [Account], snapshots: [Account.ID: UsageSnapshot], settings: AlertSettings, unavailable: Set<Account.ID>, now: Date) -> (account: Account, text: String)? {
        let others = accounts.filter { $0.service == account.service && $0.id != account.id }
        guard let best = Recommendation.bestAccount(among: others, snapshots: snapshots, unavailable: unavailable, now: now),
              let remaining = snapshots[best.id]?.bottleneck?.remaining, remaining > settings.warning else { return nil }
        return (best, String(localized: "→ \(best.displayLabel) 계정은 \(percent(remaining)) 남았어요"))
    }

    /// 빠듯할 때 버튼: 넉넉한 다른 계정이 있으면 그 계정으로 열기를 먼저, 이 계정은 그다음.
    private static func actions(for account: Account, alternative: Account?) -> [AlertAction] {
        guard let alternative else { return [.open(account)] }
        return [.open(alternative), .open(account, title: String(localized: "\(account.displayLabel) 그대로 열기"))]
    }

    private static func title(_ account: Account) -> String { "\(account.service.displayName) · \(account.displayLabel)" }

    private static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}
