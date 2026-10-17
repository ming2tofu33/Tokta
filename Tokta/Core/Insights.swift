import Foundation

/// 문장에 넣는 계정 이름. 그 서비스 계정이 하나뿐이거나 이름이 서비스와 같으면 서비스 이름만.
enum AccountName {
    static func short(_ account: Account, among accounts: [Account]) -> String {
        let label = account.displayLabel
        let alone = accounts.filter { $0.service == account.service }.count <= 1
        if alone || label.caseInsensitiveCompare(account.service.displayName) == .orderedSame || label == String(localized: "기본") {
            return account.service.displayName
        }
        return "\(account.service.displayName) \(label)"
    }
}

/// Tokta 창 “이번 달”. 요약 기록(`UsageLedger`)과 구독료로 계산한다.
struct MonthReport: Equatable {
    struct Usage: Equatable {
        var account: Account
        /// 받은 한도 중 쓴 비율. 계정의 구간마다 주기별 최고 사용 비율을 평균 내고, 그중 가장 높은 구간. 기록이 없으면 nil.
        var utilization: Double?
        var exhaustions: Int
    }

    struct Pattern: Equatable {
        var account: Account
        /// 1 = 일요일 … 7 = 토요일 (`Calendar.weekday`)
        var weekdays: [Int]
        var startHour: Int
        /// 이 시각 전까지(제외).
        var endHour: Int
        var alternative: Account?
    }

    var periodStart: Date
    /// 기록을 모은 지 3일이 안 됐으면 해석 대신 “모으는 중”을 보여준다.
    var isCollecting: Bool
    var collectedDays: Int
    var subscribed: [Account]
    var nextRenewal: (account: Account, renewal: Renewal)?
    var exhaustedThisMonth: Int
    /// 지난달 기록이 다 있을 때만.
    var exhaustedLastMonth: Int?
    var usage: [Usage]
    var idle: [Account]
    /// 거의 안 쓰는 구독을 가늠할 때 본 기간(일).
    var idleDays: Int
    var patterns: [Pattern]

    static func == (a: MonthReport, b: MonthReport) -> Bool {
        a.periodStart == b.periodStart && a.isCollecting == b.isCollecting && a.usage == b.usage && a.idle == b.idle
            && a.patterns == b.patterns && a.exhaustedThisMonth == b.exhaustedThisMonth && a.exhaustedLastMonth == b.exhaustedLastMonth
            && a.subscribed == b.subscribed && a.nextRenewal?.account == b.nextRenewal?.account && a.nextRenewal?.renewal == b.nextRenewal?.renewal
    }

    static let idleBelow = 0.1
    static let heavyAbove = 0.8

