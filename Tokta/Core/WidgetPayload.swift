import Foundation

extension WidgetData {
    /// 지금 앱 상태로 위젯 내용을 만든다. 추천·색 단계·오류 판단은 메뉴와 같은 기준이다.
    @MainActor
    static func build(from store: UsageStore, palette: UsagePalette, now: Date = .now) -> WidgetData {
        let recommended = store.recommendedAccountIDs
        let settings = store.alertSettings

        func row(_ account: Account) -> Row {
            let snapshot = store.snapshots[account.id]
            let remaining = snapshot?.bottleneck?.remaining
            return Row(
                id: account.id,
                serviceID: account.service.rawValue,
                serviceName: account.service.displayName,
                label: account.displayLabel,
                plan: snapshot?.plan,
                remaining: remaining,
                level: remaining.map { StatusLevel(remaining: $0, settings: settings) } ?? .normal,
                bars: (snapshot?.windows ?? []).prefix(3).map { Bar(tone: BarTone(remaining: $0.remaining, settings: settings), remaining: $0.remaining, title: $0.title, resetsAt: $0.resetsAt) },
                isRecommended: recommended.contains(account.id),
                problem: store.errors[account.id] == nil ? nil : String(localized: "확인 필요"),
                observedAt: snapshot?.observedAt,
                mood: store.mood(for: account, now: now)
            )
        }

        let sections = store.sections.map { Section(id: $0.id, title: $0.title, rows: $0.accounts.map(row)) }
        let services = store.activeServices.map { service -> Service in
            let accounts = store.accounts(for: service)
            // 계정이 하나면 그 계정을, 여럿이면 메뉴와 같은 추천 계정을 보여준다.
            let best = accounts.count == 1 ? accounts.first : accounts.first { recommended.contains($0.id) }
            let roomy = accounts.filter { account in
                guard store.errors[account.id] == nil, let snapshot = store.snapshots[account.id], !snapshot.isStale(at: now),
                      let remaining = snapshot.bottleneck?.remaining else { return false }
                return remaining > settings.warning
            }
            return Service(id: service.rawValue, name: service.displayName, best: best.map(row), roomyCount: roomy.count, accountCount: accounts.count)
        }
        return WidgetData(updatedAt: now, palette: palette, sections: sections, services: services, warning: settings.warning, critical: settings.critical, alerts: store.phoneAlerts)
    }
}
