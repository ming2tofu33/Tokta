import Foundation

/// 계정 하나의 구독료와 결제 주기. 결제일은 지난 날이든 다음 날이든 하나만 알면 다음 결제일을 계산한다.
struct Subscription: Codable, Hashable, Sendable {
    enum Cycle: String, Codable, CaseIterable, Hashable, Sendable {
        case monthly, yearly

        var label: String { self == .monthly ? String(localized: "월") : String(localized: "년") }
        var months: Int { self == .monthly ? 1 : 12 }
    }

    static let currencies = ["USD", "KRW"]

    var amount: Decimal
    var currency = "USD"
    var cycle = Cycle.monthly
    /// 결제가 일어난(또는 일어날) 어느 하루. nil이면 서비스에서 가져온 결제일을 쓴다.
    var anchor: Date?

    /// 오늘 또는 그 뒤의 첫 결제일(그날 0시). 1월 31일처럼 짧은 달에 없는 날은 그달 마지막 날로 맞춘다.
    func nextRenewal(onOrAfter now: Date, calendar: Calendar = .current) -> Date? {
        guard let anchor else { return nil }
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: anchor)
        // 결제일이 아주 먼 과거여도 바로 근처에서 찾도록 대략 건너뛴다.
        let elapsed = calendar.dateComponents([.month], from: start, to: today).month ?? 0
        var step = max(0, elapsed / cycle.months - 1)
        while true {
            let date = calendar.date(byAdding: .month, value: step * cycle.months, to: start) ?? start
            if date >= today { return date }
            step += 1
        }
    }

    /// 매년 결제는 12로 나눠 월 금액으로 본다.
    var monthlyAmount: Decimal { cycle == .monthly ? amount : amount / 12 }
}

/// 서비스가 알려준 다음 결제 정보. 금액은 대부분 알려주지 않는다.
struct DetectedBilling: Codable, Hashable, Sendable {
    var nextCharge: Date
    var cycle: Subscription.Cycle?
    var currency: String?
    /// 해지해서 이 날 구독이 끝나면 값이 있다. 그러면 결제가 아니라 종료다.
    var endsAt: Date?
    /// 같은 조직(예: Claude Team)의 계정들은 결제일이 하나다. 일반 멤버는 결제 정보를 못 보므로 관리자 계정 값을 같이 쓴다.
    var organizationID: String?
}

/// 카드·구독 탭·알림이 쓰는 실제 다음 결제일. 직접 적은 결제일이 서비스에서 가져온 것보다 우선한다.
struct Renewal: Equatable, Sendable {
    var date: Date
    var isDetected: Bool
    var isEnding: Bool

    static func resolve(subscription: Subscription?, detected: DetectedBilling?, now: Date, calendar: Calendar = .current) -> Renewal? {
        if let manual = subscription?.nextRenewal(onOrAfter: now, calendar: calendar) {
            return Renewal(date: manual, isDetected: false, isEnding: false)
        }
        if let detected, let ends = detected.endsAt, ends >= calendar.startOfDay(for: now) {
            return Renewal(date: calendar.startOfDay(for: ends), isDetected: true, isEnding: true)
        }
        if let detected, detected.nextCharge >= calendar.startOfDay(for: now) {
            return Renewal(date: calendar.startOfDay(for: detected.nextCharge), isDetected: true, isEnding: false)
        }
        return nil
    }
}

enum MoneyText {
    static func string(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        // USD는 "$200", KRW는 "₩29,000"처럼 익숙한 모양으로.
        formatter.locale = Locale(identifier: currency == "KRW" ? "ko_KR" : "en_US")
        let whole = amount == Decimal(Int(truncating: amount as NSNumber))
        formatter.minimumFractionDigits = whole || currency == "KRW" ? 0 : 2
        formatter.maximumFractionDigits = currency == "KRW" ? 0 : 2
        return formatter.string(from: amount as NSNumber) ?? "\(amount) \(currency)"
    }

    /// 통화별 월 합계. 환율은 쓰지 않는다. 예: "$420 · ₩29,000"
    static func monthlyTotal(_ subscriptions: [Subscription]) -> String? {
        let totals = Dictionary(grouping: subscriptions, by: \.currency).mapValues { $0.reduce(Decimal(0)) { $0 + $1.monthlyAmount } }
        guard !totals.isEmpty else { return nil }
        return Subscription.currencies.filter { totals[$0] != nil }
            .map { string(totals[$0]!, currency: $0) }
            .joined(separator: " · ")
    }
}

enum RenewalText {
    /// "10월 20일 결제 (D-7)", "내일 결제", "오늘 결제". 해지한 구독은 "결제" 대신 "구독 종료".
    static func string(_ date: Date, now: Date = .now, ending: Bool = false, calendar: Calendar = .current) -> String {
        let what = ending ? String(localized: "구독 종료") : String(localized: "결제")
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<1: return String(localized: "오늘 \(what)")
        case 1: return String(localized: "내일 \(what)")
        default:
            return String(localized: "\(LocalDate.monthDay(date, calendar: calendar)) \(what) (D-\(days))")
        }
    }

    static func string(_ renewal: Renewal, now: Date = .now) -> String {
        string(renewal.date, now: now, ending: renewal.isEnding)
    }
}
