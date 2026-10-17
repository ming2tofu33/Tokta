import Foundation

/// 맨 위 카드에 늘 크게 보여줄 것. 서비스를 고정하면 그 서비스 안에서는 계속 추천 계정을,
/// 계정을 고정하면 그 계정을 보여주다가 빠듯해질 때만 다른 계정을 제안한다.
enum CardPin: Hashable, Sendable {
    case service(Service)
    case account(Account.ID)

    /// UserDefaults에 "service:claude", "account:<UUID>"로 저장한다.
    var storageValue: String {
        switch self {
        case .service(let service): "service:\(service.rawValue)"
        case .account(let id): "account:\(id.uuidString)"
        }
    }

    init?(storageValue: String) {
        let parts = storageValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "service": guard let service = Service(rawValue: parts[1]) else { return nil }; self = .service(service)
        case "account": guard let id = UUID(uuidString: parts[1]) else { return nil }; self = .account(id)
        default: return nil
        }
    }
}

/// 메뉴 맨 위 “지금 쓸 계정” 카드 내용. 서비스 하나를 크게, 나머지 서비스는 한 줄씩.
/// 서비스마다 고르는 기준은 `Recommendation`과 같다(가장 빠듯한 구간이 가장 넉넉한 계정, 다 씀·오래된 값·오류 제외).
struct NowPick: Equatable {
    struct Line: Equatable {
        var service: Service
        /// 지금 쓸 수 있는 계정이 없으면 nil.
        var account: Account?
        var remaining: Double?
    }

    /// 크게 보여줄 계정. 보통은 추천 계정, 계정을 고정했으면 그 계정.
    var primary: Account
    /// 아직 못 읽었으면 nil.
    var primaryRemaining: Double?
    /// 같은 서비스에서 그다음으로 쓸 만한 계정. 왜 이 계정인지 비교해서 보여준다.
    var runnerUp: Account?
    var runnerUpRemaining: Double?
    /// 나머지 서비스. 계정 순서에서 서비스가 처음 나오는 순서대로.
    var others: [Line]
    /// 크게 보여주는 것이 사용자가 고정한 것이면 그 고정.
    var pin: CardPin?
    /// 고정한 서비스에 지금 쓸 계정이 없어서 다른 서비스를 크게 보여줄 때 그 서비스.
    var pinnedUnavailable: Service?
    /// 고정한 계정을 지금 쓸 수 없다(다 씀, 오래된 값, 오류, 아직 못 읽음). 열기 버튼은 `switchTo`로 간다.
    var isBlocked = false
    /// 고정한 계정이 빠듯해서 권하는 같은 서비스의 다른 계정.
    var switchTo: Account?
    var switchToRemaining: Double?
    var basis: Basis = .first

    /// 열기 버튼이 여는 계정.
    var openTarget: Account { isBlocked ? switchTo ?? primary : primary }

    /// 카드에 크게 보여줄 “기준 계정”을 왜 골랐는지. 외부 앱에서 실제로 쓰는지는 알 수 없어 “사용 중”이라고 하지 않는다.
    enum Basis: Equatable {
        /// 사용자가 고정한 계정
        case pinned
        /// 그 서비스에서 Tokta로 마지막으로 연 계정
        case recent
        /// 아직 연 적이 없으면 그 서비스의 첫 계정(사용자가 정한 순서)
        case first
    }

