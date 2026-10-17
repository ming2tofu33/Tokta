import UserNotifications

/// 맥이 정해서 넘겨준 알림을 iPhone에서 보낸다. 판단은 하지 않는다.
/// 예약 알림(다시 찼어요·내일 결제)은 미리 예약해 두어 앱을 닫아도, 맥이 꺼져 있어도 그 시각에 온다.
/// 바로 보내는 알림(곧 바닥나요)은 아직 보내지 않은 것만, 맥이 정한 지 1시간 안이면 보낸다.
@MainActor
enum PhoneAlerts {
    static let prefix = "tokta|"
    private static let deliveredKey = "deliveredAlerts"

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func apply(_ relay: WidgetData.AlertRelay?, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        // 맥에서만 받게 했으면 iPhone 예약을 모두 지운다.
        guard let relay, relay.toPhone else {
            center.removePendingNotificationRequests(withIdentifiers: pending)
            return
        }
        // iOS는 예약을 64개까지만 둔다. 가까운 것부터.
        let wanted = Dictionary(relay.scheduled.filter { $0.date > now }.sorted { $0.date < $1.date }.prefix(50).map { (key($0), $0) }) { first, _ in first }
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { wanted[$0] == nil })
        for (id, alert) in wanted where !pending.contains(id) {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: alert.date)
            try? await center.add(UNNotificationRequest(identifier: id, content: content(alert), trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }

        var delivered = UserDefaults.standard.stringArray(forKey: deliveredKey) ?? []
        for alert in relay.recent where now.timeIntervalSince(alert.date) < 3600 {
            let id = key(alert)
            guard !delivered.contains(id) else { continue }
            delivered.append(id)
            try? await center.add(UNNotificationRequest(identifier: id, content: content(alert), trigger: nil))
        }
        UserDefaults.standard.set(Array(delivered.suffix(300)), forKey: deliveredKey)
    }

    /// 같은 알림이라도 시각이 바뀌면(다음 주기) 다른 알림으로 본다.
    private static func key(_ alert: WidgetData.RelayedAlert) -> String {
        "\(prefix)\(alert.id)|\(Int(alert.date.timeIntervalSince1970))"
    }

    private static func content(_ alert: WidgetData.RelayedAlert) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        return content
    }
}
