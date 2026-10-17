import Foundation
import Testing
@testable import Tokta

private func snapshot(remaining: Double...) -> UsageSnapshot {
    UsageSnapshot(
        windows: remaining.enumerated().map { UsageWindow(id: "w\($0.offset)", title: "", used: 1 - $0.element) },
        observedAt: .now
    )
}

struct RecommendationTests {
    @Test func picksAccountWithMostHeadroomInItsTightestWindow() {
        let a = Account(service: .claude, label: "A"), b = Account(service: .claude, label: "B")
        // A는 주간이 넉넉해도 세션이 10%밖에 안 남아서 B가 낫다.
        let snapshots = [a.id: snapshot(remaining: 0.1, 0.9), b.id: snapshot(remaining: 0.5, 0.4)]
        #expect(Recommendation.bestAccount(among: [a, b], snapshots: snapshots)?.id == b.id)
    }

    @Test func skipsExhaustedAndUnfetchedAccounts() {
        let done = Account(service: .chatgpt, label: "다 씀"), pending = Account(service: .chatgpt, label: "조회 전")
        #expect(Recommendation.bestAccount(among: [done, pending], snapshots: [done.id: snapshot(remaining: 0, 0.8)]) == nil)
    }

    @Test func skipsStaleValuesEvenIfTheyLookRoomier() {
        let old = Account(service: .claude, label: "2시간 전 값"), fresh = Account(service: .claude, label: "방금 읽음")
        var stale = snapshot(remaining: 0.9)
        stale.observedAt = Date.now.addingTimeInterval(-7200)
        let snapshots = [old.id: stale, fresh.id: snapshot(remaining: 0.4)]
        #expect(Recommendation.bestAccount(among: [old, fresh], snapshots: snapshots)?.id == fresh.id)
    }

    @Test func skipsAccountsWithErrors() {
        let loggedOut = Account(service: .claude, label: "로그인 풀림"), ok = Account(service: .claude, label: "정상")
        let snapshots = [loggedOut.id: snapshot(remaining: 0.9), ok.id: snapshot(remaining: 0.4)]
        #expect(Recommendation.bestAccount(among: [loggedOut, ok], snapshots: snapshots, unavailable: [loggedOut.id])?.id == ok.id)
    }
}

struct NowPickTests {
    @Test func singleAccountStillGetsTheCard() {
        let only = Account(service: .claude, label: "하나")
        let pick = NowPick.make(accounts: [only], snapshots: [only.id: snapshot(remaining: 0.8)], preferred: nil)
        #expect(pick?.primary.id == only.id)
        #expect(pick?.basis == .first)
    }

    @Test func keepsTheBaseAccountInsteadOfFlippingToTheRoomiest() {
        let work = Account(service: .claude, label: "회사"), home = Account(service: .claude, label: "개인")
        let main = Account(service: .chatgpt, label: "메인")
        let snapshots = [work.id: snapshot(remaining: 0.31), home.id: snapshot(remaining: 0.82), main.id: snapshot(remaining: 0.96)]
        // 연 적이 없으면 그 서비스의 첫 계정. 개인이 더 넉넉해도 기준선 위면 바꾸라고 하지 않는다.
        let first = NowPick.make(accounts: [main, work, home], snapshots: snapshots, preferred: .claude)
        #expect(first?.primary.id == work.id)
        #expect(first?.basis == .first)
        #expect(first?.switchTo == nil)
        #expect(first?.others == [NowPick.Line(service: .chatgpt, account: main, remaining: 0.96)])
        // 최근 연 계정이 기준이 된다.
        let recent = NowPick.make(accounts: [main, work, home], snapshots: snapshots, preferred: .claude, recentAccounts: [.claude: home.id])
        #expect(recent?.primary.id == home.id)
        #expect(recent?.basis == .recent)
    }

    @Test func exhaustedBaseStaysAndNeverJumpsToAnotherService() {
        let spent = Account(service: .claude, label: "다 씀"), grok = Account(service: .grok, label: "기본")
        let snapshots = [spent.id: snapshot(remaining: 0), grok.id: snapshot(remaining: 0.5)]
        let pick = NowPick.make(accounts: [spent, grok], snapshots: snapshots, preferred: .claude)
        #expect(pick?.primary.id == spent.id)
        #expect(pick?.isBlocked == true)
        #expect(pick?.switchTo == nil)
        #expect(pick?.others == [NowPick.Line(service: .grok, account: grok, remaining: 0.5)])
    }

    @Test func pinnedServiceWinsOverLastOpened() {
        let claude = Account(service: .claude, label: "회사"), chatgpt = Account(service: .chatgpt, label: "메인")
        let snapshots = [claude.id: snapshot(remaining: 0.5), chatgpt.id: snapshot(remaining: 0.9)]
        let pick = NowPick.make(accounts: [claude, chatgpt], snapshots: snapshots, pin: .service(.chatgpt), preferred: .claude)
        #expect(pick?.primary.id == chatgpt.id)
        #expect(pick?.pin == .service(.chatgpt))
        #expect(pick?.pinnedUnavailable == nil)
    }

    @Test func pinnedServiceStaysEvenWhenItsAccountIsUsedUp() {
        let claude = Account(service: .claude, label: "다 씀"), chatgpt = Account(service: .chatgpt, label: "메인")
        let snapshots = [claude.id: snapshot(remaining: 0), chatgpt.id: snapshot(remaining: 0.9)]
        let pick = NowPick.make(accounts: [claude, chatgpt], snapshots: snapshots, pin: .service(.claude), preferred: nil)
        #expect(pick?.primary.id == claude.id)
        #expect(pick?.pin == .service(.claude))
        #expect(pick?.isBlocked == true)
    }

    @Test func pinnedAccountStaysEvenWhenAnotherIsRoomier() {
        let work = Account(service: .claude, label: "회사"), home = Account(service: .claude, label: "개인")
        let snapshots = [work.id: snapshot(remaining: 0.5), home.id: snapshot(remaining: 0.9)]
        let pick = NowPick.make(accounts: [work, home], snapshots: snapshots, pin: .account(work.id), preferred: nil)
        #expect(pick?.primary.id == work.id)
        #expect(pick?.switchTo == nil)
        #expect(pick?.openTarget.id == work.id)
    }

    @Test func pinnedAccountBelowWarningSuggestsRoomierAccount() {
        let work = Account(service: .claude, label: "회사"), home = Account(service: .claude, label: "개인")
        let snapshots = [work.id: snapshot(remaining: 0.12), home.id: snapshot(remaining: 0.64)]
        let pick = NowPick.make(accounts: [work, home], snapshots: snapshots, pin: .account(work.id), preferred: nil, warning: 0.2)
        #expect(pick?.primary.id == work.id)
        #expect(pick?.switchTo?.id == home.id)
        #expect(pick?.isBlocked == false)
        // 아직 쓸 수 있으니 열기 버튼은 고정한 계정 그대로.
        #expect(pick?.openTarget.id == work.id)
    }

    @Test func pinnedAccountRunningOutSoonSuggestsEvenAboveWarning() {
        let work = Account(service: .claude, label: "회사"), home = Account(service: .claude, label: "개인")
        let snapshots = [work.id: snapshot(remaining: 0.4), home.id: snapshot(remaining: 0.6)]
        let pick = NowPick.make(accounts: [work, home], snapshots: snapshots, pin: .account(work.id), preferred: nil, runningOutSoon: [work.id])
        #expect(pick?.switchTo?.id == home.id)
    }

    @Test func doesNotSuggestATighterAccount() {
        let work = Account(service: .claude, label: "회사"), home = Account(service: .claude, label: "개인")
        let snapshots = [work.id: snapshot(remaining: 0.15), home.id: snapshot(remaining: 0.1)]
        let pick = NowPick.make(accounts: [work, home], snapshots: snapshots, pin: .account(work.id), preferred: nil)
        #expect(pick?.switchTo == nil)
    }

    @Test func exhaustedPinnedAccountOpensTheSuggestion() {
        let work = Account(service: .claude, label: "회사"), home = Account(service: .claude, label: "개인")
        let snapshots = [work.id: snapshot(remaining: 0), home.id: snapshot(remaining: 0.64)]
        let pick = NowPick.make(accounts: [work, home], snapshots: snapshots, pin: .account(work.id), preferred: nil)
        #expect(pick?.primary.id == work.id)
        #expect(pick?.isBlocked == true)
        #expect(pick?.openTarget.id == home.id)
    }

    @Test func cardPinRoundTripsThroughStorage() {
        let id = UUID()
        for pin in [CardPin.service(.chatgpt), .account(id)] {
            #expect(CardPin(storageValue: pin.storageValue) == pin)
        }
        #expect(CardPin(storageValue: "service:없는서비스") == nil)
    }

    @Test func cardStaysWhenNothingIsUsable() {
        let a = Account(service: .claude, label: "A"), b = Account(service: .claude, label: "B")
        let pick = NowPick.make(accounts: [a, b], snapshots: [a.id: snapshot(remaining: 0.9)], unavailable: [a.id], preferred: nil)
        #expect(pick?.primary.id == a.id)
        #expect(pick?.isBlocked == true)
        #expect(pick?.switchTo == nil)
    }

    @Test func suggestsOnlyWithinTheSameGroup() {
        let team = UUID()
        var work = Account(service: .claude, label: "회사"); work.groupID = team
        var colleague = Account(service: .claude, label: "동료"); colleague.groupID = team
        let personal = Account(service: .claude, label: "개인")
        let snapshots = [work.id: snapshot(remaining: 0.1), colleague.id: snapshot(remaining: 0.5), personal.id: snapshot(remaining: 0.95)]
        let pick = NowPick.make(accounts: [work, colleague, personal], snapshots: snapshots, pin: .account(work.id), preferred: nil)
        #expect(pick?.switchTo?.id == colleague.id)
    }

    @Test func needsATenPointMarginUnlessBlocked() {
        let work = Account(service: .claude, label: "회사"), home = Account(service: .claude, label: "개인")
        let close = NowPick.make(accounts: [work, home], snapshots: [work.id: snapshot(remaining: 0.15), home.id: snapshot(remaining: 0.22)], pin: .account(work.id), preferred: nil)
        #expect(close?.switchTo == nil)
        let far = NowPick.make(accounts: [work, home], snapshots: [work.id: snapshot(remaining: 0.15), home.id: snapshot(remaining: 0.3)], pin: .account(work.id), preferred: nil)
        #expect(far?.switchTo?.id == home.id)
        let blocked = NowPick.make(accounts: [work, home], snapshots: [work.id: snapshot(remaining: 0), home.id: snapshot(remaining: 0.05)], pin: .account(work.id), preferred: nil)
        #expect(blocked?.switchTo?.id == home.id)
    }
}

