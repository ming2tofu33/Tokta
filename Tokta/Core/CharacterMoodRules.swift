import Foundation

extension CharacterMood {
    /// 방금 리셋됐다고 보는 시간. 이 안이면 ^o^.
    static let joyAfterReset: TimeInterval = 30 * 60

    /// 단계와 같은 기준으로 표정을 고른다.
    /// 못 읽었거나 쓸 수 없으면 •_•, 다 쓰면 -_-, 방금 리셋 ^o^, 알림 기준선 아래거나 1시간 안에 바닥나면 >_<, 절반 넘게 남으면 ^_^.
    static func of(remaining: Double?, settings: AlertSettings, notice: RowSummary.Notice? = nil, isUnavailable: Bool = false, justReset: Bool = false) -> CharacterMood {
        guard let remaining, !isUnavailable else { return .calm }
        if remaining <= 0 { return .sleep }
        if case .exhausted? = notice { return .sleep }
        if case .refillsIn? = notice { return .sleep }
        if justReset { return .joy }
        if StatusLevel(remaining: remaining, settings: settings) != .normal { return .squeeze }
        if case .runsOutIn(_, true)? = notice { return .squeeze }
        return remaining > BarTone.plentyAbove ? .happy : .calm
    }
}

extension UsageStore {
    /// 이 계정의 어느 구간이든 최근 30분 안에 리셋됐는지.
    func justReset(_ account: Account, now: Date = .now) -> Bool {
        (snapshots[account.id]?.windows ?? []).contains { window in
            history.lastReset(account: account.id, window: window.id).map { now.timeIntervalSince($0) < CharacterMood.joyAfterReset } ?? false
        }
    }

    /// 계정 하나의 표정. 메뉴 카드와 위젯이 같이 쓴다.
    func mood(for account: Account, now: Date = .now) -> CharacterMood {
        let snapshot = snapshots[account.id]
        let notice = snapshot.map { RowSummary.make(snapshot: $0, cycles: cycles(for: account), settings: alertSettings, now: now).notice }
        let unavailable = errors[account.id] != nil || (snapshot?.isStale(at: now) ?? false)
        return CharacterMood.of(remaining: snapshot?.bottleneck?.remaining, settings: alertSettings, notice: notice ?? nil, isUnavailable: unavailable, justReset: justReset(account, now: now))
    }

    func cycles(for account: Account) -> [String: [UsageSample]] {
        Dictionary(uniqueKeysWithValues: (snapshots[account.id]?.windows ?? []).map { ($0.id, cycle(for: account.id, window: $0)) })
    }

    /// 메뉴바 캐릭터: 메뉴바 숫자와 같은 값(서비스마다 가장 여유 있는 계정 중 가장 빠듯한 값)으로 고른다.
    var menuBarCharacter: (mood: CharacterMood, tone: BarTone, remaining: Double)? {
        guard let remaining = menuBarRemaining else { return nil }
        return (CharacterMood.of(remaining: remaining, settings: alertSettings), BarTone(remaining: remaining, settings: alertSettings), remaining)
    }
}