    static func make(
        accounts: [Account],
        ledger: UsageLedger,
        renewal: (Account) -> Renewal?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> MonthReport {
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let started = ledger.startedAt ?? now
        let collectedDays = max(0, Int(now.timeIntervalSince(started) / 86400))

        // 같은 Cursor 계정에 딸린 Grok Bot처럼 결제가 따로 없는 계정도 사용량에는 넣는다.
        let usage: [Usage] = accounts.map { account in
            let windows = Set(ledger.cycles.filter { $0.account == account.id }.map(\.window))
                .union(ledger.exhaustions.filter { $0.account == account.id }.map(\.window))
            var best: Double?
            for window in windows.union(openWindows(ledger, account)) {
                let peaks = ledger.cycles.filter { $0.account == account.id && $0.window == window && $0.end >= monthStart }.map(\.peak)
                let values = peaks.isEmpty ? ledger.openPeak(account: account.id, window: window).map { [$0] } ?? [] : peaks
                guard !values.isEmpty else { continue }
                let average = values.reduce(0, +) / Double(values.count)
                best = max(best ?? 0, average)
            }
            let count = ledger.exhaustions.filter { $0.account == account.id && $0.at >= monthStart }.count
            return Usage(account: account, utilization: best, exhaustions: count)
        }

        let idleDays = min(14, collectedDays)
        let idleSince = now.addingTimeInterval(-Double(idleDays) * 86400)
        let idle: [Account] = collectedDays < 7 ? [] : accounts.filter { account in
            let recentPeaks = ledger.cycles.filter { $0.account == account.id && $0.end >= idleSince }.map(\.peak)
            let openPeaks = openWindows(ledger, account).compactMap { ledger.openPeak(account: account.id, window: $0) }
            let all = recentPeaks + openPeaks
            return !all.isEmpty && all.allSatisfy { $0 < idleBelow }
        }

        let recentExhaustions = ledger.exhaustions.filter { now.timeIntervalSince($0.at) <= 30 * 86400 }
        let patterns: [Pattern] = accounts.compactMap { account in
            let events = recentExhaustions.filter { $0.account == account.id }
            guard events.count >= 3 else { return nil }
            let byDay = Dictionary(grouping: events) { calendar.component(.weekday, from: $0.at) }
            let days = byDay.filter { $0.value.count >= 2 }.sorted { $0.value.count > $1.value.count }.prefix(3).map(\.key).sorted()
            guard !days.isEmpty else { return nil }
            let hours = events.filter { days.contains(calendar.component(.weekday, from: $0.at)) }.map { calendar.component(.hour, from: $0.at) }
            guard let low = hours.min(), let high = hours.max() else { return nil }
            let others = accounts.filter { $0.service == account.service && $0.id != account.id }
            let alternative = others.max { a, b in
                (usage.first { $0.account == a }?.utilization ?? 1) > (usage.first { $0.account == b }?.utilization ?? 1)
            }
            return Pattern(account: account, weekdays: days, startHour: low, endHour: min(24, high + 1), alternative: alternative)
        }

        let subscribed = accounts.filter { $0.subscription != nil }
        let next = accounts.compactMap { account in renewal(account).map { (account: account, renewal: $0) } }
            .filter { !$0.renewal.isEnding }
            .min { $0.renewal.date < $1.renewal.date }

        let exhaustedLast: Int? = started <= lastMonthStart
            ? ledger.exhaustions.filter { $0.at >= lastMonthStart && $0.at < monthStart }.count
            : nil

        return MonthReport(
            periodStart: monthStart,
            isCollecting: collectedDays < 3,
            collectedDays: collectedDays,
            subscribed: subscribed,
            nextRenewal: next,
            exhaustedThisMonth: ledger.exhaustions.filter { $0.at >= monthStart }.count,
            exhaustedLastMonth: exhaustedLast,
            usage: usage,
            idle: idle,
            idleDays: idleDays,
            patterns: patterns
        )
    }

    private static func openWindows(_ ledger: UsageLedger, _ account: Account) -> [String] {
        ledger.openWindows(account: account.id)
    }

    /// 맨 위 한 문장.
    func headline(accounts: [Account]) -> String {
        if isCollecting { return String(localized: "기록을 모으는 중이에요. 며칠 쓰면 여기서 이번 달을 정리해 드려요.") }
        var parts: [String] = []
        if let total = MoneyText.monthlyTotal(subscribed.compactMap(\.subscription)) {
            parts.append(String(localized: "구독 \(subscribed.count)개에 \(total)."))
        }
        let heavy = usage.filter { ($0.utilization ?? 0) >= Self.heavyAbove }.max { ($0.utilization ?? 0) < ($1.utilization ?? 0) }?.account
        let idleOne = idle.first
        switch (heavy, idleOne) {
        case let (heavy?, idle?):
            let h = AccountName.short(heavy, among: accounts), i = AccountName.short(idle, among: accounts)
            parts.append(String(localized: "\(h)\(Josa.topic(h)) 꽉 차게 쓰고, \(i)\(Josa.topic(i)) 거의 쓰지 않았어요."))
        case let (heavy?, nil):
            let h = AccountName.short(heavy, among: accounts)
            parts.append(String(localized: "\(h)\(Josa.subject(h)) 한도를 가장 꽉 채워 쓰고 있어요."))
        case let (nil, idle?):
            let i = AccountName.short(idle, among: accounts)
            parts.append(String(localized: "\(i)\(Josa.topic(i)) 거의 쓰지 않았어요."))
        case (nil, nil):
            parts.append(String(localized: "한도를 무리 없이 고르게 쓰고 있어요."))
        }
        return parts.joined(separator: " ")
    }
}

extension UsageLedger {
    /// 지금 주기가 열려 있는 구간.
    func openWindows(account: Account.ID) -> [String] {
        openKeys.filter { $0.hasPrefix(account.uuidString + "|") }.compactMap { $0.split(separator: "|", maxSplits: 1).last.map(String.init) }
    }
}
