import Foundation

/// “다음에 차는 계정” 위젯. 위젯 파일에 이미 있는 구간별 리셋 시각만으로 계산해서 앱이 쓰는 파일 모양은 그대로다.
extension WidgetData {
    struct Refill: Equatable, Sendable {
        var row: Row
        /// 가장 빠듯한 구간이 리셋되는 시각.
        var at: Date
        /// 그때 남을 양. 그 전에 리셋되지 않는 다른 구간이 더 빠듯하면 그 값.
        var to: Double
    }

    /// 지금 빠듯하고(절반 이하) 곧 다시 차는 계정을 리셋이 빠른 순으로. 오류가 붙은 계정과
    /// 리셋돼도 거의 늘지 않는 계정(다른 구간이 막고 있음)은 뺀다.
    func refills(after now: Date, limit: Int = 3) -> [Refill] {
        let refills = sections.flatMap(\.rows).compactMap { row -> Refill? in
            guard row.problem == nil, let remaining = row.remaining, remaining <= 0.5,
                  let tightest = row.bars.min(by: { $0.remaining < $1.remaining }),
                  let at = tightest.resetsAt, at > now else { return nil }
            let to = row.bars.map { bar in (bar.resetsAt.map { $0 <= at } ?? false) ? 1 : bar.remaining }.min() ?? 1
            guard to >= remaining + 0.1 else { return nil }
            return Refill(row: row, at: at, to: to)
        }
        return Array(refills.sorted { $0.at < $1.at }.prefix(limit))
    }
}

/// 위젯용 남은 시간 문구. "40분 뒤", "2시간 50분 뒤", "1일 3시간 뒤".
enum RefillText {
    static func until(_ date: Date, now: Date) -> String {
        let minutes = max(1, Int(date.timeIntervalSince(now) / 60))
        let days = minutes / 1440, hours = minutes % 1440 / 60, mins = minutes % 60
        if days > 0 { return String(localized: "\(days)일 \(hours)시간 뒤") }
        if hours > 0 { return mins > 0 ? String(localized: "\(hours)시간 \(mins)분 뒤") : String(localized: "\(hours)시간 뒤") }
        return String(localized: "\(mins)분 뒤")
    }
}
