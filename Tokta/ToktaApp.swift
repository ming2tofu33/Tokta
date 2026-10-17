import SwiftUI

@main
struct ToktaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: UsageStore

    init() {
        let notifier = SystemNotifier()
        let store = UsageStore(notifier: notifier)
        AppDelegate.store = store
        store.onChange = { [weak store] in if let store { WidgetSync.publish(store) } }
        WidgetSync.publish(store)
        store.startAutoRefresh()
        if store.alertSettings.destination.onMac {
            Task { _ = await notifier.requestAuthorization() }
        }
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("Tokta", id: MainWindowView.id) {
            MainWindowView()
                .environment(store)
        }
        .defaultSize(width: 760, height: 640)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

/// 메뉴바 아이콘. 처음 실행이면 Tokta 창을 열어 계정 연결부터 안내한다.
private struct MenuBarLabel: View {
    let store: UsageStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage("didOnboard") private var didOnboard = false

    var body: some View {
        MenuBarIcon(level: store.menuBarLevel, remaining: store.menuBarRemaining, character: store.menuBarCharacter)
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
                openWindow(id: MainWindowView.id)
                NSApp.activate()
            }
            .task {
                // 이 기능 전부터 쓰던 사람은 안내를 건너뛴다.
                if !store.accounts.isEmpty { didOnboard = true }
                guard !didOnboard else { return }
                openWindow(id: MainWindowView.id)
                NSApp.activate()
            }
    }
}

/// 위젯을 누르면 오는 `tokta://open/<계정 ID>`를 받아 그 계정으로 연다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var store: UsageStore?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let store = Self.store else { return }
        for url in urls {
            // tokta://window — Tokta 창 열기, tokta://window/month — 이번 달 탭으로
            if url.scheme == "tokta", url.host() == "window" {
                NotificationCenter.default.post(name: .openMainWindow, object: nil)
                if url.lastPathComponent == "month" {
                    // 창이 막 열릴 때는 탭 화면이 아직 없어서 조금 뒤에.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: .showMonthTab, object: nil)
                    }
                }
                continue
            }
            guard let id = WidgetData.accountID(fromOpenURL: url), let account = store.accounts.first(where: { $0.id == id }) else { continue }
            AccountOpen.open(account, store: store)
        }
    }
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("app.tokta.openMainWindow")
    static let showMonthTab = Notification.Name("app.tokta.showMonthTab")
}
