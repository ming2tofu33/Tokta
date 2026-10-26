import SwiftUI
import WebKit

/// 계정 하나의 웹 로그인 창. 그 계정 전용 저장소에 로그인하고, 사용량을 읽을 수 있게 되면 저절로 닫힌다.
@MainActor
final class LoginWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private static var openWindows: [Account.ID: LoginWindowController] = [:]

    private let account: Account
    private let site: WebLoginSite
    private let store: UsageStore
    private let window: NSWindow
    private let webView: WKWebView
    private var polling: Task<Void, Never>?
    private let state = LoginViewState()
    private var checking: Task<Void, Never>?
    private var isClosed = false

    static func show(for account: Account, store: UsageStore) {
        guard store.canUse(account.id), let site = WebLoginSite(account.service) else { return }
        let controller = openWindows[account.id] ?? LoginWindowController(account: account, site: site, store: store)
        openWindows[account.id] = controller
        controller.window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    static func closeAndWait(for id: Account.ID) async {
        guard let controller = openWindows[id] else { return }
        let checking = controller.checking
        controller.window.close()
        await checking?.value
    }

    private init(account: Account, site: WebLoginSite, store: UsageStore) {
        self.account = account
        self.site = site
        self.store = store
        webView = WKWebView(frame: .zero, configuration: WebSessions.configuration(for: account.id))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        window.title = String(localized: "\(account.service.displayName) 로그인 · \(account.displayLabel)")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: LoginView(
            webView: webView,
            hint: site.hint,
            googleNotice: site.googleNotice,
            state: state,
            onRestart: { [weak self] in self?.restart() }
        ))
        window.center()
        webView.load(URLRequest(url: site.loginURL))
        // 로그인 후 화면 이동 없이 앱 안에서만 넘어가는 경우도 있어서 주기적으로도 확인한다.
        polling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                self?.checkLogin()
            }
        }
    }

    private func checkLogin() {
        guard !isClosed, checking == nil, store.canUse(account.id),
              let url = webView.url, site.isPastLogin(url) else { return }
        checking = Task {
            defer { checking = nil }
            guard let snapshot = try? await site.read(account.id), !Task.isCancelled,
                  !isClosed, store.canUse(account.id) else { return }
            store.record(snapshot, for: account.id)
            window.close()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkLogin()
    }

    /// Google 로그인 페이지로 넘어가는 순간 안내를 띄우고, 다른 곳으로 가면 내린다.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let url = webView.url { state.showsGoogleNotice = WebLoginSite.isGoogleSignIn(url) }
    }

    private func restart() {
        state.showsGoogleNotice = false
        webView.load(URLRequest(url: site.loginURL))
    }

    /// 새 창으로 여는 로그인 단계도 같은 창에서 이어서 연다.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
           WebURLPolicy.allowsExternal(url) { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url.map(WebURLPolicy.allowsNavigation) == true ? .allow : .cancel)
    }

    func windowWillClose(_ notification: Notification) {
        isClosed = true
        checking?.cancel()
        window.contentView = nil
        polling?.cancel()
        webView.stopLoading()
        Self.openWindows[account.id] = nil
    }
}

@MainActor
@Observable
private final class LoginViewState {
    var showsGoogleNotice = false
}

private struct LoginView: View {
    let webView: WKWebView
    let hint: String
    let googleNotice: String
    let state: LoginViewState
    let onRestart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if state.showsGoogleNotice {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(googleNotice)
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("처음으로 돌아가기", action: onRestart)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(14)
                .background(.orange.opacity(0.15))
            } else {
                Label("\(hint) 로그인되면 이 창은 저절로 닫힙니다.", systemImage: "info.circle")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.bar)
            }
            WebView(webView: webView)
        }
    }
}

private struct WebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
