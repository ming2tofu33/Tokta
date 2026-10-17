import Foundation

struct UsageSample: Codable, Equatable, Sendable {
    /// 읽은 시각
    var t: Date
    /// 사용한 비율, 0...1
    var u: Double
}

/// 계정 × 구간마다 사용 비율을 시간순으로 모은다. 값이 바뀌었거나 10분이 지났을 때만 남기고 8일만 보관한다.
struct UsageHistory: Codable, Equatable, Sendable {
    private(set) var series: [String: [UsageSample]] = [:]

    static let keepFor: TimeInterval = 8 * 86400
    static let minInterval: TimeInterval = 10 * 60
    /// 이보다 작은 변화는 같은 값으로 본다. 이만큼 줄어들면 리셋으로 본다.
    static let minChange = 0.005

    static func key(_ account: Account.ID, _ window: String) -> String { "\(account.uuidString)|\(window)" }

    mutating func record(_ snapshot: UsageSnapshot, for account: Account.ID) {
        for window in snapshot.windows {
            let key = Self.key(account, window.id)
            var samples = series[key] ?? []
            let sample = UsageSample(t: snapshot.observedAt, u: (window.used * 10_000).rounded() / 10_000)
            if let last = samples.last {
                guard sample.t > last.t else { continue }
                if abs(sample.u - last.u) < Self.minChange, sample.t.timeIntervalSince(last.t) < Self.minInterval { continue }
            }
            samples.append(sample)
            samples.removeAll { snapshot.observedAt.timeIntervalSince($0.t) > Self.keepFor }
            series[key] = samples
        }
    }

    mutating func remove(account: Account.ID) {
        series = series.filter { !$0.key.hasPrefix(account.uuidString) }
    }

    /// 마지막 리셋(사용 비율이 뚝 떨어진 지점) 이후의 기록.
    func currentCycle(account: Account.ID, window: String) -> [UsageSample] {
        var cycle: [UsageSample] = []
        for sample in series[Self.key(account, window)] ?? [] {
            if let last = cycle.last, sample.u < last.u - Self.minChange { cycle = [] }
            cycle.append(sample)
        }
        return cycle
    }

    /// 가장 최근에 리셋(사용 비율이 뚝 떨어짐)이 보인 시각. 기록 안에서 리셋이 없었으면 nil.
    func lastReset(account: Account.ID, window: String) -> Date? {
        var previous: UsageSample?
        var reset: Date?
        for sample in series[Self.key(account, window)] ?? [] {
            if let previous, sample.u < previous.u - Self.minChange { reset = sample.t }
            previous = sample
        }
        return reset
    }
}

enum Forecaster {
    /// 지금 주기의 최근 사용 속도가 그대로 이어지면 다 쓰는 시각. 리셋 전에 바닥나지 않으면 nil.
    /// 최근 = 5시간 구간은 1시간, 그보다 긴 구간은 하루. 15분 넘게 쌓인 기록이 있어야 계산한다.
    static func exhaustion(cycle: [UsageSample], window: UsageWindow, observedAt: Date) -> Date? {
        var points = cycle
        if observedAt > (points.last?.t ?? .distantPast) { points.append(UsageSample(t: observedAt, u: window.used)) }
        guard let latest = points.last, latest.u < 1 else { return nil }
        let lookback: TimeInterval = isShortWindow(window) ? 3600 : 86400
        let recent = points.filter { latest.t.timeIntervalSince($0.t) <= lookback }
        guard let first = recent.first, latest.t.timeIntervalSince(first.t) >= 15 * 60, latest.u > first.u else { return nil }
        let rate = (latest.u - first.u) / latest.t.timeIntervalSince(first.t)
        let exhausts = latest.t.addingTimeInterval((1 - latest.u) / rate)
        if let reset = window.resetsAt, exhausts >= reset { return nil }
        return exhausts
    }

    static func isShortWindow(_ window: UsageWindow) -> Bool {
        window.id == "five_hour" || window.id == "300m"
    }
}