@MainActor
struct StoreRecommendationTests {
    @Test func accountThatStartsFailingLosesRecommendation() async {
        let roomy = StubProvider(.success(snapshot(remaining: 0.9)))
        let store = UsageStore(registry: ProviderRegistry(providers: [.claude: roomy]), directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        let a = Account(service: .claude, label: "A"), b = Account(service: .claude, label: "B")
        store.add(a)
        store.add(b)
        await store.refresh(a)
        roomy.next = .success(snapshot(remaining: 0.4))
        await store.refresh(b)
        #expect(store.recommendedAccountIDs == [a.id])

        // A의 로그인이 풀려 마지막 값(90%)만 남으면 B를 추천한다.
        roomy.next = .failure(.needsLogin)
        await store.refresh(a)
        #expect(store.snapshots[a.id] != nil)
        #expect(store.recommendedAccountIDs == [b.id])
    }
}

struct ResetTextTests {
    static let cases: [(TimeInterval, String)] = [
        (-5, "곧 리셋"),
        (30, "1분 후 리셋"),
        (2_700, "45분 후 리셋"),
        (10_800, "3시간 후 리셋"),
        (7_800, "2시간 10분 후 리셋"),
        (190_800, "2일 5시간 후 리셋"),
    ]

    @Test(arguments: cases)
    func formats(offset: TimeInterval, expected: String) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ResetText.string(until: now.addingTimeInterval(offset), now: now) == expected)
    }
}

private final class StubProvider: UsageProvider, @unchecked Sendable {
    var next: Result<UsageSnapshot, UsageError>
    init(_ next: Result<UsageSnapshot, UsageError>) { self.next = next }
    func fetchUsage(for account: Account) async throws -> UsageSnapshot { try next.get() }
}

@MainActor
struct UsageStoreTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    @Test func persistsAccountsAcrossLaunches() {
        let store = UsageStore(registry: ProviderRegistry(providers: [:]), directory: directory)
        store.add(Account(service: .chatgpt, label: "회사", email: "work@example.com"))
        let reloaded = UsageStore(registry: ProviderRegistry(providers: [:]), directory: directory)
        #expect(reloaded.accounts.map(\.label) == ["회사"])
        #expect(reloaded.accounts.first?.email == "work@example.com")
    }

    @Test func failedRefreshKeepsLastSnapshotAndShowsError() async {
        let stub = StubProvider(.success(snapshot(remaining: 0.7)))
        let store = UsageStore(registry: ProviderRegistry(providers: [.claude: stub]), directory: directory)
        let account = Account(service: .claude, label: "메인")
        store.add(account)
        await store.refresh(account)
        #expect(store.snapshots[account.id]?.windows.first?.remaining == 0.7)

        stub.next = .failure(.needsLogin)
        await store.refreshAll()
        #expect(store.snapshots[account.id] != nil)
        #expect(store.errors[account.id] == "로그인이 필요합니다")
    }

    @Test func serviceWithoutProviderIsMarkedUnsupported() async {
        let store = UsageStore(registry: ProviderRegistry(providers: [:]), directory: directory)
        let account = Account(service: .claude, label: "기본")
        store.add(account)
        await store.refreshAll()
        #expect(store.errors[account.id] == "아직 지원하지 않는 서비스입니다")
    }
}

struct CodexParsingTests {
    @Test func readsWeeklyOnlyProPlan() throws {
        // 2026-10 실제 응답에서 개인정보를 뺀 형태. Pro는 주간 한도 하나만 내려온다.
        let json = #"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":4,"windowDurationMins":10080,"resetsAt":1792472315},"secondary":null,"planType":"pro"},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":4,"windowDurationMins":10080,"resetsAt":1792472315},"secondary":null}}}"#
        let windows = try CodexProvider.windows(from: Data(json.utf8))
        #expect(windows.map(\.title) == ["Codex 주간"])
        #expect(windows[0].used == 0.04)
        #expect(windows[0].resetsAt == Date(timeIntervalSince1970: 1792472315))
    }

    @Test func readsSessionAndWeeklyWindows() throws {
        let json = #"{"rateLimits":{"primary":{"usedPercent":62.5,"windowDurationMins":300,"resetsAt":1792400000},"secondary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":1792900000}}}"#
        let windows = try CodexProvider.windows(from: Data(json.utf8))
        #expect(windows.map(\.title) == ["Codex 5시간", "Codex 주간"])
        #expect(windows[0].remaining == 0.375)
    }

    @Test func rejectsResponseWithoutLimits() {
        #expect(throws: UsageError.self) { try CodexProvider.windows(from: Data(#"{"rateLimits":{"primary":null}}"#.utf8)) }
    }

    @Test func readsLimitResetsLeft() {
        // 2026-10 실제 응답의 형태. credits 배열 안은 쓰지 않는다.
        let json = #"{"rateLimits":{"primary":{"usedPercent":4,"windowDurationMins":10080,"resetsAt":1792472315}},"rateLimitResetCredits":{"availableCount":2,"credits":[{}]}}"#
        #expect(CodexProvider.limitResetsLeft(from: Data(json.utf8)) == 2)
    }

    @Test func missingLimitResetsIsNil() {
        let json = #"{"rateLimits":{"primary":{"usedPercent":4,"windowDurationMins":10080,"resetsAt":1792472315}}}"#
        #expect(CodexProvider.limitResetsLeft(from: Data(json.utf8)) == nil)
    }
}

struct ClaudeParsingTests {
    @Test func readsSessionWeeklyAndModelWindows() throws {
        let json = #"{"five_hour":{"utilization":37.0,"resets_at":"2026-10-13T09:59:59.943648+00:00"},"seven_day":{"utilization":12.5,"resets_at":"2026-10-18T03:00:00+00:00"},"seven_day_oauth_apps":null,"seven_day_opus":{"utilization":0.0,"resets_at":null},"extra_usage":{"is_enabled":false}}"#
        let windows = try ClaudeUsageParser.windows(from: Data(json.utf8))
        #expect(windows.map(\.title) == ["5시간", "주간", "주간 · Opus"])
        #expect(windows[0].used == 0.37)
        #expect(windows[0].resetsAt == Date.lenientISO8601("2026-10-13T09:59:59Z"))
        #expect(windows[2].resetsAt == nil)
    }

    @Test func newLimitsFormatOverridesAndAddsModelWindows() throws {
        let json = #"{"five_hour":{"utilization":10,"resets_at":null},"limits":[{"kind":"session","percent":42,"resets_at":"2026-10-13T12:00:00Z"},{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}},"utilization":5},{"kind":"unknown","percent":99}]}"#
        let windows = try ClaudeUsageParser.windows(from: Data(json.utf8))
        #expect(windows.map(\.id) == ["five_hour", "seven_day_fable"])
        #expect(windows[0].used == 0.42)
        #expect(windows[1].title == "주간 · Fable")
    }

    @Test func picksLastActiveChatOrganization() throws {
        let json = #"[{"uuid":"api-org","capabilities":["api"]},{"uuid":"team-org","capabilities":["chat","claude_pro"]},{"uuid":"personal-org","capabilities":["chat","claude_max"]}]"#
        let org = try ClaudeUsageParser.organization(from: Data(json.utf8), activeID: "personal-org")
        #expect(org.id == "personal-org")
        #expect(org.plan == "Max")
    }

    @Test func refusesToGuessBetweenOrganizations() {
        let json = #"[{"uuid":"a","capabilities":["chat"]},{"uuid":"b","capabilities":["chat"]}]"#
        #expect(throws: UsageError.self) { try ClaudeUsageParser.organization(from: Data(json.utf8), activeID: nil) }
    }
}

@MainActor
struct MigrationTests {
    @Test func movesCodexToChatGPTAndDropsRemovedServices() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = #"[{"id":"7A0D2F3E-1111-4E4B-9C5F-000000000001","service":"codex","label":"기본"},{"id":"7A0D2F3E-1111-4E4B-9C5F-000000000002","service":"claudeCode","label":"기본"},{"id":"7A0D2F3E-1111-4E4B-9C5F-000000000003","service":"claude","label":"메인"}]"#
        try Data(json.utf8).write(to: directory.appending(path: "accounts.json"))
        let store = UsageStore(registry: ProviderRegistry(providers: [:]), directory: directory)
        #expect(store.accounts.map(\.service) == [.chatgpt, .claude])
    }
}

@MainActor
struct LoginEmailTests {
    @Test func refusesSnapshotFromDifferentLogin() async {
        var snap = snapshot(remaining: 0.5)
        snap.loginEmail = "other@example.com"
        let store = UsageStore(registry: ProviderRegistry(providers: [.chatgpt: StubProvider(.success(snap))]), directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        let account = Account(service: .chatgpt, label: "회사", email: "Work@example.com")
        store.add(account)
        await store.refresh(account)
        #expect(store.snapshots[account.id] == nil)
        #expect(store.errors[account.id]?.contains("other@example.com") == true)
    }
}

@MainActor
struct GroupTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    private func store() -> UsageStore {
        UsageStore(registry: ProviderRegistry(providers: [:]), directory: directory)
    }

    @Test func withoutGroupsSectionsFollowServices() {
        let store = store()
        store.add(Account(service: .claude, label: "메인"))
        store.add(Account(service: .chatgpt, label: "개인"))
        #expect(store.sections.map(\.title) == ["Codex", "Claude"])
        #expect(store.sections.allSatisfy { !$0.showsService })
    }

    @Test func groupsMixServicesAndKeepUngroupedLast() {
        let store = store()
        let work = store.addGroup(named: "회사")
        store.addGroup(named: "빈 그룹")
        let claude = Account(service: .claude, label: "회사 Claude", groupID: work.id)
        let chatgpt = Account(service: .chatgpt, label: "회사 GPT", groupID: work.id)
        store.add(claude)
        store.add(chatgpt)
        store.add(Account(service: .claude, label: "개인"))
        #expect(store.sections.map(\.title) == ["회사", "그룹 없음"])
        #expect(store.sections[0].accounts.map(\.label) == ["회사 Claude", "회사 GPT"])
        #expect(store.sections[0].showsService)
    }

    @Test func removingGroupKeepsItsAccounts() {
        let store = store()
        let group = store.addGroup(named: "개인")
        let account = Account(service: .claude, label: "메인", groupID: group.id)
        store.add(account)
        store.removeGroup(group.id)
        #expect(store.accounts.first?.groupID == nil)
        #expect(store.sections.map(\.title) == ["Claude"])
    }

    @Test func groupsPersistWithNamesOrderAndMembership() {
        let first = store()
        let a = first.addGroup(named: "A")
        let b = first.addGroup(named: "B")
        first.renameGroup(a.id, to: "회사")
        first.moveGroups(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        let account = Account(service: .chatgpt, label: "기본")
        first.add(account)
        first.assign(account.id, to: b.id)

        let reloaded = store()
        #expect(reloaded.groups.map(\.name) == ["B", "회사"])
        #expect(reloaded.accounts.first?.groupID == b.id)
    }
}

@MainActor
struct ChatGPTAccountTests {
    @Test func legacyChatGPTAccountKeepsUsingSystemLogin() throws {
        let json = #"[{"id":"7A0D2F3E-1111-4E4B-9C5F-000000000001","service":"chatgpt","label":"기본"},{"id":"7A0D2F3E-1111-4E4B-9C5F-000000000002","service":"claude","label":"메인"}]"#
        let accounts = try JSONDecoder().decode([Account].self, from: Data(json.utf8))
        #expect(accounts.map(\.usesSystemLogin) == [true, false])
    }

    @Test func newAccountRoundTripsLoginChoice() throws {
        let account = Account(service: .chatgpt, label: "회사")
        let decoded = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(account))
        #expect(decoded.usesSystemLogin == false)
    }

    @Test func dedicatedAccountBeforeLoginNeverFallsBackToSystemLogin() async {
        let account = Account(service: .chatgpt, label: "회사")
        await #expect(throws: UsageError.needsLogin) { try await CodexProvider().fetchUsage(for: account) }
    }

