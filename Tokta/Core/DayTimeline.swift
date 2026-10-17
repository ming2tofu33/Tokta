import Foundation

/// Tokta 창 “오늘 하루”: 계정마다 오늘 언제 썼고, 언제 바닥이었고, 언제 리셋됐는지.
/// 사용 기록(`UsageHistory`)에서 뽑는다. 기록은 값이 바뀔 때마다 남으므로, 두 기록 사이에 사용 비율이 올랐으면 그동안 쓴 것으로 본다.
struct DayTimeline: Equatable {
    struct Span: Equatable {
        var start: Date
        var end: Date
    }

    struct Row: Equatable {
        var account: Account
        var used: [Span]
        /// 어느 구간이든 다 써서 막혀 있던 때.
        var empty: [Span]
        var resets: [Date]
    }

    var start: Date
    var end: Date
    var now: Date
    var rows: [Row]

    /// 하루 중 `date`의 위치(0...1).
    func position(_ date: Date) -> Double {
        min(1, max(0, date.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }

    /// 다 쓴 것으로 보는 사용 비율.
    static let fullAbove = 0.995

    static func make(accounts: [Account], history: UsageHistory, now: Date = .now, calendar: Calendar = .current) -> DayTimeline {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        let rows = accounts.compactMap { account -> Row? in
            var used: [Span] = [], empty: [Span] = [], resets: [Date] = []
            var touched = false
            for (key, samples) in history.series where key.hasPrefix(account.id.uuidString + "|") {
                // 오늘 첫 기록 바로 앞 기록부터 봐야 자정을 넘긴 구간이 이어진다.
                guard let firstToday = samples.firstIndex(where: { $0.t >= start }) else {
                    if let last = samples.last, last.u >= fullAbove { empty.append(Span(start: start, end: now)); touched = true }
                    continue
                }
                touched = true
                let from = max(0, firstToday - 1)
                for index in from..<samples.count {
                    let sample = samples[index]
                    let next = index + 1 < samples.count ? samples[index + 1] : nil
                    let spanEnd = next?.t ?? now
                    if sample.u >= fullAbove { empty.append(Span(start: sample.t, end: spanEnd)) }
                    guard let next else { continue }
                    if next.u > sample.u + UsageHistory.minChange { used.append(Span(start: sample.t, end: next.t)) }
                    if next.u < sample.u - UsageHistory.minChange, next.t >= start, next.t <= now { resets.append(next.t) }
                }
            }
            guard touched else { return nil }
            return Row(account: account, used: merge(used, from: start, to: now), empty: merge(empty, from: start, to: now), resets: resets.sorted())
        }
        return DayTimeline(start: start, end: end, now: now, rows: rows)
    }

    /// 오늘 안으로 자르고, 겹치거나 맞닿은 구간을 합친다.
    static func merge(_ spans: [Span], from start: Date, to end: Date) -> [Span] {
        let clipped = spans
            .map { Span(start: max($0.start, start), end: min($0.end, end)) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        var merged: [Span] = []
        for span in clipped {
            if let last = merged.last, span.start <= last.end {
                merged[merged.count - 1].end = max(last.end, span.end)
            } else {
                merged.append(span)
            }
        }
        return merged
    }
}