    /// 기준 계정. 숫자가 조금 바뀔 때마다 바뀌지 않는다(2026-10-17 기획서 F1).
    /// 고정한 계정 → (고정한 서비스나 마지막으로 연 서비스 안에서) 마지막으로 연 계정 → 그 서비스의 첫 계정.
    /// 기준 계정이 알림 기준선(`warning`) 이하이거나, 1시간 안에 바닥날 것 같거나(`runningOutSoon`), 지금 쓸 수 없을 때만 대안을 권한다.
    /// 대안은 같은 서비스 · 같은 그룹(그룹 없음끼리도 한 그룹) 안에서, 오류·오래된 값·조회 전을 빼고 가장 빠듯한 구간이 가장 넉넉한 계정.
    /// 기준 계정을 쓸 수 있으면 `margin`(10%p) 넘게 더 넉넉할 때만 권한다. 다른 서비스로는 바꾸지 않는다.
    static func make(
        accounts: [Account],
        snapshots: [Account.ID: UsageSnapshot],
        unavailable: Set<Account.ID> = [],
        pin: CardPin? = nil,
        preferred: Service?,
        recentAccounts: [Service: Account.ID] = [:],
        warning: Double = 0.2,
        runningOutSoon: Set<Account.ID> = [],
        margin: Double = 0.1,
        now: Date = .now
    ) -> NowPick? {
        guard !accounts.isEmpty else { return nil }
        var services: [Service] = []
        for account in accounts where !services.contains(account.service) { services.append(account.service) }

        /// 확정 추천에 쓸 수 있는 값이면 가장 빠듯한 구간의 남은 비율.
        func usable(_ account: Account) -> Double? {
            guard !unavailable.contains(account.id), let snapshot = snapshots[account.id], !snapshot.isStale(at: now) else { return nil }
            return snapshot.bottleneck?.remaining
        }
        func best(_ candidates: [Account]) -> (account: Account, remaining: Double)? {
            guard let account = Recommendation.bestAccount(among: candidates, snapshots: snapshots, unavailable: unavailable, now: now),
                  let remaining = snapshots[account.id]?.bottleneck?.remaining else { return nil }
            return (account, remaining)
        }

        let base: Account
        let basis: Basis
        if case .account(let id)? = pin, let pinned = accounts.first(where: { $0.id == id }) {
            base = pinned
            basis = .pinned
        } else {
            var pinnedService: Service?
            if case .service(let service)? = pin, services.contains(service) { pinnedService = service }
            let service = pinnedService ?? preferred.flatMap { services.contains($0) ? $0 : nil } ?? services[0]
            let members = accounts.filter { $0.service == service }
            if let id = recentAccounts[service], let recent = members.first(where: { $0.id == id }) {
                base = recent
                basis = .recent
            } else {
                base = members[0]
                basis = .first
            }
        }

        let remaining = snapshots[base.id]?.bottleneck?.remaining
        let current = usable(base)
        let isBlocked = current == nil || current == 0
        let needsSwitch = isBlocked || (remaining ?? 0) <= warning || runningOutSoon.contains(base.id)

        var switchTo: (account: Account, remaining: Double)?
        if needsSwitch {
            let order = Dictionary(uniqueKeysWithValues: accounts.enumerated().map { ($1.id, $0) })
            let recent = recentAccounts[base.service]
            let candidates = accounts
                .filter { $0.service == base.service && $0.id != base.id && $0.groupID == base.groupID }
                .compactMap { account in usable(account).flatMap { $0 > 0 ? (account: account, remaining: $0) : nil } }
                .sorted { a, b in
                    if a.remaining != b.remaining { return a.remaining > b.remaining }
                    if (a.account.id == recent) != (b.account.id == recent) { return a.account.id == recent }
                    return order[a.account.id, default: 0] < order[b.account.id, default: 0]
                }
            if let top = candidates.first, isBlocked || top.remaining >= (current ?? 0) + margin {
                switchTo = top
            }
        }

        let pinMatches: CardPin? = switch pin {
        case .account(let id)? where id == base.id: pin
        case .service(let service)? where service == base.service: pin
        default: nil
        }
        return NowPick(
            primary: base,
            primaryRemaining: remaining,
            others: services.filter { $0 != base.service }.map { service in
                let pick = best(accounts.filter { $0.service == service })
                return Line(service: service, account: pick?.account, remaining: pick?.remaining)
            },
            pin: pinMatches,
            isBlocked: isBlocked,
            switchTo: switchTo?.account,
            switchToRemaining: switchTo?.remaining,
            basis: basis
        )
    }
}