    @Test func preparedHomeStoresCredentialsInFile() throws {
        let id = UUID()
        defer { CodexHomes.remove(for: id) }
        let home = try CodexHomes.prepare(for: id)
        let config = try String(contentsOf: home.appending(path: "config.toml"), encoding: .utf8)
        #expect(config.contains(#"cli_auth_credentials_store = "file""#))
        #expect(!CodexHomes.isLoggedIn(home))
        let permissions = try FileManager.default.attributesOfItem(atPath: home.path)[.posixPermissions] as? Int
        #expect(permissions == 0o700)
    }

    @Test func connectingThisMacAddsSystemLoginNextToDedicatedAccounts() {
        let store = UsageStore(registry: ProviderRegistry(providers: [:]), directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        store.add(Account(service: .chatgpt, label: "회사"))
        store.addSystemLogin(for: .chatgpt)
        store.addSystemLogin(for: .chatgpt)
        #expect(store.accounts.map(\.usesSystemLogin) == [false, true])
    }
}

private func window(_ id: String, remaining: Double, resetsIn: TimeInterval? = 3600, now: Date) -> UsageWindow {
    UsageWindow(id: id, title: id == "five_hour" ? "5시간" : "주간", used: 1 - remaining, resetsAt: resetsIn.map { now.addingTimeInterval($0) })
}

struct AlertPlannerTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let work = Account(service: .claude, label: "회사")
    let home = Account(service: .claude, label: "개인")

    private func plan(_ snapshots: [Account.ID: [UsageWindow]], settings: AlertSettings = AlertSettings(), state: inout [String: Double], accounts: [Account]? = nil) -> [AlertEvent] {
        AlertPlanner.plan(
            accounts: accounts ?? [work, home],
            snapshots: snapshots.mapValues { UsageSnapshot(windows: $0, observedAt: now) },
            settings: settings, state: &state, now: now
        )
    }

    private func notifications(_ events: [AlertEvent]) -> [AlertMessage] {
        events.compactMap { if case .notify(let message) = $0 { message } else { nil } }
    }

    @Test func notifiesOncePerCycleUntilWindowRecovers() {
        var state: [String: Double] = [:]
        #expect(notifications(plan([work.id: [window("five_hour", remaining: 0.5, now: now)]], state: &state)).isEmpty)
        #expect(notifications(plan([work.id: [window("five_hour", remaining: 0.18, now: now)]], state: &state)).count == 1)
        #expect(notifications(plan([work.id: [window("five_hour", remaining: 0.12, now: now)]], state: &state)).isEmpty)
        // 5%는 메뉴 색에만 쓰고 알림은 다시 보내지 않는다.
        #expect(notifications(plan([work.id: [window("five_hour", remaining: 0.04, now: now)]], state: &state)).isEmpty)

        let recovered = plan([work.id: [window("five_hour", remaining: 1, now: now)]], state: &state)
        #expect(recovered == [.cancel(id: AlertPlanner.resetID("\(work.id.uuidString)|five_hour"))])
        #expect(notifications(plan([work.id: [window("five_hour", remaining: 0.15, now: now)]], state: &state)).count == 1)
    }

    @Test func dropsStraightToCriticalWithSingleAlert() {
        var state: [String: Double] = [:]
        let messages = notifications(plan([work.id: [window("seven_day", remaining: 0.03, now: now)]], state: &state))
        #expect(messages.count == 1)
        #expect(messages[0].body.hasPrefix(">_< 주간 3% 남음"))
    }

    @Test func suggestsAnotherAccountOnlyWhenItHasRoom() {
        var state: [String: Double] = [:]
        let roomy = notifications(plan([work.id: [window("five_hour", remaining: 0.1, now: now)], home.id: [window("five_hour", remaining: 0.8, now: now)]], state: &state))
        #expect(roomy[0].body.contains("→ 개인 계정은 80% 남았어요"))
        // 버튼: 넉넉한 계정으로 열기가 먼저, 이 계정 그대로 열기가 그다음.
        #expect(roomy[0].actions.map(\.title) == ["개인 계정으로 열기", "회사 그대로 열기"])
        #expect(roomy[0].actions.first?.url == WidgetData.openURL(for: home.id))

        state = [:]
        let bothLow = notifications(plan([work.id: [window("five_hour", remaining: 0.1, now: now)], home.id: [window("five_hour", remaining: 0.15, now: now)]], state: &state))
        #expect(bothLow.allSatisfy { !$0.body.contains("→") })

        state = [:]
        let homeFailing = AlertPlanner.plan(
            accounts: [work, home],
            snapshots: [work.id: UsageSnapshot(windows: [window("five_hour", remaining: 0.1, now: now)], observedAt: now),
                        home.id: UsageSnapshot(windows: [window("five_hour", remaining: 0.8, now: now)], observedAt: now)],
            settings: AlertSettings(), state: &state, unavailable: [home.id], now: now
        )
        #expect(notifications(homeFailing).allSatisfy { !$0.body.contains("→") })
        #expect(notifications(homeFailing).allSatisfy { $0.actions == [.open(work)] })
    }

    @Test func schedulesResetOnlyForLowWindows() {
        var state: [String: Double] = [:]
        let events = plan([work.id: [window("five_hour", remaining: 0.1, resetsIn: 600, now: now), window("seven_day", remaining: 0.9, now: now)]], state: &state)
        let scheduled = events.compactMap { if case .schedule(let message, let date) = $0 { (message, date) } else { nil } }
        #expect(scheduled.count == 1)
        #expect(scheduled[0].0.body == "5시간 한도 리셋 예정 시각이에요")
        #expect(scheduled[0].0.actions == [.open(work)])
        #expect(scheduled[0].1 == now.addingTimeInterval(600))
    }

    @Test func respectsDisabledSettingsButKeepsTracking() {
        var state: [String: Double] = [:]
        var settings = AlertSettings()
        settings.lowEnabled = false
        settings.resetEnabled = false
        #expect(plan([work.id: [window("five_hour", remaining: 0.1, now: now)]], settings: settings, state: &state).isEmpty)
        #expect(state.count == 1)
    }

    @Test func forgetsRemovedAccountsAndCancelsTheirResets() {
        var state: [String: Double] = [:]
        _ = plan([work.id: [window("five_hour", remaining: 0.1, now: now)]], state: &state)
        let events = plan([:], state: &state, accounts: [home])
        #expect(events == [.cancel(id: AlertPlanner.resetID("\(work.id.uuidString)|five_hour"))])
        #expect(state.isEmpty)
    }

    @Test func statusLevelUsesBestAccountPerServiceAndTightestService() {
        let gpt = Account(service: .chatgpt, label: "기본")
        func level(_ values: [Account.ID: Double]) -> StatusLevel {
            AlertPlanner.statusLevel(accounts: [work, home, gpt], snapshots: values.mapValues { UsageSnapshot(windows: [window("w", remaining: $0, now: now)], observedAt: now) }, settings: AlertSettings())
        }
        #expect(level([:]) == .normal)
        #expect(level([work.id: 0.03, home.id: 0.9, gpt.id: 0.5]) == .normal)
        #expect(level([work.id: 0.03, home.id: 0.15, gpt.id: 0.5]) == .warning)
        #expect(level([work.id: 0.5, gpt.id: 0.02]) == .critical)
    }
}

@MainActor
private final class RecordingNotifier: AlertDelivering {
    var events: [AlertEvent] = []
    func handle(_ event: AlertEvent) { events.append(event) }
    func requestAuthorization() async -> Bool { true }
}

@MainActor
struct StoreAlertTests {
    @Test func alertStateSurvivesRestartSoNoDuplicateNotification() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let low = UsageSnapshot(windows: [UsageWindow(id: "five_hour", title: "5시간", used: 0.9)], observedAt: .now)
        let registry = ProviderRegistry(providers: [.claude: StubProvider(.success(low))])

        let first = RecordingNotifier()
        let store = UsageStore(registry: registry, directory: directory, notifier: first)
        var settings = store.alertSettings
        settings.destination = .mac
        store.updateAlertSettings(settings)
        store.add(Account(service: .claude, label: "회사"))
        await store.refreshAll()
        #expect(first.events.contains { if case .notify = $0 { true } else { false } })
        #expect(store.statusLevel == .warning)

        let second = RecordingNotifier()
        let restarted = UsageStore(registry: registry, directory: directory, notifier: second)
        await restarted.refreshAll()
        #expect(!second.events.contains { if case .notify = $0 { true } else { false } })
    }

    @Test func iPhoneDestinationRelaysInsteadOfNotifyingTheMac() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let low = UsageSnapshot(windows: [UsageWindow(id: "five_hour", title: "5시간", used: 0.9, resetsAt: .now.addingTimeInterval(3600))], observedAt: .now)
        let notifier = RecordingNotifier()
        let store = UsageStore(registry: ProviderRegistry(providers: [.claude: StubProvider(.success(low))]), directory: directory, notifier: notifier)
        var phone = store.alertSettings
        phone.destination = .iPhone
        store.updateAlertSettings(phone)
        store.add(Account(service: .claude, label: "회사"))
        await store.refreshAll()
        #expect(!notifier.events.contains { if case .cancel = $0 { false } else { true } })
        let relay = store.phoneAlerts
        #expect(relay.toPhone)
        #expect(relay.recent.count == 1)
        #expect(relay.scheduled.map(\.body) == ["5시간 한도 리셋 예정 시각이에요"])

        var settings = store.alertSettings
        settings.destination = .mac
        store.updateAlertSettings(settings)
        #expect(store.phoneAlerts.toPhone == false)
    }

    @Test func alertSettingsPersist() {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = UsageStore(registry: ProviderRegistry(providers: [:]), directory: directory)
        var settings = store.alertSettings
        settings.thresholds = [0.3]
        settings.resetEnabled = false
        store.updateAlertSettings(settings)
        #expect(UsageStore(registry: ProviderRegistry(providers: [:]), directory: directory).alertSettings == settings)
    }
}

