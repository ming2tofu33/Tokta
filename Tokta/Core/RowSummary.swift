import Foundation

/// 메뉴에서 계정 한 줄에 보여줄 요약. 가장 빠듯한 구간의 남은 비율과, 지금 쓰는 데 걸리는 일이 있으면 그 한 가지.
/// 평소 리셋 시각은 줄에 넣지 않는다. 펼치면 구간마다 보인다.
struct RowSummary: Equatable, Sendable {
    enum Notice: Equatable, Sendable {
        /// 다 쓴 구간이 다시 채워질 때까지
        case refillsIn(String)
        /// 다 썼는데 리셋 시각을 모른다
        case exhausted
        /// 이 속도면 바닥날 때까지. `soon`이면 1시간 안
        case runsOutIn(String, soon: Bool)
        /// 마지막으로 읽은 값이 오래됐다
        case stale(String)

        var text: String {
            switch self {
            case .refillsIn(let time): String(localized: "다 썼어요 · \(time) 뒤 다시 쓸 수 있어요")
            case .exhausted: String(localized: "다 썼어요")
            case .runsOutIn(let time, _): String(localized: "이 속도면 \(time) 뒤 바닥")
            case .stale(let age): String(localized: "\(age) 값 · 최신이 아닐 수 있어요")
            }
        }
    }

    var remaining: Double
    var level: StatusLevel
    var notice: Notice?

    /// 우선순위: 오래된 값 → 다 씀 → 소진 예측(가장 이른 것).
    static func make(snapshot: UsageSnapshot, cycles: [String: [UsageSample]], settings: AlertSettings, now: Date) -> RowSummary {
        guard let tightest = snapshot.bottleneck else { return RowSummary(remaining: 1, level: .normal) }
        var summary = RowSummary(remaining: tightest.remaining, level: StatusLevel(remaining: tightest.remaining, settings: settings))
        func until(_ date: Date) -> String {
            let seconds = Int(date.timeIntervalSince(now))
            return seconds > 0 ? DurationText.string(seconds: seconds) : String(localized: "곧")
        }
        if snapshot.isStale(at: now) {
            summary.notice = .stale(AgeText.string(since: snapshot.observedAt, now: now))
        } else if tightest.remaining <= 0 {
            summary.notice = tightest.resetsAt.map { .refillsIn(until($0)) } ?? .exhausted
        } else if let runsOut = snapshot.windows
            .compactMap({ Forecaster.exhaustion(cycle: cycles[$0.id] ?? [], window: $0, observedAt: snapshot.observedAt) })
            .min() {
            summary.notice = .runsOutIn(until(runsOut), soon: runsOut.timeIntervalSince(now) < 3600)
        }
        return summary
    }
}

extension BarTone {
    init(remaining: Double, settings: AlertSettings) {
        switch StatusLevel(remaining: remaining, settings: settings) {
        case .critical: self = .critical
        case .warning: self = .low
        case .normal: self = remaining > Self.plentyAbove ? .plenty : .moderate
        }
    }
}
