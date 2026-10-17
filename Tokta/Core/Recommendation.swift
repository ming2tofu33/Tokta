import Foundation

enum Recommendation {
    /// 같은 서비스 계정 중 지금 쓰기 가장 좋은 계정.
    /// 각 계정의 병목 구간 남은 비율을 비교한다. 다 쓴 계정, 아직 조회 전인 계정, 값이 오래된 계정,
    /// 오류가 난 계정(`unavailable`: 로그인 풀림, 다른 이메일로 로그인, 이미 추가한 계정과 같은 로그인 등)은 뺀다.
    /// 마지막으로 읽은 값이 남아 있어도 지금 그 계정을 쓸 수 있다는 보장이 없어서다.
    static func bestAccount(
        among accounts: [Account],
        snapshots: [Account.ID: UsageSnapshot],
        unavailable: Set<Account.ID> = [],
        now: Date = .now
    ) -> Account? {
        accounts
            .compactMap { account -> (Account, Double)? in
                guard !unavailable.contains(account.id),
                      let snapshot = snapshots[account.id], !snapshot.isStale(at: now),
                      let remaining = snapshot.bottleneck?.remaining, remaining > 0 else { return nil }
                return (account, remaining)
            }
            .max { $0.1 < $1.1 }?
            .0
    }
}

enum AgeText {
    static func string(since date: Date, now: Date = .now) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date)) / 60)
        if minutes < 1 { return String(localized: "방금") }
        if minutes < 60 { return String(localized: "\(minutes)분 전") }
        if minutes < 1440 { return String(localized: "\(minutes / 60)시간 전") }
        return String(localized: "\(minutes / 1440)일 전")
    }
}

enum DurationText {
    /// "2일 5시간", "3시간 10분", "45분". 1분보다 짧으면 "1분".
    static func string(seconds: Int) -> String {
        let minutes = max(seconds, 60) / 60
        let days = minutes / 1440, hours = minutes % 1440 / 60, mins = minutes % 60
        if days > 0 { return hours > 0 ? String(localized: "\(days)일 \(hours)시간") : String(localized: "\(days)일") }
        if hours > 0 { return mins > 0 ? String(localized: "\(hours)시간 \(mins)분") : String(localized: "\(hours)시간") }
        return String(localized: "\(mins)분")
    }
}

enum ResetText {
    static func string(until date: Date, now: Date = .now) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return String(localized: "곧 리셋") }
        return String(localized: "\(DurationText.string(seconds: seconds)) 후 리셋")
    }
}

/// 앱 언어에 맞춘 날짜 문구. 한국어는 예전 모양 그대로("목 오후 3:00", "10월 20일").
enum LocalDate {
    private static var isKorean: Bool { Bundle.main.preferredLocalizations.first?.hasPrefix("ko") ?? true }

    static func weekdayTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        if isKorean {
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = "E a h:mm"
        } else {
            formatter.locale = Locale(identifier: "en_US")
            formatter.setLocalizedDateFormatFromTemplate("EEE j:mm")
        }
        return formatter.string(from: date)
    }

    /// "오후 3:20", "3:20 PM"
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        if isKorean {
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = "a h:mm"
        } else {
            formatter.locale = Locale(identifier: "en_US")
            formatter.setLocalizedDateFormatFromTemplate("j:mm")
        }
        return formatter.string(from: date)
    }

    static func monthDay(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if isKorean {
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = "M월 d일"
        } else {
            formatter.locale = Locale(identifier: "en_US")
            formatter.setLocalizedDateFormatFromTemplate("MMM d")
        }
        return formatter.string(from: date)
    }
}

enum ForecastText {
    /// 하루 안이면 남은 시간, 그보다 멀면 요일과 시각.
    static func string(exhaustsAt: Date, now: Date = .now) -> String {
        let seconds = Int(exhaustsAt.timeIntervalSince(now))
        guard seconds > 60 else { return String(localized: "이 속도면 곧 바닥") }
        if seconds < 86400 { return String(localized: "이 속도면 \(DurationText.string(seconds: seconds)) 뒤 바닥") }
        return String(localized: "이 속도면 \(LocalDate.weekdayTime(exhaustsAt))쯤 바닥")
    }
}