@MainActor
struct AccountOrderTests {
    private func store() -> UsageStore {
        UsageStore(registry: ProviderRegistry(providers: [:]), directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    @Test func movingInsideGroupKeepsOtherSectionsInPlace() {
        let store = store()
        let work = store.addGroup(named: "회사")
        for (label, group) in [("A", work.id), ("개인", nil), ("B", work.id), ("C", work.id)] {
            store.add(Account(service: .claude, label: label, groupID: group))
        }
        store.moveAccounts(inSection: work.id.uuidString, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(store.sections.map { $0.accounts.map(\.label) } == [["C", "A", "B"], ["개인"]])
        #expect(store.accounts.map(\.label) == ["C", "개인", "A", "B"])
    }

    @Test func orderPersistsAndAppliesToServiceSections() {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let first = UsageStore(registry: ProviderRegistry(providers: [:]), directory: directory)
        first.add(Account(service: .chatgpt, label: "개인"))
        first.add(Account(service: .chatgpt, label: "회사"))
        first.moveAccounts(inSection: Service.chatgpt.rawValue, fromOffsets: IndexSet(integer: 1), toOffset: 0)
        let reloaded = UsageStore(registry: ProviderRegistry(providers: [:]), directory: directory)
        #expect(reloaded.sections.first?.accounts.map(\.label) == ["회사", "개인"])
    }
}

struct GrokTests {
    @Test func unusedUnifiedWeekReadsAsZeroPercent() throws {
        // 2026-10-13 실제 응답 형식. 하나도 안 쓴 주에는 creditUsagePercent가 빠진다.
        let json = #"{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-10-11T15:28:46.333986+00:00","end":"2026-10-18T15:28:46.333986+00:00"},"onDemandCap":{"val":0},"onDemandUsed":{"val":0},"isUnifiedBillingUser":true,"prepaidBalance":{"val":0},"topUpMethod":"x","billingPeriodStart":"2026-10-11T15:28:46.333986+00:00","billingPeriodEnd":"2026-10-18T15:28:46.333986+00:00"}}"#
        let windows = try GrokProvider.windows(from: Data(json.utf8))
        #expect(windows.map(\.title) == ["주간"])
        #expect(windows[0].used == 0)
        #expect(windows[0].resetsAt == Date.lenientISO8601("2026-10-18T15:28:46Z"))
    }

    @Test func readsUsagePercentAndMonthlyFallback() throws {
        let percent = #"{"config":{"creditUsagePercent":42.5,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-10-18T15:28:46Z"}}}"#
        #expect(try GrokProvider.windows(from: Data(percent.utf8))[0].used == 0.425)
        let monthly = #"{"config":{"monthlyLimit":{"val":200},"used":{"val":50},"billingPeriodEnd":"2026-11-01T00:00:00Z"}}"#
        let windows = try GrokProvider.windows(from: Data(monthly.utf8))
        #expect(windows[0].used == 0.25)
        #expect(windows[0].title == "구독 기간")
    }

    @Test func refusesResponseWithoutUsage() {
        #expect(throws: UsageError.self) { try GrokProvider.windows(from: Data(#"{"config":{"isUnifiedBillingUser":false}}"#.utf8)) }
    }

    @Test func readsAuthEntryAndRejectsTeamLogin() throws {
        let personal = #"{"https://auth.x.ai::client":{"key":"test-token","email":"me@example.com","expires_at":"2026-10-13T20:00:00Z","principal_type":"User"}}"#
        let auth = try GrokProvider.Auth.decode(Data(personal.utf8))
        #expect(auth.email == "me@example.com")
        #expect(auth.expiresAt == Date.lenientISO8601("2026-10-13T20:00:00Z"))
        let team = #"{"https://auth.x.ai::client":{"key":"t","principal_type":"Team"}}"#
        #expect(throws: UsageError.self) { try GrokProvider.Auth.decode(Data(team.utf8)) }
        #expect(throws: UsageError.needsLogin) { try GrokProvider.Auth.decode(Data("{}".utf8)) }
    }

    @Test func dedicatedAccountBeforeLoginNeverFallsBackToSystemLogin() async {
        await #expect(throws: UsageError.needsLogin) { try await GrokProvider().fetchUsage(for: Account(service: .grok, label: "서브")) }
    }

    @MainActor
    @Test func systemLoginIsAddedOncePerService() {
        let store = UsageStore(registry: ProviderRegistry(providers: [:]), directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        store.addSystemLogin(for: .grok)
        store.addSystemLogin(for: .grok)
        store.addSystemLogin(for: .claude)
        #expect(store.accounts.map(\.service) == [.grok])
        #expect(store.accounts[0].usesSystemLogin)
    }
}

struct CursorTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    @Test func readsModelPoolsAndPlanWithoutGrokBot() throws {
        let summary = #"{"membershipType":"ultra","billingCycleEnd":"2026-11-01T00:00:00.000Z","individualUsage":{"plan":{"enabled":true,"autoPercentUsed":12.5,"apiPercentUsed":40,"totalPercentUsed":30}}}"#
        let usage = try CursorProvider.usage(summary: Data(summary.utf8))
        #expect(usage.plan == "Ultra")
        // Grok Bot은 따로 보여주므로 Cursor 계정에는 섞지 않는다.
        #expect(usage.windows.map(\.title) == ["Cursor 모델", "기타 모델"])
        #expect(usage.windows[0].used == 0.125)
        #expect(usage.windows[0].resetsAt == Date.lenientISO8601("2026-11-01T00:00:00Z"))
    }

    @Test func readsGrokBotWeekly() {
        let sand = #"{"includedLimitZero":false,"usagePercent":75,"nextResetTimestampUtc":"2026-10-19T00:00:00Z"}"#
        let window = CursorProvider.grokBotWindow(Data(sand.utf8), now: now)
        #expect(window?.title == "주간")
        #expect(window?.remaining == 0.25)
        #expect(window?.resetsAt == Date.lenientISO8601("2026-10-19T00:00:00Z"))
    }

    @Test func fallsBackToTotalPlanUsage() throws {
        let summary = #"{"billingCycleEnd":1793500000000,"individualUsage":{"plan":{"used":50,"limit":200}}}"#
        let usage = try CursorProvider.usage(summary: Data(summary.utf8))
        #expect(usage.windows.map(\.title) == ["플랜"])
        #expect(usage.windows[0].used == 0.25)
        #expect(usage.windows[0].resetsAt == Date(timeIntervalSince1970: 1_793_500_000))
    }

    @Test func grokBotTrialOnlyWhileActiveAndHiddenWithoutLimit() {
        let trial = #"{"includedLimitZero":true,"sandTrialExpiresAt":"2026-10-20T00:00:00Z","usagePercent":10}"#
        #expect(CursorProvider.grokBotWindow(Data(trial.utf8), now: now)?.title == "체험")
        let expired = #"{"includedLimitZero":true,"sandTrialExpiresAt":"2020-01-01T00:00:00Z","usagePercent":10}"#
        #expect(CursorProvider.grokBotWindow(Data(expired.utf8), now: now) == nil)
        let legacy = #"{"hasNonZeroIncludedLimit":true,"usagePercent":5}"#
        #expect(CursorProvider.grokBotWindow(Data(legacy.utf8), now: now)?.title == "주간")
    }

    @Test func refusesDisabledOrTeamPlan() {
        #expect(throws: UsageError.self) { try CursorProvider.usage(summary: Data(#"{"individualUsage":{"plan":{"enabled":false}}}"#.utf8)) }
        #expect(throws: UsageError.self) { try CursorProvider.usage(summary: Data(#"{"teamUsage":{}}"#.utf8)) }
    }
}

@MainActor
struct DailyUseTests {
    @Test func renamePersistsAndBlankNameShowsPlaceholder() {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = UsageStore(registry: ProviderRegistry(providers: [:]), directory: directory)
        let account = Account(service: .claude, label: "메인")
        store.add(account)
        store.renameAccount(account.id, to: "회사 Max")
        #expect(UsageStore(registry: ProviderRegistry(providers: [:]), directory: directory).accounts.first?.displayLabel == "회사 Max")
        store.renameAccount(account.id, to: "   ")
        #expect(store.accounts.first?.displayLabel == "이름 없음")
    }

    @Test func snapshotBecomesStaleAfterFifteenMinutes() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let fresh = UsageSnapshot(windows: [], observedAt: now.addingTimeInterval(-14 * 60))
        let old = UsageSnapshot(windows: [], observedAt: now.addingTimeInterval(-16 * 60))
        #expect(!fresh.isStale(at: now))
        #expect(old.isStale(at: now))
    }

    nonisolated static let ages: [(TimeInterval, String)] = [(30, "방금"), (720, "12분 전"), (10_740, "2시간 전"), (259_200, "3일 전")]

    @Test(arguments: ages)
    func ageText(seconds: TimeInterval, expected: String) {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        #expect(AgeText.string(since: now.addingTimeInterval(-seconds), now: now) == expected)
    }

    @Test func menuBarValueIsTightestServiceUsingItsBestAccount() {
        let now = Date.now
        let claudeA = Account(service: .claude, label: "A"), claudeB = Account(service: .claude, label: "B"), gpt = Account(service: .chatgpt, label: "G")
        func snap(_ remaining: Double) -> UsageSnapshot { UsageSnapshot(windows: [UsageWindow(id: "w", title: "", used: 1 - remaining)], observedAt: now) }
        let value = AlertPlanner.tightestRemaining(accounts: [claudeA, claudeB, gpt], snapshots: [claudeA.id: snap(0.1), claudeB.id: snap(0.7), gpt.id: snap(0.4)])
        #expect(value == 0.4)
        #expect(AlertPlanner.tightestRemaining(accounts: [gpt], snapshots: [:]) == nil)
    }
}

struct HistoryTests {
    let start = Date(timeIntervalSince1970: 2_000_000_000)
    let account = UUID()

    private func snap(_ used: Double, at minutes: Double, id: String = "five_hour", resetIn: TimeInterval? = 4 * 3600) -> UsageSnapshot {
        let t = start.addingTimeInterval(minutes * 60)
        return UsageSnapshot(windows: [UsageWindow(id: id, title: "5시간", used: used, resetsAt: resetIn.map { start.addingTimeInterval($0) })], observedAt: t)
    }

    @Test func recordsOnlyChangesOrEveryTenMinutes() {
        var history = UsageHistory()
        history.record(snap(0.10, at: 0), for: account)
        history.record(snap(0.101, at: 5), for: account)    // 거의 같고 10분 안 → 건너뜀
        history.record(snap(0.20, at: 6), for: account)     // 바뀜 → 남김
        history.record(snap(0.20, at: 17), for: account)    // 같아도 10분 지남 → 남김
        #expect(history.currentCycle(account: account, window: "five_hour").map(\.u) == [0.10, 0.20, 0.20])
    }

    @Test func dropMarksNewCycleAndOldSamplesArePruned() {
        var history = UsageHistory()
        history.record(snap(0.8, at: 0), for: account)
        history.record(snap(0.9, at: 30), for: account)
        history.record(snap(0.05, at: 60), for: account)    // 리셋
        history.record(snap(0.10, at: 90), for: account)
        #expect(history.currentCycle(account: account, window: "five_hour").map(\.u) == [0.05, 0.10])
        history.record(snap(0.12, at: 9 * 24 * 60), for: account)
        #expect(history.series.values.flatMap { $0 }.count == 1)
    }

    @Test func forecastsExhaustionBeforeResetFromRecentPace() {
        // 30분에 20%씩 → 지금 60% 사용, 남은 40%는 1시간 뒤 바닥. 리셋은 4시간 뒤.
        let cycle = [UsageSample(t: start, u: 0.2), UsageSample(t: start.addingTimeInterval(1800), u: 0.4)]
        let window = UsageWindow(id: "five_hour", title: "5시간", used: 0.6, resetsAt: start.addingTimeInterval(4 * 3600))
        let exhausts = Forecaster.exhaustion(cycle: cycle, window: window, observedAt: start.addingTimeInterval(3600))
        #expect(exhausts == start.addingTimeInterval(2 * 3600))
    }

    @Test func noForecastWhenResetComesFirstOrTooLittleData() {
        let slow = [UsageSample(t: start, u: 0.1), UsageSample(t: start.addingTimeInterval(3600), u: 0.12)]
        let window = UsageWindow(id: "five_hour", title: "5시간", used: 0.12, resetsAt: start.addingTimeInterval(2 * 3600))
        #expect(Forecaster.exhaustion(cycle: slow, window: window, observedAt: start.addingTimeInterval(3600)) == nil)
        let short = [UsageSample(t: start, u: 0.1)]
        #expect(Forecaster.exhaustion(cycle: short, window: window, observedAt: start.addingTimeInterval(600)) == nil)
    }

    @Test func forecastTextUsesDurationWithinADay() {
        #expect(ForecastText.string(exhaustsAt: start.addingTimeInterval(2 * 3600 + 600), now: start) == "이 속도면 2시간 10분 뒤 바닥")
        #expect(ForecastText.string(exhaustsAt: start.addingTimeInterval(30), now: start) == "이 속도면 곧 바닥")
    }
}

@MainActor
struct ForecastAlertTests {
    @Test func alertsOncePerCycleWithSuggestion() {
        let now = Date.now
        let busy = Account(service: .claude, label: "회사"), spare = Account(service: .claude, label: "개인")
        var history = UsageHistory()
        for (minutes, used) in [(-40.0, 0.5), (-20.0, 0.65)] {
            history.record(UsageSnapshot(windows: [UsageWindow(id: "five_hour", title: "5시간", used: used, resetsAt: now.addingTimeInterval(3 * 3600))], observedAt: now.addingTimeInterval(minutes * 60)), for: busy.id)
        }
        let snapshots = [
            busy.id: UsageSnapshot(windows: [UsageWindow(id: "five_hour", title: "5시간", used: 0.8, resetsAt: now.addingTimeInterval(3 * 3600))], observedAt: now),
            spare.id: UsageSnapshot(windows: [UsageWindow(id: "five_hour", title: "5시간", used: 0.1)], observedAt: now),
        ]
        var sent: Set<String> = []
        let first = AlertPlanner.planForecasts(accounts: [busy, spare], snapshots: snapshots, history: history, settings: AlertSettings(), sent: &sent, now: now)
        guard case .notify(let message) = first.first else { Issue.record("알림 없음"); return }
        #expect(message.body.contains("뒤 바닥"))
        #expect(message.body.contains("→ 개인 계정은 90% 남았어요"))
        #expect(AlertPlanner.planForecasts(accounts: [busy, spare], snapshots: snapshots, history: history, settings: AlertSettings(), sent: &sent, now: now).isEmpty)

        var off = AlertSettings()
        off.lowEnabled = false
        var fresh: Set<String> = []
        #expect(AlertPlanner.planForecasts(accounts: [busy, spare], snapshots: snapshots, history: history, settings: off, sent: &fresh, now: now).isEmpty)
    }

    @Test func olderSettingsFileKeepsValuesAndEnablesForecast() throws {
        let json = #"{"lowEnabled":false,"resetEnabled":true,"thresholds":[0.3]}"#
        let settings = try JSONDecoder().decode(AlertSettings.self, from: Data(json.utf8))
        #expect(settings.lowEnabled == false)
        #expect(settings.thresholds == [0.3])
        #expect(settings.forecastEnabled)
        #expect(settings.destination == .mac)
    }

    @Test func forecastAndThresholdMergeIntoOneAlertPerCycle() {
        let now = Date.now
        let work = Account(service: .claude, label: "회사")
        var state: [String: Double] = [:]
        let key = "\(work.id.uuidString)|five_hour"
        let events = AlertPlanner.plan(accounts: [work], snapshots: [work.id: UsageSnapshot(windows: [window("five_hour", remaining: 0.15, now: now)], observedAt: now)],
                                       settings: AlertSettings(), state: &state, forecasted: [key], now: now)
        #expect(!events.contains { if case .notify = $0 { true } else { false } })
        #expect(state[key] != nil)
    }

    @Test func historySurvivesRestart() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let snap = UsageSnapshot(windows: [UsageWindow(id: "five_hour", title: "5시간", used: 0.3)], observedAt: .now)
        let registry = ProviderRegistry(providers: [.claude: StubProvider(.success(snap))])
        let store = UsageStore(registry: registry, directory: directory)
        let account = Account(service: .claude, label: "메인")
        store.add(account)
        await store.refreshAll()
        let reloaded = UsageStore(registry: registry, directory: directory)
        #expect(reloaded.history.currentCycle(account: account.id, window: "five_hour").map(\.u) == [0.3])
    }
}

struct SubscriptionTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func nextMonthlyRenewalFromPastOrFutureAnchor() {
        let past = Subscription(amount: 20, anchor: day(2025, 3, 20))
        #expect(past.nextRenewal(onOrAfter: day(2026, 10, 13, 15), calendar: calendar) == day(2026, 10, 20))
        #expect(past.nextRenewal(onOrAfter: day(2026, 10, 20, 23), calendar: calendar) == day(2026, 10, 20))
        let future = Subscription(amount: 20, anchor: day(2026, 12, 5))
        #expect(future.nextRenewal(onOrAfter: day(2026, 10, 13), calendar: calendar) == day(2026, 12, 5))
    }

