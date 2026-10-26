import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    private(set) var accounts: [Account]
    private(set) var groups: [AccountGroup]
    private(set) var snapshots: [Account.ID: UsageSnapshot] = [:]
    private(set) var errors: [Account.ID: String] = [:]
    /// 브라우저 로그인을 기다리는 ChatGPT 계정.
    private(set) var loggingIn: Set<Account.ID> = []
    /// 진행 중인 ChatGPT 로그인 주소. 시크릿 창에서 다른 계정으로 로그인할 수 있게 복사해 준다.
    private(set) var loginURLs: [Account.ID: URL] = [:]
    private(set) var isRefreshing = false
    private(set) var deleting: Set<Account.ID> = []
    private var deletionFailures: Set<Account.ID> = []
    @ObservationIgnored private var reads: [Account.ID: Task<UsageSnapshot, any Error>] = [:]
    @ObservationIgnored private let removeCredentials: @MainActor (Account) async throws -> Void

    func canUse(_ id: Account.ID) -> Bool {
        accounts.contains { $0.id == id } && !deleting.contains(id) && !deletionFailures.contains(id)
    }
    private(set) var alertSettings = AlertSettings()
    private(set) var lastRefresh: Date?
    /// 계정 × 구간별 사용 기록. 추이 그래프와 소진 예측에 쓴다.
    private(set) var history = UsageHistory()
    /// 주기별 최고 사용 비율과 바닥난 순간. 한 달 넘게 남겨 Tokta 창 “이번 달”에 쓴다.
    private(set) var ledger = UsageLedger()

    @ObservationIgnored private let registry: ProviderRegistry
    @ObservationIgnored private let accountsURL: URL
    @ObservationIgnored private let groupsURL: URL
    @ObservationIgnored private let alertsURL: URL
    @ObservationIgnored private let historyURL: URL
    @ObservationIgnored private let ledgerURL: URL
    @ObservationIgnored private var historyChanged = false
    /// 이미 보낸 소진 예측 알림 id. 주기마다 한 번만 보낸다.
    @ObservationIgnored private var forecastSent: Set<String> = []
    /// iPhone으로 넘길 알림. 예약은 id마다 하나(취소되면 지운다), 바로 보낸 알림은 최근 2시간만.
    @ObservationIgnored private var scheduledAlerts: [String: WidgetData.RelayedAlert] = [:]
    @ObservationIgnored private var recentAlerts: [WidgetData.RelayedAlert] = []
    @ObservationIgnored private let notifier: (any AlertDelivering)?
    /// 계정|구간마다 이미 알린 가장 낮은 기준선. 앱을 다시 켜도 같은 알림을 반복하지 않게 저장한다.
    @ObservationIgnored private var alertState: [String: Double] = [:]
    @ObservationIgnored private var autoRefreshTask: Task<Void, Never>?
    /// 사용량이나 계정이 바뀐 뒤 부른다. 앱이 위젯 파일을 새로 쓰는 데 쓴다.
    @ObservationIgnored var onChange: (() -> Void)?

    nonisolated static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Tokta", directoryHint: .isDirectory)
    }

    init(registry: ProviderRegistry = .live, directory: URL = UsageStore.defaultDirectory, notifier: (any AlertDelivering)? = nil, removeCredentials: @escaping @MainActor (Account) async throws -> Void = UsageStore.deleteCredentials) {
        self.removeCredentials = removeCredentials
        self.registry = registry
        self.notifier = notifier
        alertsURL = directory.appending(path: "alerts.json")
        historyURL = directory.appending(path: "history.json")
        let history = (try? JSONDecoder().decode(UsageHistory.self, from: Data(contentsOf: historyURL))) ?? UsageHistory()
        self.history = history
        ledgerURL = directory.appending(path: "ledger.json")
        ledger = (try? JSONDecoder().decode(UsageLedger.self, from: Data(contentsOf: ledgerURL))) ?? UsageLedger.seeded(from: history)
        accountsURL = directory.appending(path: "accounts.json")
        groupsURL = directory.appending(path: "groups.json")
        accounts = Self.load(from: accountsURL)
        groups = (try? JSONDecoder().decode([AccountGroup].self, from: Data(contentsOf: groupsURL))) ?? []
        if let stored = try? JSONDecoder().decode(StoredAlerts.self, from: Data(contentsOf: alertsURL)) {
            alertSettings = stored.settings
            alertState = stored.state
            forecastSent = Set(stored.forecastSent ?? [])
        }
    }

    /// 이 구간의 지금 주기 사용 기록.
    func cycle(for accountID: Account.ID, window: UsageWindow) -> [UsageSample] {
        history.currentCycle(account: accountID, window: window.id)
    }

    var tightestRemaining: Double? {
        AlertPlanner.tightestRemaining(accounts: accounts, snapshots: snapshots)
    }

    var statusLevel: StatusLevel {
        AlertPlanner.statusLevel(accounts: accounts, snapshots: snapshots, settings: alertSettings)
    }

    /// 기준선 아래로 내려간 구간이 하나라도 있으면 더 자주 조회한다.
    var hasLowWindow: Bool {
        accounts.contains { snapshots[$0.id]?.bottleneck.map { $0.remaining <= alertSettings.warning } ?? false }
    }

    func updateAlertSettings(_ settings: AlertSettings) {
        if !settings.resetEnabled {
            for key in alertState.keys { deliver([.cancel(id: AlertPlanner.resetID(key))]) }
        }
        // 맥에서 받지 않게 바꾸면 맥에 예약해 둔 알림을 지운다.
        if alertSettings.destination.onMac && !settings.destination.onMac {
            for id in scheduledAlerts.keys { notifier?.handle(.cancel(id: id)) }
        }
        alertSettings = settings
        evaluateAlerts()
        saveAlerts()
        if settings.destination.onMac && (settings.lowEnabled || settings.resetEnabled || settings.renewalEnabled) {
            Task { _ = await notifier?.requestAuthorization() }
        }
    }

    /// 받을 곳(맥·iPhone)으로 테스트 알림을 보낸다.
    func sendTestAlert() {
        deliver([.notify(AlertMessage(id: "test|\(Int(Date.now.timeIntervalSince1970))", title: "Tokta", body: String(localized: "알림이 이렇게 보입니다")))])
        onChange?()
    }

    /// Tokta 창 “이번 달”.
    func monthReport(now: Date = .now) -> MonthReport {
        MonthReport.make(accounts: accounts, ledger: ledger, renewal: { [self] in renewal(for: $0, now: now) }, now: now)
    }

    /// 위젯 데이터에 실어 iPhone으로 보낼 알림.
    var phoneAlerts: WidgetData.AlertRelay {
        WidgetData.AlertRelay(
            toPhone: alertSettings.destination.onPhone,
            scheduled: scheduledAlerts.values.sorted { $0.date < $1.date },
            recent: recentAlerts
        )
    }

    /// 알림을 받을 곳으로 보낸다. 맥에서 받으면 알림 센터로, iPhone으로는 기록해 두었다가 위젯 데이터로 넘긴다.
    private func deliver(_ events: [AlertEvent], now: Date = .now) {
        for event in events {
            switch event {
            case .notify(let message):
                recentAlerts.append(.init(id: message.id, title: message.title, body: message.body, date: now))
            case .schedule(let message, let date):
                scheduledAlerts[message.id] = .init(id: message.id, title: message.title, body: message.body, date: date)
            case .cancel(let id):
                scheduledAlerts[id] = nil
            }
            // 취소는 받을 곳과 상관없이 맥에도 보낸다(예전에 맥에 예약해 둔 것을 지우게).
            if case .cancel = event { notifier?.handle(event) } else if alertSettings.destination.onMac { notifier?.handle(event) }
        }
        scheduledAlerts = scheduledAlerts.filter { $0.value.date > now }
        recentAlerts.removeAll { now.timeIntervalSince($0.date) > 2 * 3600 }
    }

    /// 이번 주기에 소진 예측으로 이미 “곧 바닥나요”를 보낸 구간(`계정|구간`).
    private var forecastedKeys: Set<String> {
        Set(forecastSent.compactMap { id -> String? in
            let parts = id.split(separator: "|").map(String.init)
            guard parts.count == 4, let account = UUID(uuidString: parts[1]), let start = Int(parts[3]),
                  let cycleStart = history.currentCycle(account: account, window: parts[2]).first?.t,
                  Int(cycleStart.timeIntervalSince1970) == start else { return nil }
            return "\(parts[1])|\(parts[2])"
        })
    }

    /// 그룹을 하나라도 쓰면 그룹 순서대로, 아니면 서비스별로 묶는다. 묶음 안에서는 사용자가 정한 계정 순서를 따른다. 그룹에 안 넣은 계정은 맨 뒤 "그룹 없음"으로 간다.
    var sections: [AccountSection] {
        let grouped = groups.compactMap { group -> AccountSection? in
            let members = accounts.filter { $0.groupID == group.id }
            let name = group.name.trimmingCharacters(in: .whitespaces)
            return members.isEmpty ? nil : AccountSection(id: group.id.uuidString, title: name.isEmpty ? String(localized: "이름 없는 그룹") : name, accounts: members, showsService: true)
        }
        let groupIDs = Set(groups.map(\.id))
        let ungrouped = accounts.filter { $0.groupID.map { !groupIDs.contains($0) } ?? true }
        guard !grouped.isEmpty else {
            return Service.allCases.compactMap { service in
                let members = ungrouped.filter { $0.service == service }
                return members.isEmpty ? nil : AccountSection(id: service.rawValue, title: service.displayName, accounts: members, showsService: false)
            }
        }
        return ungrouped.isEmpty ? grouped : grouped + [AccountSection(id: "ungrouped", title: String(localized: "그룹 없음"), accounts: ungrouped, showsService: true)]
    }

    /// 계정이 둘 이상인 서비스마다 지금 쓰기 가장 좋은 계정. 그룹과 관계없이 서비스 전체에서 고른다.
    var recommendedAccountIDs: Set<Account.ID> {
        Set(Service.allCases.compactMap { service in
            let candidates = accounts(for: service)
            return candidates.count > 1 ? Recommendation.bestAccount(among: candidates, snapshots: snapshots, unavailable: unavailableAccountIDs)?.id : nil
        })
    }

    /// 같은 서비스의 다른 계정 중 지금 쓰기 가장 좋은 계정. 계정 창의 “바꾸기”가 쓴다.
    func bestAlternative(to account: Account) -> Account? {
        let others = accounts(for: account.service).filter { $0.id != account.id }
        return Recommendation.bestAccount(among: others, snapshots: snapshots, unavailable: unavailableAccountIDs)
    }

    /// 마지막으로 “그 계정으로 열기”를 한 서비스. 메뉴 맨 위 카드가 이 서비스를 크게 보여준다.
    var lastOpenedService: Service? = UserDefaults.standard.string(forKey: UsageStore.lastOpenedServiceKey).flatMap { Service(rawValue: $0) } {
        didSet { UserDefaults.standard.set(lastOpenedService?.rawValue, forKey: Self.lastOpenedServiceKey) }
    }

    nonisolated static let lastOpenedServiceKey = "lastOpenedService"

    /// 서비스마다 Tokta로 마지막으로 연 계정. 카드의 “최근 연 계정”(기준 계정)이 된다.
    var lastOpenedAccounts: [Service: Account.ID] = UsageStore.loadLastOpenedAccounts() {
        didSet {
            UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: lastOpenedAccounts.map { ($0.key.rawValue, $0.value.uuidString) }), forKey: Self.lastOpenedAccountsKey)
        }
    }

    nonisolated static let lastOpenedAccountsKey = "lastOpenedAccounts"

    private static func loadLastOpenedAccounts() -> [Service: Account.ID] {
        let raw = UserDefaults.standard.dictionary(forKey: lastOpenedAccountsKey) as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            guard let service = Service(rawValue: key), let id = UUID(uuidString: value) else { return nil }
            return (service, id)
        })
    }

    /// 그 계정으로 열었다. 다음부터 카드의 기준 계정이 된다.
    func noteOpened(_ account: Account) {
        lastOpenedService = account.service
        lastOpenedAccounts[account.service] = account.id
    }

    /// 메뉴바 숫자와 색: 기준 계정의 가장 빠듯한 구간. 여러 서비스를 섞지 않는다.
    /// 값이 없거나 오래됐거나 오류가 붙었으면 nil(숫자 대신 “—”).
    var menuBarRemaining: Double? {
        guard let pick = nowPick(), let snapshot = snapshots[pick.primary.id],
              !snapshot.isStale(at: .now), errors[pick.primary.id] == nil else { return nil }
        return snapshot.bottleneck?.remaining
    }

    var menuBarLevel: StatusLevel {
        menuBarRemaining.map { StatusLevel(remaining: $0, settings: alertSettings) } ?? .normal
    }

    /// 맨 위 카드에 늘 크게 보여줄 서비스나 계정. nil이면 마지막으로 연 서비스.
    var cardPin: CardPin? = UserDefaults.standard.string(forKey: UsageStore.cardPinKey).flatMap { CardPin(storageValue: $0) } {
        didSet { UserDefaults.standard.set(cardPin?.storageValue, forKey: Self.cardPinKey) }
    }

    nonisolated static let cardPinKey = "cardPin"

    /// 메뉴 맨 위 “지금 쓸 계정” 카드.
    func nowPick(now: Date = .now) -> NowPick? {
        NowPick.make(
            accounts: accounts,
            snapshots: snapshots,
            unavailable: unavailableAccountIDs,
            pin: cardPin,
            preferred: lastOpenedService,
            recentAccounts: lastOpenedAccounts,
            warning: alertSettings.warning,
            runningOutSoon: runningOutSoon(now: now),
            now: now
        )
    }

    /// 이 속도면 1시간 안에 바닥날 계정. 메뉴 줄의 소진 표시와 같은 기준.
    private func runningOutSoon(now: Date) -> Set<Account.ID> {
        Set(accounts.compactMap { account in
            guard let snapshot = snapshots[account.id] else { return nil }
            let cycles = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.id, cycle(for: account.id, window: $0)) })
            guard case .runsOutIn(_, soon: true)? = RowSummary.make(snapshot: snapshot, cycles: cycles, settings: alertSettings, now: now).notice else { return nil }
            return account.id
        })
    }

    /// 오류가 붙은 계정. 마지막 값이 남아 있어도 추천하지 않는다.
    private var unavailableAccountIDs: Set<Account.ID> { Set(errors.keys).union(deleting).union(deletionFailures) }

    var activeServices: [Service] {
        Service.allCases.filter { service in accounts.contains { $0.service == service } }
    }

    /// 수집기가 있는 서비스만 계정으로 추가할 수 있다.
    var supportedServices: [Service] {
        Service.allCases.filter { registry.provider(for: $0) != nil }
    }

    func accounts(for service: Service) -> [Account] {
        accounts.filter { $0.service == service }
    }

    func add(_ account: Account) {
        accounts.append(account)
        save()
        Task { await refresh(account) }
    }

    /// Keep the account until every credential store has been removed. Failure is visible and retryable.
    @discardableResult
    func remove(_ id: Account.ID) async -> Bool {
        guard let account = accounts.first(where: { $0.id == id }) else { return true }
        let targets = accounts.filter { $0.id == id || $0.linkedAccountID == id }
        let ids = Set(targets.map(\.id))
        guard deleting.isDisjoint(with: ids) else { return false }
        deleting.formUnion(ids)
        defer { deleting.subtract(ids) }
        do {
            for target in targets {
                AccountWindowController.close(for: target.id)
                try await CodexLogin.stop(for: target.id, store: self)
                try await GrokLogin.stop(for: target.id, store: self)
                await LoginWindowController.closeAndWait(for: target.id)
                if let read = reads[target.id] {
                    read.cancel()
                    _ = await read.result
                }
            }
            for target in targets { try await removeCredentials(target) }
        } catch {
            deletionFailures.formUnion(ids)
            for id in ids {
                errors[id] = String(localized: "로그인 정보를 지우지 못했습니다. 계정 삭제를 다시 시도하세요.")
            }
            onChange?()
            return false
        }
        if account.service == .grokBot, let cursorID = account.linkedAccountID,
           let index = accounts.firstIndex(where: { $0.id == cursorID }) {
            accounts[index].hidesGrokBot = true
        }
        if case .account(let pinned) = cardPin, ids.contains(pinned) { cardPin = nil }
        accounts.removeAll { ids.contains($0.id) }
        deletionFailures.subtract(ids)
        for id in ids {
            snapshots[id] = nil
            errors[id] = nil
            loginURLs[id] = nil
            loggingIn.remove(id)
            history.remove(account: id)
            ledger.remove(account: id)
            let alertIDs = scheduledAlerts.keys.filter { $0.contains(id.uuidString) }
            for alertID in alertIDs { deliver([.cancel(id: alertID)]) }
            recentAlerts.removeAll { $0.id.contains(id.uuidString) }
        }
        save()
        historyChanged = true
        evaluateAlerts()
        return true
    }

    static func deleteCredentials(for account: Account) async throws {
        switch account.service {
        case .claude, .cursor:
            try await WebSessions.remove(account.id)
        case .chatgpt where !account.usesSystemLogin:
            try CodexHomes.remove(for: account.id)
        case .grok where !account.usesSystemLogin:
            try GrokHomes.remove(for: account.id)
        default: break // Shared/system logins belong to the official app, never delete them.
        }
        let script = defaultDirectory.appending(path: "launch/\(account.id.uuidString).command")
        if FileManager.default.fileExists(atPath: script.path) { try FileManager.default.removeItem(at: script) }
    }

    /// Cursor 계정에 Grok Bot 한도가 있으면 Grok Bot 계정을 하나 만든다. 이름·그룹은 Cursor 계정을 따른다.
    private func addGrokBotIfNeeded(for cursor: Account) {
        guard cursor.service == .cursor, !cursor.hidesGrokBot,
              !accounts.contains(where: { $0.service == .grokBot && $0.linkedAccountID == cursor.id }) else { return }
        var grokBot = Account(service: .grokBot, label: cursor.label)
        grokBot.groupID = cursor.groupID
        grokBot.linkedAccountID = cursor.id
        add(grokBot)
    }

    @discardableResult
    func addGroup(named name: String) -> AccountGroup {
        let group = AccountGroup(name: name)
        groups.append(group)
        save()
        return group
    }

    func renameGroup(_ id: AccountGroup.ID, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = name
        save()
    }

    /// 그룹을 지워도 계정은 남기고 "그룹 없음"으로 옮긴다.
    func removeGroup(_ id: AccountGroup.ID) {
        groups.removeAll { $0.id == id }
        for index in accounts.indices where accounts[index].groupID == id {
            accounts[index].groupID = nil
        }
        save()
    }

    func moveGroups(fromOffsets source: IndexSet, toOffset destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// 메뉴 묶음 하나 안에서 계정 순서를 바꾼다. 다른 묶음의 계정 위치는 그대로 둔다.
    func moveAccounts(inSection sectionID: AccountSection.ID, fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let section = sections.first(where: { $0.id == sectionID }) else { return }
        var reordered = section.accounts
        reordered.move(fromOffsets: source, toOffset: destination)
        let slots = accounts.indices.filter { index in section.accounts.contains { $0.id == accounts[index].id } }
        for (slot, account) in zip(slots, reordered) { accounts[slot] = account }
        save()
    }

    func setSubscription(_ subscription: Subscription?, for id: Account.ID) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].subscription = subscription
        save()
        evaluateAlerts()
    }

    func renewal(for account: Account, now: Date = .now) -> Renewal? {
        Renewal.resolve(subscription: account.subscription, detected: detectedBilling(for: account), now: now)
    }

    /// 이 계정이 직접 받은 결제일, 없으면 같은 조직의 다른 계정이 받은 결제일.
    func detectedBilling(for account: Account) -> DetectedBilling? {
        if let own = snapshots[account.id]?.billing { return own }
        guard let organization = snapshots[account.id]?.organizationID else { return nil }
        return accounts
            .filter { $0.service == account.service && $0.id != account.id }
            .compactMap { snapshots[$0.id]?.billing }
            .first { $0.organizationID == organization }
    }

    /// 통화별 월 구독 합계. 입력한 구독이 없으면 nil.
    var monthlySubscriptionTotal: String? {
        MoneyText.monthlyTotal(accounts.compactMap(\.subscription))
    }

    func renameAccount(_ id: Account.ID, to label: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].label = label
        save()
    }

    func assign(_ accountID: Account.ID, to groupID: AccountGroup.ID?) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].groupID = groupID
        save()
    }

    /// 이 Mac의 기본 CLI 로그인(ChatGPT는 Codex, Grok은 Grok CLI)을 계정으로 추가한다. 이미 있으면 건너뛴다.
    func addSystemLogin(for service: Service) {
        guard service.hasSystemLogin, !hasSystemLogin(for: service) else { return }
        add(Account(service: service, label: String(localized: "기본"), usesSystemLogin: true))
    }

    func hasSystemLogin(for service: Service) -> Bool {
        accounts.contains { $0.service == service && $0.usesSystemLogin }
    }

    func setLoginURL(_ url: URL?, for id: Account.ID) {
        guard url == nil || canUse(id) else { return }
        loginURLs[id] = url
    }

    func setLoggingIn(_ id: Account.ID, _ active: Bool) {
        guard !active || canUse(id) else { return }
        if active { loggingIn.insert(id) } else { loggingIn.remove(id) }
    }

    func reportError(_ message: String, for id: Account.ID) {
        guard canUse(id) else { return }
        errors[id] = message
    }

    /// 로그인 창에서 바로 읽어온 값을 반영한다. 이메일을 적지 않은 계정은 이 로그인 계정에 묶는다.
    func record(_ snapshot: UsageSnapshot, for id: Account.ID) {
        guard canUse(id) else { return }
        if let index = accounts.firstIndex(where: { $0.id == id }), accounts[index].email == nil, let email = snapshot.loginEmail {
            accounts[index].email = email
            save()
        }
        apply(.success(snapshot), to: id)
        evaluateAlerts()
    }

    func startAutoRefresh(every interval: Duration = .seconds(300)) {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                try? await Task.sleep(for: self?.hasLowWindow == true ? min(interval, .seconds(120)) : interval)
            }
        }
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefresh = .now
        }
        await withTaskGroup(of: Void.self) { group in
            for account in accounts where canUse(account.id) {
                group.addTask { await self.refresh(account) }
            }
        }
        evaluateAlerts()
    }

    func refresh(_ account: Account) async {
        guard canUse(account.id) else { return }
        // One read per account; deletion waits for it before touching credentials.
        if let read = reads[account.id] {
            apply(await read.result, to: account.id)
            return
        }
        guard let provider = registry.provider(for: account.service) else {
            errors[account.id] = UsageError.notSupported.localizedDescription
            return
        }
        let read = Task {
            try Task.checkCancellation()
            return try await provider.fetchUsage(for: account)
        }
        reads[account.id] = read
        let result = await read.result
        reads[account.id] = nil
        apply(result, to: account.id)
        evaluateAlerts()
    }

    private func evaluateAlerts() {
        let before = (alertState, forecastSent)
        var events = AlertPlanner.plan(accounts: accounts, snapshots: snapshots, settings: alertSettings, state: &alertState, forecasted: forecastedKeys, unavailable: unavailableAccountIDs)
        let detected = Dictionary(uniqueKeysWithValues: accounts.compactMap { account in detectedBilling(for: account).map { (account.id, $0) } })
        events += AlertPlanner.planRenewals(accounts: accounts, detected: detected, settings: alertSettings)
        events += AlertPlanner.planForecasts(accounts: accounts, snapshots: snapshots, history: history, settings: alertSettings, sent: &forecastSent, state: alertState, unavailable: unavailableAccountIDs)
        deliver(events)
        if alertState != before.0 || forecastSent != before.1 { saveAlerts() }
        saveHistoryIfNeeded()
        onChange?()
    }

    private struct StoredAlerts: Codable {
        var settings: AlertSettings
        var state: [String: Double]
        var forecastSent: [String]?
    }

    private func saveHistoryIfNeeded() {
        guard historyChanged else { return }
        historyChanged = false
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(history).write(to: historyURL, options: .atomic)
            try JSONEncoder().encode(ledger).write(to: ledgerURL, options: .atomic)
        } catch {
            assertionFailure("사용 기록 저장 실패: \(error)")
        }
    }

    private func saveAlerts() {
        do {
            try FileManager.default.createDirectory(at: alertsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(StoredAlerts(settings: alertSettings, state: alertState, forecastSent: forecastSent.sorted())).write(to: alertsURL, options: .atomic)
        } catch {
            assertionFailure("알림 상태 저장 실패: \(error)")
        }
    }

    /// 실패해도 마지막으로 읽은 값은 남겨두고 오류만 표시한다.
    private func apply(_ result: Result<UsageSnapshot, any Error>, to id: Account.ID) {
        guard canUse(id), let account = accounts.first(where: { $0.id == id }) else { return }
        switch result {
        case .success(let snapshot):
            // 다른 계정의 사용량을 이 별칭에 붙이지 않는다.
            if let expected = account.email, let actual = snapshot.loginEmail,
               expected.caseInsensitiveCompare(actual) != .orderedSame {
                errors[id] = String(localized: "로그인된 계정(\(actual))이 이 계정의 이메일과 다릅니다")
                return
            }
            snapshots[id] = snapshot
            errors[id] = duplicateWarning(for: account, loginEmail: snapshot.loginEmail)
            // Reads finish in any order: an earlier account can reveal a duplicate already read.
            for other in accounts where other.id != id && errors[other.id] == nil && canUse(other.id) {
                if let email = snapshots[other.id]?.loginEmail {
                    errors[other.id] = duplicateWarning(for: other, loginEmail: email)
                }
            }
            if snapshot.hasGrokBot == true { addGrokBotIfNeeded(for: account) }
            let before = (history, ledger)
            history.record(snapshot, for: id)
            ledger.observe(snapshot, for: id)
            if history != before.0 || ledger != before.1 { historyChanged = true }
        case .failure(let error):
            errors[id] = error.localizedDescription
        }
    }

    /// 같은 서비스에서 먼저 추가한 계정과 로그인 이메일이 같으면, 나중에 추가한 쪽에 경고를 단다.
    private func duplicateWarning(for account: Account, loginEmail: String?) -> String? {
        guard let email = loginEmail, let index = accounts.firstIndex(where: { $0.id == account.id }) else { return nil }
        let earlier = accounts[..<index].first { other in
            other.service == account.service
                && (snapshots[other.id]?.loginEmail ?? other.email)?.caseInsensitiveCompare(email) == .orderedSame
        }
        return earlier.map { String(localized: "이미 추가된 계정(\($0.displayLabel))과 같은 계정입니다. 다른 계정으로 다시 로그인하세요") }
    }

    /// 더 이상 지원하지 않는 서비스의 계정은 빼고 나머지만 읽는다.
    private static func load(from url: URL) -> [Account] {
        struct Stored: Decodable {
            let account: Account?
            init(from decoder: any Decoder) throws { account = try? Account(from: decoder) }
        }
        let stored = (try? JSONDecoder().decode([Stored].self, from: Data(contentsOf: url))) ?? []
        return stored.compactMap(\.account)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: accountsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(accounts).write(to: accountsURL, options: .atomic)
            try encoder.encode(groups).write(to: groupsURL, options: .atomic)
        } catch {
            assertionFailure("계정 저장 실패: \(error)")
        }
    }
}
