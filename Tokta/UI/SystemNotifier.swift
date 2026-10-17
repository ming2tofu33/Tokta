import AppKit
import UserNotifications

/// macOS 알림 센터로 알림을 보내고 리셋 알림을 예약한다.
@MainActor
final class SystemNotifier: NSObject, AlertDelivering, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    /// 버튼 이름 조합마다 하나씩 만든 알림 종류. 버튼 이름에 계정 이름이 들어가서 미리 정해 둘 수 없다.
    private var categories: [String: UNNotificationCategory] = [:]

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func handle(_ event: AlertEvent) {
        switch event {
        case .notify(let message):
            add(message, trigger: nil)
        case .schedule(let message, let date):
            add(message, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false))
        case .cancel(let id):
            center.removePendingNotificationRequests(withIdentifiers: [id])
        }
    }

    private func add(_ message: AlertMessage, trigger: UNNotificationTrigger?) {
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        if !message.actions.isEmpty {
            content.categoryIdentifier = category(for: message.actions)
            content.userInfo = ["urls": message.actions.map(\.url.absoluteString)]
        }
        center.add(UNNotificationRequest(identifier: message.id, content: content, trigger: trigger))
    }

    private func category(for actions: [AlertAction]) -> String {
        let id = "actions|" + actions.map(\.title).joined(separator: "|")
        if categories[id] == nil {
            let buttons = actions.enumerated().map { index, action in
                UNNotificationAction(identifier: "action.\(index)", title: action.title, options: [.foreground])
            }
            categories[id] = UNNotificationCategory(identifier: id, actions: buttons, intentIdentifiers: [])
            center.setNotificationCategories(Set(categories.values))
        }
        return id
    }

    /// 버튼을 누르면 그 버튼의 주소를, 배너 자체를 누르면 첫 번째 버튼의 주소를 연다.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let urls = response.notification.request.content.userInfo["urls"] as? [String] else { return }
        let index: Int? = switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier: 0
        case let id where id.hasPrefix("action."): Int(id.dropFirst("action.".count))
        default: nil
        }
        guard let index, urls.indices.contains(index), let url = URL(string: urls[index]) else { return }
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
    }

    /// 메뉴를 열어둔 동안에도 배너를 보여준다.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