    @Test func monthEndAndYearlyRenewals() {
        let monthEnd = Subscription(amount: 20, anchor: day(2026, 1, 31))
        #expect(monthEnd.nextRenewal(onOrAfter: day(2026, 2, 10), calendar: calendar) == day(2026, 2, 28))
        #expect(monthEnd.nextRenewal(onOrAfter: day(2026, 3, 1), calendar: calendar) == day(2026, 3, 31))
        let yearly = Subscription(amount: 240, cycle: .yearly, anchor: day(2024, 5, 1))
        #expect(yearly.nextRenewal(onOrAfter: day(2026, 10, 13), calendar: calendar) == day(2027, 5, 1))
        #expect(yearly.monthlyAmount == 20)
    }

    @Test func monthlyTotalPerCurrencyAndMoneyFormat() {
        let subscriptions = [
            Subscription(amount: 200, anchor: .now),
            Subscription(amount: 240, cycle: .yearly, anchor: .now),
            Subscription(amount: 29000, currency: "KRW", anchor: .now),
        ]
        #expect(MoneyText.monthlyTotal(subscriptions) == "$220 · ₩29,000")
        #expect(MoneyText.string(Decimal(string: "19.99")!, currency: "USD") == "$19.99")
        #expect(MoneyText.monthlyTotal([]) == nil)
    }

    @Test func renewalTextShowsDayCount() {
        let now = day(2026, 10, 13, 15)
        #expect(RenewalText.string(day(2026, 10, 13), now: now, calendar: calendar) == "오늘 결제")
        #expect(RenewalText.string(day(2026, 10, 14), now: now, calendar: calendar) == "내일 결제")
        #expect(RenewalText.string(day(2026, 10, 20), now: now, calendar: calendar) == "10월 20일 결제 (D-7)")
    }

    @Test func reminderIsScheduledDayBeforeAtNine() {
        var account = Account(service: .claude, label: "회사")
        account.subscription = Subscription(amount: 200, anchor: day(2026, 9, 20))
        let events = AlertPlanner.planRenewals(accounts: [account], settings: AlertSettings(), now: day(2026, 10, 13, 15), calendar: calendar)
        guard case .schedule(let message, let date) = events.first else { Issue.record("예약 없음"); return }
        #expect(date == day(2026, 10, 19, 9))
        #expect(message.body == "내일 $200 결제 예정 (매월)")

        // 전날 9시가 지났으면 그다음 결제를 예약한다.
        let late = AlertPlanner.planRenewals(accounts: [account], settings: AlertSettings(), now: day(2026, 10, 19, 10), calendar: calendar)
        guard case .schedule(_, let next) = late.first else { Issue.record("예약 없음"); return }
        #expect(next == day(2026, 11, 19, 9))
    }

    @Test func noSubscriptionOrDisabledCancels() {
        var account = Account(service: .claude, label: "회사")
        #expect(AlertPlanner.planRenewals(accounts: [account], settings: AlertSettings()) == [.cancel(id: AlertPlanner.renewalID(account.id))])
        account.subscription = Subscription(amount: 20, anchor: .now)
        var off = AlertSettings()
        off.renewalEnabled = false
        #expect(AlertPlanner.planRenewals(accounts: [account], settings: off) == [.cancel(id: AlertPlanner.renewalID(account.id))])
    }

    @MainActor
    @Test func subscriptionPersistsAndOldAccountsDecode() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = UsageStore(registry: ProviderRegistry(providers: [:]), directory: directory)
        let account = Account(service: .grok, label: "Heavy")
        store.add(account)
        store.setSubscription(Subscription(amount: 300, anchor: day(2026, 10, 1)), for: account.id)
        let reloaded = UsageStore(registry: ProviderRegistry(providers: [:]), directory: directory)
        #expect(reloaded.accounts.first?.subscription?.amount == 300)
        #expect(reloaded.monthlySubscriptionTotal == "$300")

        let old = #"{"id":"7A0D2F3E-1111-4E4B-9C5F-000000000003","service":"claude","label":"메인"}"#
        #expect(try JSONDecoder().decode(Account.self, from: Data(old.utf8)).subscription == nil)
    }
}

struct DetectedBillingTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func readsClaudeSubscriptionDetails() throws {
        // 2026-10-13 실제 응답 형식(카드 정보는 뺌).
        let json = #"{"billing_interval":"monthly","currency":"usd","next_charge_at":"2026-11-10T05:06:45Z","next_charge_date":"2026-11-10","plan_ending_at":null,"status":"active","payment_method":{"type":"card"}}"#
        let billing = try #require(ClaudeUsageParser.billing(from: Data(json.utf8), calendar: calendar))
        #expect(billing.nextCharge == day(2026, 11, 10))
        #expect(billing.cycle == .monthly)
        #expect(billing.currency == "USD")
        #expect(billing.endsAt == nil)
    }

    @Test func claudeEndingAndInactiveSubscriptions() throws {
        let ending = #"{"status":"active","next_charge_date":"2026-11-10","plan_ending_at":"2026-11-10T05:06:45Z"}"#
        #expect(ClaudeUsageParser.billing(from: Data(ending.utf8), calendar: calendar)?.endsAt != nil)
        let canceled = #"{"status":"canceled","next_charge_date":"2026-11-10"}"#
        #expect(ClaudeUsageParser.billing(from: Data(canceled.utf8), calendar: calendar) == nil)
    }

    @Test func cursorUsesBillingCycleEnd() {
        let summary = #"{"billingCycleEnd":"2026-11-01T00:00:00.000Z","individualUsage":{"plan":{"autoPercentUsed":1}}}"#
        #expect(CursorProvider.billing(summary: Data(summary.utf8))?.nextCharge == Date.lenientISO8601("2026-11-01T00:00:00Z"))
    }

    @Test func manualDateWinsOverDetectedAndDetectedWorksWithoutPrice() {
        let now = day(2026, 10, 13, 15)
        let detected = DetectedBilling(nextCharge: day(2026, 11, 10))
        let manual = Subscription(amount: 20, anchor: day(2026, 9, 20))
        #expect(Renewal.resolve(subscription: manual, detected: detected, now: now, calendar: calendar) == Renewal(date: day(2026, 10, 20), isDetected: false, isEnding: false))
        let auto = Subscription(amount: 20, anchor: nil)
        #expect(Renewal.resolve(subscription: auto, detected: detected, now: now, calendar: calendar) == Renewal(date: day(2026, 11, 10), isDetected: true, isEnding: false))
        #expect(Renewal.resolve(subscription: nil, detected: detected, now: now, calendar: calendar)?.isDetected == true)
        let past = DetectedBilling(nextCharge: day(2026, 10, 1))
        #expect(Renewal.resolve(subscription: nil, detected: past, now: now, calendar: calendar) == nil)
    }

    @Test func remindersForDetectedDatesSkipEndingSubscriptions() {
        let now = day(2026, 10, 13, 15)
        let account = Account(service: .claude, label: "회사")
        let events = AlertPlanner.planRenewals(accounts: [account], detected: [account.id: DetectedBilling(nextCharge: day(2026, 11, 10))], settings: AlertSettings(), now: now, calendar: calendar)
        guard case .schedule(let message, let date) = events.first else { Issue.record("예약 없음"); return }
        #expect(date == day(2026, 11, 9, 9))
        #expect(message.body == "내일 결제 예정")

        let ending = DetectedBilling(nextCharge: day(2026, 11, 10), endsAt: day(2026, 11, 10))
        #expect(AlertPlanner.planRenewals(accounts: [account], detected: [account.id: ending], settings: AlertSettings(), now: now, calendar: calendar) == [.cancel(id: AlertPlanner.renewalID(account.id))])
        #expect(RenewalText.string(day(2026, 11, 10), now: now, ending: true, calendar: calendar) == "11월 10일 구독 종료 (D-28)")
    }

    @Test func subscriptionWithoutDateRoundTrips() throws {
        let auto = Subscription(amount: 200, anchor: nil)
        #expect(try JSONDecoder().decode(Subscription.self, from: JSONEncoder().encode(auto)) == auto)
        #expect(MoneyText.monthlyTotal([auto]) == "$200")
    }
}

