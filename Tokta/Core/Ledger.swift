import Foundation

/// 한 달 넘게 남기는 요약 기록. 자세한 사용 기록(`UsageHistory`)은 8일만 두므로,
/// 주기가 끝날 때(리셋) 그 주기에 가장 많이 쓴 비율과, 한도가 바닥난 순간만 따로 모은다.
struct UsageLedger: Codable, Equatable, Sendable {
    struct Cycle: Codable, Equatable, Sendable {
        var account: Account.ID
        var window: String
        /// 리셋이 보인 시각(그 주기의 끝).
        var end: Date
        /// 그 주기에 가장 많이 쓴 비율, 0...1
        var peak: Double
    }

    struct Exhaustion: Codable, Equatable, Sendable {
        var account: Account.ID
        var window: String
        var at: Date
    }

    static let keepFor: TimeInterval = 400 * 86400
    /// 이만큼 쓰면 바닥으로 본다.
    static let exhaustedAt = 0.995

    /// 기록을 모으기 시작한 시각. “지난달보다” 같은 비교는 그 달 기록이 다 있을 때만 한다.
    var startedAt: Date?
    private(set) var cycles: [Cycle] = []
    private(set) var exhaustions: [Exhaustion] = []
    /// 계정|구간마다 지금 주기에 가장 많이 쓴 비율과 마지막 값.
    private var open: [String: OpenCycle] = [:]

    private struct OpenCycle: Codable, Equatable, Sendable {
        var peak: Double
        var last: Double
        var since: Date
    }

    /// 새로 읽은 값을 반영한다. 사용 비율이 뚝 떨어지면 리셋으로 보고 그 주기를 닫는다.
    mutating func observe(_ snapshot: UsageSnapshot, for account: Account.ID) {
        for window in snapshot.windows {
            observe(used: window.used, at: snapshot.observedAt, account: account, window: window.id)
        }
        let cutoff = snapshot.observedAt.addingTimeInterval(-Self.keepFor)
        cycles.removeAll { $0.end < cutoff }
        exhaustions.removeAll { $0.at < cutoff }
    }

    mutating func observe(used: Double, at time: Date, account: Account.ID, window: String) {
        if startedAt.map({ time < $0 }) ?? true { startedAt = time }
        let key = UsageHistory.key(account, window)
        guard var state = open[key] else {
            open[key] = OpenCycle(peak: used, last: used, since: time)
            if used >= Self.exhaustedAt { exhaustions.append(Exhaustion(account: account, window: window, at: time)) }
            return
        }
        if used < state.last - UsageHistory.minChange {
            cycles.append(Cycle(account: account, window: window, end: time, peak: state.peak))
            state = OpenCycle(peak: used, last: used, since: time)
        } else {
            if used >= Self.exhaustedAt && state.last < Self.exhaustedAt {
                exhaustions.append(Exhaustion(account: account, window: window, at: time))
            }
            state.peak = max(state.peak, used)
            state.last = used
        }
        open[key] = state
    }

    var openKeys: [String] { Array(open.keys) }

    /// 지금 주기에 가장 많이 쓴 비율.
    func openPeak(account: Account.ID, window: String) -> Double? {
        open[UsageHistory.key(account, window)]?.peak
    }

    mutating func remove(account: Account.ID) {
        cycles.removeAll { $0.account == account }
        exhaustions.removeAll { $0.account == account }
        open = open.filter { !$0.key.hasPrefix(account.uuidString) }
    }

    /// 요약 기록이 없을 때(이 기능 전 설치본) 남아 있는 8일 기록으로 채운다.
    static func seeded(from history: UsageHistory) -> UsageLedger {
        var ledger = UsageLedger()
        for (key, samples) in history.series {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let account = UUID(uuidString: parts[0]) else { continue }
            for sample in samples {
                ledger.observe(used: sample.u, at: sample.t, account: account, window: parts[1])
            }
        }
        ledger.cycles.sort { $0.end < $1.end }
        ledger.exhaustions.sort { $0.at < $1.at }
        return ledger
    }
}
