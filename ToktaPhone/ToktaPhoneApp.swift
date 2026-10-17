import SwiftUI
import UIKit
import WidgetKit

@main
struct ToktaPhoneApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = PhoneStore.shared

    var body: some Scene {
        WindowGroup {
            PhoneContentView()
                .environment(store)
                .onOpenURL { store.open($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
    }
}

/// 맥이 iCloud에 새 값을 올리면 오는 조용한 알림을 받아 다시 읽는다.
final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        Task {
            try? await CloudSync.subscribe()
            await PhoneAlerts.requestPermission()
            await PhoneAlerts.apply(PhoneStore.shared.data?.alerts)
        }
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await PhoneStore.shared.refresh() ? .newData : .noData
    }
}

/// iPhone의 Tokta. 사용량은 직접 읽지 않고, 맥이 iCloud에 올린 값을 받아 보여준다.
/// 받은 값은 App Group 파일에도 써서 iPhone 위젯이 같이 쓴다.
@MainActor
@Observable
final class PhoneStore {
    static let shared = PhoneStore()

    private(set) var data: WidgetData? = WidgetData.load()
    private(set) var isRefreshing = false
    private(set) var lastError: String?
    /// iPhone에서 따로 고른 색 조합. nil이면 맥과 같게.
    var localPalette: UsagePalette? = WidgetData.localPalette {
        didSet {
            WidgetData.localPalette = localPalette
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// 새 값을 받았으면 true.
    @discardableResult
    func refresh() async -> Bool {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            guard let fresh = try await CloudSync.fetch() else { lastError = nil; return false }
            lastError = nil
            guard fresh != data else { return false }
            data = fresh
            try? fresh.save()
            PixelCharacter.current = fresh.character ?? .window
            WidgetCenter.shared.reloadAllTimelines()
            await PhoneAlerts.apply(fresh.alerts)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// 위젯이나 목록에서 계정을 누르면 그 서비스를 연다. 어느 계정으로 열지는 iPhone에서 고를 수 없다.
    func open(_ url: URL) {
        guard let id = WidgetData.accountID(fromOpenURL: url),
              let row = data?.sections.flatMap(\.rows).first(where: { $0.id == id }) else { return }
        open(row)
    }

    func open(_ row: WidgetData.Row) {
        guard let url = Self.homeURL(serviceID: row.serviceID) else { return }
        UIApplication.shared.open(url)
    }

    static func homeURL(serviceID: String) -> URL? {
        switch serviceID {
        case "claude": URL(string: "https://claude.ai/new")
        case "chatgpt": URL(string: "https://chatgpt.com")
        case "grok": URL(string: "https://grok.com")
        case "cursor", "grokBot": URL(string: "https://cursor.com/dashboard")
        case "antigravity": URL(string: "https://antigravity.google")
        default: nil
        }
    }
}