private struct PerAccountProvider: UsageProvider {
    let make: @Sendable (Account) -> UsageSnapshot
    func fetchUsage(for account: Account) async throws -> UsageSnapshot { make(account) }
}

@MainActor
struct SharedOrganizationBillingTests {
    @Test func membersReuseOwnerBillingOfSameOrganization() async {
        let next = Date.now.addingTimeInterval(20 * 86400)
        let provider = PerAccountProvider { account in
            var snapshot = UsageSnapshot(windows: [UsageWindow(id: "five_hour", title: "5시간", used: 0.1)], observedAt: .now)
            snapshot.organizationID = account.label == "다른 조직" ? "org-b" : "org-a"
            if account.label == "관리자" { snapshot.billing = DetectedBilling(nextCharge: next, organizationID: "org-a") }
            return snapshot
        }
        let store = UsageStore(registry: ProviderRegistry(providers: [.claude: provider]), directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        let owner = Account(service: .claude, label: "관리자"), member = Account(service: .claude, label: "멤버"), outsider = Account(service: .claude, label: "다른 조직")
        for account in [owner, member, outsider] { store.add(account) }
        await store.refreshAll()
        #expect(store.detectedBilling(for: member)?.nextCharge == next)
        #expect(store.renewal(for: member)?.isDetected == true)
        #expect(store.detectedBilling(for: outsider) == nil)
    }

    @Test func oneReminderPerOrganizationPreferringAccountWithPrice() {
        let now = Date.now
        let billing = DetectedBilling(nextCharge: now.addingTimeInterval(10 * 86400), organizationID: "org-a")
        let member = Account(service: .claude, label: "멤버")
        var owner = Account(service: .claude, label: "관리자")
        owner.subscription = Subscription(amount: 150, anchor: nil)
        let events = AlertPlanner.planRenewals(accounts: [member, owner], detected: [member.id: billing, owner.id: billing], settings: AlertSettings(), now: now)
        #expect(events.count == 2)
        #expect(events[0] == .cancel(id: AlertPlanner.renewalID(member.id)))
        guard case .schedule(let message, _) = events[1] else { Issue.record("관리자 계정 예약 없음"); return }
        #expect(message.body == "내일 $150 결제 예정 (매월)")
    }
}

@MainActor
struct LoginGuidanceTests {
    @Test func detectsGoogleSignInPages() {
        #expect(WebLoginSite.isGoogleSignIn(URL(string: "https://accounts.google.com/v3/signin/identifier?x=1")!))
        #expect(!WebLoginSite.isGoogleSignIn(URL(string: "https://claude.ai/login")!))
    }

    @Test func laterDuplicateLoginGetsWarningEarlierStaysClean() async {
        let provider = PerAccountProvider { _ in
            UsageSnapshot(windows: [UsageWindow(id: "w", title: "주간", used: 0.1)], observedAt: .now, loginEmail: "Same@Example.com")
        }
        let store = UsageStore(registry: ProviderRegistry(providers: [.chatgpt: provider]), directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        let first = Account(service: .chatgpt, label: "개인"), second = Account(service: .chatgpt, label: "회사")
        store.add(first)
        store.add(second)
        await store.refreshAll()
        #expect(store.errors[first.id] == nil)
        #expect(store.errors[second.id] == "이미 추가된 계정(개인)과 같은 계정입니다. 다른 계정으로 다시 로그인하세요")
        #expect(store.snapshots[second.id] != nil)
    }

    @Test func settingsHintMatchesLoginPlace() {
        #expect(AccountsSettingsHint.text(for: .claude).contains("이메일로 계속하기"))
        #expect(AccountsSettingsHint.text(for: .chatgpt).contains("브라우저"))
    }
}

struct RequiredAppTests {
    @Test func onlyCliServicesNeedAnApp() {
        #expect(RequiredApp.requirement(for: .chatgpt)?.name == "ChatGPT 데스크톱 앱")
        #expect(RequiredApp.requirement(for: .grok)?.name == "Grok CLI")
        #expect(RequiredApp.requirement(for: .claude) == nil)
        #expect(RequiredApp.isInstalled(for: .cursor))
        #expect(RequiredApp.missingMessage(for: .grok) == "Grok CLI가 설치돼 있지 않습니다. 설치한 뒤 다시 시도하세요")
    }
}

struct RowSummaryTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func window(_ id: String, used: Double, resetsIn: TimeInterval?) -> UsageWindow {
        UsageWindow(id: id, title: id, used: used, resetsAt: resetsIn.map { now.addingTimeInterval($0) })
    }

    @Test func showsTightestWindowWithoutNoticeWhenFine() {
        let snapshot = UsageSnapshot(windows: [window("five_hour", used: 0.88, resetsIn: 71 * 60), window("seven_day", used: 0.41, resetsIn: 3 * 86400)], observedAt: now)
        let summary = RowSummary.make(snapshot: snapshot, cycles: [:], settings: AlertSettings(), now: now)
        #expect(abs(summary.remaining - 0.12) < 0.0001)
        #expect(summary.level == .warning)
        #expect(summary.notice == nil)
    }

    @Test func exhaustedWindowShowsWhenItRefills() {
        let snapshot = UsageSnapshot(windows: [window("five_hour", used: 1, resetsIn: 40 * 60), window("seven_day", used: 0.3, resetsIn: 86400)], observedAt: now)
        let summary = RowSummary.make(snapshot: snapshot, cycles: [:], settings: AlertSettings(), now: now)
        #expect(summary.level == .critical)
        #expect(summary.notice == .refillsIn("40분"))
    }

    @Test func forecastBeatsResetTime() {
        let snapshot = UsageSnapshot(windows: [window("five_hour", used: 0.8, resetsIn: 3 * 3600)], observedAt: now)
        let cycles = ["five_hour": [UsageSample(t: now.addingTimeInterval(-1800), u: 0.5)]]
        let summary = RowSummary.make(snapshot: snapshot, cycles: cycles, settings: AlertSettings(), now: now)
        #expect(summary.notice == .runsOutIn("20분", soon: true))
    }

    @Test func staleValueSaysHowOld() {
        let snapshot = UsageSnapshot(windows: [window("five_hour", used: 0.2, resetsIn: 3600)], observedAt: now.addingTimeInterval(-3600))
        let summary = RowSummary.make(snapshot: snapshot, cycles: [:], settings: AlertSettings(), now: now)
        #expect(summary.notice == .stale("1시간 전"))
    }

    @Test func barColorsFollowAlertThresholds() {
        let settings = AlertSettings()
        #expect(StatusLevel(remaining: 0.5, settings: settings) == .normal)
        #expect(StatusLevel(remaining: 0.2, settings: settings) == .warning)
        #expect(StatusLevel(remaining: 0.05, settings: settings) == .critical)
    }

    @Test func barTonesSplitAboveAlertThresholds() {
        let settings = AlertSettings()
        #expect(BarTone(remaining: 0.8, settings: settings) == .plenty)
        #expect(BarTone(remaining: 0.5, settings: settings) == .moderate)
        #expect(BarTone(remaining: 0.21, settings: settings) == .moderate)
        #expect(BarTone(remaining: 0.2, settings: settings) == .low)
        #expect(BarTone(remaining: 0.03, settings: settings) == .critical)
    }
}

struct UsagePaletteTests {
    @Test func everyPaletteResolvesAllLevels() {
        for palette in UsagePalette.allCases {
            #expect(palette.platformColor(for: StatusLevel.normal) == nil)
            // 예전에 경고 단계가 자기 자신을 불러 앱이 멈췄다. 값이 나오기만 하면 된다.
            #expect(palette.platformColor(for: StatusLevel.warning) != nil)
            #expect(palette.platformColor(for: StatusLevel.critical) != nil)
        }
    }
}

struct TerminalLaunchTests {
    @Test func scriptRunsCLIWithAccountHomeAndKeepsShell() {
        let script = TerminalLaunch.script(
            binary: URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"),
            environment: ["CODEX_HOME": "/Users/me/Library/Application Support/Tokta/codex/A"],
            title: "Codex · 회사"
        )
        #expect(script.hasPrefix("#!/bin/zsh -l\n"))
        #expect(script.contains("export CODEX_HOME='/Users/me/Library/Application Support/Tokta/codex/A'\n"))
        #expect(script.contains("'/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex'\nexec /bin/zsh -l\n"))
    }

    @Test func quotingKeepsShellFromInterpretingNames() {
        #expect(TerminalLaunch.quote("민's $(rm -rf ~)") == #"'민'\''s $(rm -rf ~)'"#)
    }
}

struct DownloadNameTests {
    @Test func addsNumberWhenFileExists() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(AccountWindowController.uniqueDownloadURL(for: "report.pdf", in: directory).lastPathComponent == "report.pdf")
        try Data().write(to: directory.appending(path: "report.pdf"))
        #expect(AccountWindowController.uniqueDownloadURL(for: "report.pdf", in: directory).lastPathComponent == "report 2.pdf")
    }
}

struct AntigravityTests {
    /// 2026-10-14 agy 1.3.4 `agy -p /usage --output-format json` 실제 응답(무료 개인 계정).
    static let realResponse = #"{"conversation_id":"","status":"SUCCESS","response":"Gemini Models\tWeekly Limit Remaining\t100%\t2026-10-20T16:11:04Z\nClaude and GPT models\tWeekly Limit Remaining\t100%\t2026-10-20T16:11:04Z\n","duration_seconds":0,"num_turns":0,"usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0},"command":{"name":"usage","data":{"description":"Within each group, models share a weekly limit. Quota is consumed proportionally to the cost of the tokens. Thus, limits will last longer with shorter tasks or using more cost-effective models. Your weekly limit is tied directly to your individual tier.","groups":[{"name":"Gemini Models","description":"Models within this group: Gemini Flash, Gemini Pro","buckets":[{"id":"gemini-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":1,"reset_time":"2026-10-20T16:11:04Z"}]},{"name":"Claude and GPT models","description":"Models within this group: Claude Opus, Claude Sonnet, GPT-OSS","buckets":[{"id":"3p-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":1,"reset_time":"2026-10-20T16:11:04Z"}]}]}}}"#

    @Test func readsWeeklyGroupsFromRealResponse() throws {
        let windows = try AntigravityProvider.windows(from: Data(Self.realResponse.utf8))
        #expect(windows.map(\.title) == ["Gemini 주간", "Claude·GPT 주간"])
        #expect(windows.map(\.id) == ["gemini-weekly", "3p-weekly"])
        #expect(windows.allSatisfy { $0.remaining == 1 })
        #expect(windows[0].resetsAt == Date.lenientISO8601("2026-10-20T16:11:04Z"))
    }

    @Test func readsSessionBucketsWhenTheyAppear() throws {
        // 유료 등급은 5시간 구간이 더 올 수 있다. 창 이름(window)만 보고 붙인다.
        let json = #"{"status":"SUCCESS","command":{"data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"gemini-session","window":"session","remaining_fraction":0.25,"reset_time":"2026-10-14T05:00:00Z"},{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.9}]}]}}}"#
        let windows = try AntigravityProvider.windows(from: Data(json.utf8))
        #expect(windows.map(\.title) == ["Gemini 5시간", "Gemini 주간"])
        #expect(windows[0].remaining == 0.25)
    }

    @Test func failedOrEmptyOutputSaysToSignIn() {
        #expect(throws: UsageError.self) { try AntigravityProvider.windows(from: Data()) }
        #expect(throws: UsageError.self) { try AntigravityProvider.windows(from: Data(#"{"status":"ERROR"}"#.utf8)) }
    }

    @Test func antigravityIsSingleAccountSystemLogin() {
        #expect(Service.antigravity.supportsMultipleAccounts == false)
        #expect(Service.antigravity.hasSystemLogin)
    }

    @MainActor
    @Test func geminiAccountsMoveToAntigravity() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = #"[{"id":"7A0D2F3E-1111-4E4B-9C5F-000000000009","service":"gemini","label":"기본","usesSystemLogin":true}]"#
        try Data(json.utf8).write(to: directory.appending(path: "accounts.json"))
        let store = UsageStore(registry: ProviderRegistry(providers: [:]), directory: directory)
        #expect(store.accounts.map(\.service) == [.antigravity])
        #expect(store.accounts.first?.usesSystemLogin == true)
    }
}

struct ExecutablesTests {
    @Test func parsesLoginShellPathKeepingOrderWithoutDuplicates() {
        #expect(Executables.parsePath("/Users/me/.local/node/bin:/usr/bin::relative:/usr/bin") == ["/Users/me/.local/node/bin", "/usr/bin"])
    }

    @Test func findsCLIsInstalledWhereTheLoginShellLooks() {
        // 이 Mac의 실제 로그인 셸 PATH를 읽는다. 셸이 PATH를 주면 /usr/bin은 늘 들어 있다.
        #expect(Executables.loginShellPath.isEmpty || Executables.loginShellPath.contains("/usr/bin"))
    }
}

@MainActor
struct WidgetDataTests {
    /// 계정 이름마다 정해진 결과를 준다. `add`가 띄우는 비동기 새로고침과 순서가 엇갈려도 결과가 같다.
    private struct ByLabel: UsageProvider {
        let results: [String: Result<UsageSnapshot, UsageError>]
        func fetchUsage(for account: Account) async throws -> UsageSnapshot { try results[account.label]!.get() }
    }

    @Test func summarizesBestAccountPerServiceLikeTheMenu() async {
        let provider = ByLabel(results: ["A": .success(snapshot(remaining: 0.9)), "B": .success(snapshot(remaining: 0.1, 0.8)), "C": .failure(.needsLogin)])
        let store = UsageStore(registry: ProviderRegistry(providers: [.claude: provider, .cursor: provider]), directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        let a = Account(service: .claude, label: "A"), b = Account(service: .claude, label: "B"), c = Account(service: .cursor, label: "C")
        store.add(a); store.add(b); store.add(c)
        await store.refreshAll()

        let data = WidgetData.build(from: store, palette: .graphite)
        #expect(data.palette == .graphite)
        let claude = data.services.first { $0.id == "claude" }
        #expect(claude?.best?.label == "A")
        #expect(claude?.roomyCount == 1)
        #expect(claude?.accountCount == 2)
        // 계정이 하나면 오류가 있어도 그 계정을 보여주고, 문제를 표시한다.
        let cursor = data.services.first { $0.id == "cursor" }
        #expect(cursor?.best?.label == "C")
        #expect(cursor?.best?.problem == "확인 필요")

        let rowB = data.sections.flatMap(\.rows).first { $0.label == "B" }
        #expect(rowB?.bars.map(\.tone) == [.low, .plenty])
        #expect(rowB?.level == .warning)
        #expect(rowB?.isRecommended == false)
    }

    @Test func savesAndLoadsThroughFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/widget.json")
        let row = WidgetData.Row(id: UUID(), serviceID: "claude", serviceName: "Claude", label: "메인", plan: "Max", remaining: 0.4, level: .normal,
                                 bars: [.init(tone: .moderate, remaining: 0.4)], isRecommended: true, problem: nil, observedAt: Date(timeIntervalSince1970: 2_000_000_000))
        let data = WidgetData(updatedAt: Date(timeIntervalSince1970: 2_000_000_000), palette: .indigo,
                              sections: [.init(id: "claude", title: "Claude", rows: [row])],
                              services: [.init(id: "claude", name: "Claude", best: row, roomyCount: 1, accountCount: 1)])
        try data.save(to: url)
        #expect(WidgetData.load(from: url) == data)
    }

    @Test func openURLRoundTrips() {
        let id = UUID()
        #expect(WidgetData.accountID(fromOpenURL: WidgetData.openURL(for: id)) == id)
        #expect(WidgetData.accountID(fromOpenURL: URL(string: "https://example.com/open/\(id.uuidString)")!) == nil)
    }
}

struct CharacterMoodTests {
    let settings = AlertSettings()

    @Test func followsTheSameLevelsAsTheMenu() {
        #expect(CharacterMood.of(remaining: 0.8, settings: settings) == .happy)
        #expect(CharacterMood.of(remaining: 0.4, settings: settings) == .calm)
        #expect(CharacterMood.of(remaining: 0.15, settings: settings) == .squeeze)
        #expect(CharacterMood.of(remaining: 0, settings: settings) == .sleep)
        #expect(CharacterMood.of(remaining: nil, settings: settings) == .calm)
        #expect(CharacterMood.of(remaining: 0.9, settings: settings, isUnavailable: true) == .calm)
    }

    @Test func runOutSoonSqueezesAndResetCheers() {
        #expect(CharacterMood.of(remaining: 0.6, settings: settings, notice: .runsOutIn("20분", soon: true)) == .squeeze)
        #expect(CharacterMood.of(remaining: 0.6, settings: settings, notice: .runsOutIn("3시간", soon: false)) == .happy)
        #expect(CharacterMood.of(remaining: 1, settings: settings, justReset: true) == .joy)
        // 다 쓴 계정은 방금 리셋 기록이 있어도 잔다.
        #expect(CharacterMood.of(remaining: 0, settings: settings, justReset: true) == .sleep)
    }

    @Test func historyFindsTheLastReset() {
        var history = UsageHistory()
        let id = UUID(), t0 = Date(timeIntervalSince1970: 2_000_000_000)
        for (i, used) in [0.5, 0.8, 0.95, 0.02].enumerated() {
            history.record(UsageSnapshot(windows: [UsageWindow(id: "w", title: "", used: used)], observedAt: t0.addingTimeInterval(Double(i) * 900)), for: id)
        }
        #expect(history.lastReset(account: id, window: "w") == t0.addingTimeInterval(2700))
        #expect(history.lastReset(account: UUID(), window: "w") == nil)
    }

    @Test func spriteMatchesTheDesign() {
        // 화면 아홉 줄 중 남은 비율만큼 아래부터 빛. 신호등과 얼굴 자리는 늘 같다.
        let full = PixelSprite.grid(mood: .happy, remaining: 1, fillIsLight: false)
        let empty = PixelSprite.grid(mood: .sleep, remaining: 0, fillIsLight: false)
        #expect(full[13][1] == .fill && full[5][1] == .fill)
        #expect(empty[13][1] == .screen)
        #expect(full[2][2] == .red && full[2][4] == .yellow && full[2][6] == .green)
        #expect(full[7][5] == .faceLight)            // ^ 꼭대기
        #expect(empty[9][11] == .zzz)                // 잘 때 Z
        let light = PixelSprite.grid(mood: .calm, remaining: 1, fillIsLight: true)
        #expect(light[10][8] == .faceDark)           // 밝은 빛 위의 입은 진한 색
    }
}

@MainActor
struct GrokBotSplitTests {
    private struct CursorStub: UsageProvider {
        let hasGrokBot: Bool
        func fetchUsage(for account: Account) async throws -> UsageSnapshot {
            var snapshot = UsageSnapshot(windows: [UsageWindow(id: "cursor_models", title: "Cursor 모델", used: 0.1)], observedAt: .now)
            snapshot.hasGrokBot = hasGrokBot
            return snapshot
        }
    }

    private func store(hasGrokBot: Bool = true) -> UsageStore {
        UsageStore(registry: ProviderRegistry(providers: [.cursor: CursorStub(hasGrokBot: hasGrokBot), .grokBot: StubProvider(.success(snapshot(remaining: 0.3)))]),
                   directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    @Test func cursorWithGrokBotGetsALinkedGrokBotAccount() async {
        let store = store()
        let group = store.addGroup(named: "개인")
        var cursor = Account(service: .cursor, label: "내 커서")
        cursor.groupID = group.id
        store.add(cursor)
        await store.refresh(cursor)
        await store.refresh(cursor)   // 두 번 읽어도 하나만
        let grokBots = store.accounts.filter { $0.service == .grokBot }
        #expect(grokBots.count == 1)
        #expect(grokBots.first?.linkedAccountID == cursor.id)
        #expect(grokBots.first?.label == "내 커서")
        #expect(grokBots.first?.groupID == group.id)
    }

    @Test func noGrokBotAccountWithoutGrokBotLimit() async {
        let store = store(hasGrokBot: false)
        let cursor = Account(service: .cursor, label: "커서")
        store.add(cursor)
        await store.refresh(cursor)
        #expect(!store.accounts.contains { $0.service == .grokBot })
    }

    @Test func deletedGrokBotStaysDeletedAndGoesWithItsCursor() async {
        let store = store()
        let cursor = Account(service: .cursor, label: "커서")
        store.add(cursor)
        await store.refresh(cursor)
        let grokBot = store.accounts.first { $0.service == .grokBot }!
        store.remove(grokBot.id)
        await store.refresh(cursor)
        #expect(!store.accounts.contains { $0.service == .grokBot })
        #expect(store.accounts.first?.hidesGrokBot == true)

        let other = self.store()
        let second = Account(service: .cursor, label: "커서2")
        other.add(second)
        await other.refresh(second)
        other.remove(second.id)
        #expect(other.accounts.isEmpty)
    }

    @Test func grokBotIsNotOfferedInTheAddList() {
        #expect(Service.grokBot.supportsMultipleAccounts == false)
        #expect(Service.grokBot.hasSystemLogin == false)
    }
}

struct EstimationTests {
    let observed = Date(timeIntervalSince1970: 2_000_000_000)

    private func row(_ label: String, bars: [WidgetData.Bar], problem: String? = nil) -> WidgetData.Row {
        let remaining = bars.map(\.remaining).min()
        return WidgetData.Row(id: UUID(), serviceID: "claude", serviceName: "Claude", label: label, plan: nil, remaining: remaining,
                              level: (remaining ?? 1) <= 0.2 ? .warning : .normal, bars: bars, isRecommended: false,
                              problem: problem, observedAt: observed, mood: (remaining ?? 1) <= 0 ? .sleep : .calm)
    }

    @Test func windowsPastTheirResetAreFullAgain() {
        let main = row("메인", bars: [.init(tone: .critical, remaining: 0, title: "5시간", resetsAt: observed.addingTimeInterval(3600)),
                                     .init(tone: .plenty, remaining: 0.6, title: "주간", resetsAt: observed.addingTimeInterval(86400 * 3))])
        let before = main.estimated(at: observed.addingTimeInterval(1800), warning: 0.2, critical: 0.05)
        #expect(before == main)   // 아직 리셋 전이면 그대로

        let after = main.estimated(at: observed.addingTimeInterval(7200), warning: 0.2, critical: 0.05)
        #expect(after.isEstimated == true)
        #expect(after.bars[0].remaining == 1)
        #expect(after.remaining == 0.6)   // 주간은 그대로라 가장 빠듯한 건 60%
        #expect(after.level == .normal)
        #expect(after.mood == .joy)
    }

    @Test func estimatesAreNeverRecommended() {
        let empty = row("메인", bars: [.init(tone: .critical, remaining: 0, title: "5시간", resetsAt: observed.addingTimeInterval(3600))])
        let half = row("서브", bars: [.init(tone: .moderate, remaining: 0.4, title: "5시간", resetsAt: observed.addingTimeInterval(86400))])
        let data = WidgetData(updatedAt: observed, palette: .indigo,
                              sections: [.init(id: "claude", title: "Claude", rows: [empty, half])],
                              services: [.init(id: "claude", name: "Claude", best: half, roomyCount: 1, accountCount: 2)],
                              warning: 0.2, critical: 0.05)
        let later = data.estimated(at: observed.addingTimeInterval(7200))
        // 메인은 리셋 예정 시각이 지났을 뿐 확인 전이라 추천하지 않고, 확인된 서브를 그대로 권한다.
        #expect(later.services[0].best?.label == "서브")
        #expect(later.sections[0].rows[0].isEstimated == true)
        #expect(data.estimated(at: observed.addingTimeInterval(60)) == data)
    }
}

struct LedgerTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    let main = Account(service: .claude, label: "메인")
    let sub = Account(service: .claude, label: "서브")
    let grok = Account(service: .grok, label: "개인")

    @Test func closesCycleOnResetAndCountsExhaustionOnce() {
        var ledger = UsageLedger()
        for (hour, used) in [(0, 0.2), (1, 0.6), (2, 1.0), (3, 1.0), (5, 0.0), (6, 0.3)] {
            ledger.observe(used: used, at: start.addingTimeInterval(Double(hour) * 3600), account: main.id, window: "five_hour")
        }
        #expect(ledger.cycles.map(\.peak) == [1.0])
        #expect(ledger.exhaustions.count == 1)
        #expect(ledger.openPeak(account: main.id, window: "five_hour") == 0.3)
    }

    @Test func seedsFromExistingHistory() {
        var history = UsageHistory()
        for (hour, used) in [(0, 0.5), (1, 0.9), (2, 0.1)] {
            history.record(UsageSnapshot(windows: [UsageWindow(id: "w", title: "주간", used: used)], observedAt: start.addingTimeInterval(Double(hour) * 3600)), for: main.id)
        }
        let ledger = UsageLedger.seeded(from: history)
        #expect(ledger.startedAt == start)
        #expect(ledger.cycles.map(\.peak) == [0.9])
    }

    @Test func reportFindsHeavyIdleAndPattern() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        // 3주 전부터 기록. 메인은 화요일 오후마다 바닥, Grok은 거의 안 씀.
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12))!
        var ledger = UsageLedger()
        let firstDay = calendar.date(byAdding: .day, value: -21, to: now)!
        ledger.observe(used: 0.02, at: firstDay, account: grok.id, window: "week")
        ledger.observe(used: 0.1, at: firstDay, account: sub.id, window: "five_hour")
        var day = firstDay
        while day < now {
            let weekday = calendar.component(.weekday, from: day)
            let at = calendar.date(bySettingHour: weekday == 3 ? 15 : 10, minute: 0, second: 0, of: day)!
            ledger.observe(used: 0.0, at: at.addingTimeInterval(-3600), account: main.id, window: "five_hour")
            ledger.observe(used: weekday == 3 ? 1.0 : 0.85, at: at, account: main.id, window: "five_hour")
            ledger.observe(used: 0.03, at: at, account: grok.id, window: "week")
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        var paid = grok
        paid.subscription = Subscription(amount: 30, currency: "USD")
        let accounts = [main, sub, paid]
        let report = MonthReport.make(accounts: accounts, ledger: ledger, renewal: { _ in nil }, now: now, calendar: calendar)
        #expect(!report.isCollecting)
        #expect(report.idle.map(\.id) == [grok.id])
        #expect((report.usage.first { $0.account.id == main.id }?.utilization ?? 0) > 0.8)
        #expect(report.patterns.first?.weekdays == [3])
        #expect(report.patterns.first?.startHour == 15)
        #expect(report.patterns.first?.alternative?.id == sub.id)
        #expect(report.headline(accounts: accounts) == "구독 1개에 $30. Claude 메인은 꽉 차게 쓰고, Grok은 거의 쓰지 않았어요.")
    }

    @Test func reportSaysCollectingAtFirst() {
        var ledger = UsageLedger()
        ledger.observe(used: 0.5, at: start, account: main.id, window: "w")
        let report = MonthReport.make(accounts: [main], ledger: ledger, renewal: { _ in nil }, now: start.addingTimeInterval(3600))
        #expect(report.isCollecting)
    }

    @Test func josaFollowsLastSound() {
        #expect(Josa.topic("Claude 메인") == "은")
        #expect(Josa.topic("Cursor") == "는")
        #expect(Josa.topic("Grok") == "은")
        #expect(Josa.subject("ChatGPT 개인") == "이")
        #expect(Josa.subject("ChatGPT") == "가")
    }
}

struct DayTimelineTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private func at(_ hour: Double) -> Date {
        calendar.startOfDay(for: Date(timeIntervalSince1970: 1_792_000_000)).addingTimeInterval(hour * 3600)
    }

    private func snapshot(_ used: Double, at hour: Double) -> UsageSnapshot {
        UsageSnapshot(windows: [UsageWindow(id: "five_hour", title: "5시간", used: used)], observedAt: at(hour))
    }

    @Test func findsUseEmptyAndResetSpans() {
        let work = Account(service: .claude, label: "회사")
        var history = UsageHistory()
        // 어제 밤부터 이어진 기록: 9시에 쓰기 시작해 11시에 바닥, 13시에 리셋, 14–15시에 다시 씀.
        for (used, hour) in [(0.2, -1.0), (0.2, 9.0), (0.6, 10.0), (1.0, 11.0), (1.0, 12.0), (0.0, 13.0), (0.0, 14.0), (0.3, 15.0)] {
            history.record(snapshot(used, at: hour), for: work.id)
        }
        let timeline = DayTimeline.make(accounts: [work], history: history, now: at(16), calendar: calendar)
        let row = try! #require(timeline.rows.first)
        #expect(row.used == [DayTimeline.Span(start: at(9), end: at(11)), DayTimeline.Span(start: at(14), end: at(15))])
        #expect(row.empty == [DayTimeline.Span(start: at(11), end: at(13))])
        #expect(row.resets == [at(13)])
        #expect(timeline.position(at(12)) == 0.5)
    }

    @Test func accountStillEmptySinceYesterdayShowsAllDayEmpty() {
        let home = Account(service: .claude, label: "개인")
        var history = UsageHistory()
        history.record(snapshot(1.0, at: -3), for: home.id)
        let timeline = DayTimeline.make(accounts: [home], history: history, now: at(8), calendar: calendar)
        #expect(timeline.rows.first?.empty == [DayTimeline.Span(start: at(0), end: at(8))])
        #expect(timeline.rows.first?.used == [])
    }

    @Test func accountsWithoutHistoryAreLeftOut() {
        let idle = Account(service: .cursor, label: "회사")
        #expect(DayTimeline.make(accounts: [idle], history: UsageHistory(), now: at(8), calendar: calendar).rows.isEmpty)
    }
}

struct RefillTests {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)

    private func row(_ label: String, _ bars: [(Double, TimeInterval?)], problem: String? = nil) -> WidgetData.Row {
        let bars = bars.map { WidgetData.Bar(tone: .plenty, remaining: $0.0, resetsAt: $0.1.map { now.addingTimeInterval($0) }) }
        return WidgetData.Row(id: UUID(), serviceID: "claude", serviceName: "Claude", label: label, plan: nil,
                              remaining: bars.map(\.remaining).min(), level: .normal, bars: bars, isRecommended: false,
                              problem: problem, observedAt: now)
    }

    private func data(_ rows: [WidgetData.Row]) -> WidgetData {
        WidgetData(updatedAt: now, palette: .indigo, sections: [WidgetData.Section(id: "claude", title: "Claude", rows: rows)], services: [])
    }

    @Test func soonestTightAccountFirst() {
        let later = row("회사", [(0.1, 3 * 3600), (0.9, 86400)])
        let sooner = row("개인", [(0.3, 40 * 60), (0.8, 86400)])
        let roomy = row("서브", [(0.9, 600)])
        let refills = data([later, sooner, roomy]).refills(after: now)
        #expect(refills.map(\.row.label) == ["개인", "회사"])
        // 주간 80%가 남아 있어서 리셋 뒤에도 80%까지만 찬다.
        #expect(refills.first?.to == 0.8)
    }

    @Test func waitsForTheWindowThatActuallyBlocksAndSkipsErrors() {
        // 5시간은 10분 뒤 리셋되지만 주간이 2%라 그때는 늘지 않는다. 주간 리셋 때 찬다.
        let blocked = row("회사", [(0.1, 600), (0.02, 5 * 86400)])
        let broken = row("개인", [(0.1, 600)], problem: "확인 필요")
        let refills = data([blocked, broken]).refills(after: now)
        #expect(refills.map(\.row.label) == ["회사"])
        #expect(refills.first?.at == now.addingTimeInterval(5 * 86400))
    }

    @Test func refillTextCountsDown() {
        #expect(RefillText.until(now.addingTimeInterval(40 * 60), now: now) == "40분 뒤")
        #expect(RefillText.until(now.addingTimeInterval(170 * 60), now: now) == "2시간 50분 뒤")
        #expect(RefillText.until(now.addingTimeInterval(27 * 3600), now: now) == "1일 3시간 뒤")
    }
}
