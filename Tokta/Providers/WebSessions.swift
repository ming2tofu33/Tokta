import WebKit

enum WebURLPolicy {
    static func allowsExternal(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host() != nil
    }

    static func allowsNavigation(_ url: URL) -> Bool {
        allowsExternal(url) || url.absoluteString == "about:blank" || url.scheme == "blob"
    }

    static func matchesHost(_ url: URL, _ domain: String) -> Bool {
        guard url.scheme == "https", let host = url.host()?.lowercased() else { return false }
        return host == domain || host.hasSuffix("." + domain)
    }
}

/// 계정마다 분리된 WebKit 저장소. 같은 서비스의 계정 여러 개가 쿠키를 섞지 않는다.
@MainActor
enum WebSessions {
    private static var stores: [Account.ID: WKWebsiteDataStore] = [:]

    static func dataStore(for id: Account.ID) -> WKWebsiteDataStore {
        if let store = stores[id] { return store }
        let store = WKWebsiteDataStore(forIdentifier: id)
        stores[id] = store
        return store
    }

    static func configuration(for id: Account.ID) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore(for: id)
        return configuration
    }

    static func cookie(named name: String, domain: String, for id: Account.ID) async -> String? {
        await dataStore(for: id).httpCookieStore.allCookies()
            .first { $0.name == name && ($0.domain == domain || $0.domain == "." + domain) }?
            .value
    }

    private static func clearData(for id: Account.ID) async {
        await dataStore(for: id).removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    /// 계정을 지우면 그 계정의 로그인 쿠키와 캐시도 지운다.
    static func remove(_ id: Account.ID) async throws {
        // Clear credentials first; even if removing the store fails, cookies must not survive.
        await clearData(for: id)
        stores[id] = nil
        for attempt in 0..<3 {
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: id)
                return
            } catch {
                if attempt == 2 { throw error }
                try await Task.sleep(for: .milliseconds(200))
            }
        }
    }
}

/// 앱 안 로그인 창으로 로그인하는 사이트.
enum WebLoginSite {
    case claude, cursor

    init?(_ service: Service) {
        switch service {
        case .claude: self = .claude
        case .cursor: self = .cursor
        case .chatgpt, .grok, .grokBot, .antigravity: return nil
        }
    }

    var loginURL: URL {
        switch self {
        case .claude: ClaudeWebProvider.loginURL
        case .cursor: CursorProvider.loginURL
        }
    }

    var hint: String {
        switch self {
        case .claude: String(localized: "Google 로그인이 막히면 같은 이메일로 ‘이메일로 계속하기’를 선택하세요.")
        case .cursor: String(localized: "Google 로그인이 막히면 GitHub이나 이메일로 로그인하세요.")
        }
    }

    /// Google 로그인 페이지에 들어가면 크게 띄우는 안내. 앱 안 창에서는 Google 로그인이 막힌다.
    var googleNotice: String {
        switch self {
        case .claude: String(localized: "Google 로그인은 앱 안 창에서 막혀요. 처음으로 돌아가서 같은 Gmail 주소를 입력하고 ‘이메일로 계속하기’를 고르세요. 같은 Claude 계정으로 로그인됩니다.")
        case .cursor: String(localized: "Google 로그인은 앱 안 창에서 막혀요. 처음으로 돌아가서 GitHub이나 같은 Gmail 주소의 이메일 로그인을 쓰세요.")
        }
    }

    static func isGoogleSignIn(_ url: URL) -> Bool {
        WebURLPolicy.matchesHost(url, "accounts.google.com")
    }

    /// 로그인을 마치고 그 사이트로 돌아왔는지. 로그인 페이지(다른 도메인 포함)에 있으면 읽기를 시도하지 않는다.
    func isPastLogin(_ url: URL) -> Bool {
        let host = url.host() ?? ""
        switch self {
        case .claude: return WebURLPolicy.matchesHost(url, "claude.ai") && !url.path().contains("login")
        case .cursor: return url.scheme == "https" && (host == "cursor.com" || host == "www.cursor.com") && !url.path().contains("login")
        }
    }

    @MainActor
    func read(_ accountID: Account.ID) async throws -> UsageSnapshot {
        switch self {
        case .claude: try await ClaudeWebProvider.read(accountID)
        case .cursor: try await CursorProvider.read(accountID)
        }
    }
}

/// 화면에 띄우지 않는 WKWebView로, 로그인된 사이트 안에서 fetch를 실행한다.
/// 사이트가 직접 보내는 요청과 같아서 쿠키와 보안 확인을 그대로 통과하고 토큰을 따로 다룰 필요가 없다.
@MainActor
final class HiddenBrowser: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var loading: CheckedContinuation<Void, any Error>?
    private var loadTimeout: Task<Void, Never>?

    init(accountID: Account.ID) {
        webView = WKWebView(frame: .zero, configuration: WebSessions.configuration(for: accountID))
        super.init()
        webView.navigationDelegate = self
    }

    func open(_ url: URL) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { continuation in
            loading = continuation
            loadTimeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                self?.webView.stopLoading()
                self?.finishLoading(URLError(.timedOut))
            }
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15))
        }
    }

    /// 현재 페이지 기준 경로로 요청을 보내고 상태 코드와 본문을 돌려준다. `jsonBody`가 있으면 POST.
    func get(_ path: String, jsonBody: String? = nil) async throws -> (status: Int, body: String) {
        try Task.checkCancellation()
        let result = try await webView.callAsyncJavaScript(
            """
            const options = { signal: AbortSignal.timeout(15000), credentials: 'include', cache: 'no-store', headers: { Accept: 'application/json' } };
            if (body !== null) {
              options.method = 'POST';
              options.headers['Content-Type'] = 'application/json';
              options.body = body;
            }
            const response = await fetch(path, options);
            return [response.status, await response.text()];
            """,
            arguments: ["path": path, "body": jsonBody.map { $0 as Any } ?? NSNull()],
            contentWorld: .defaultClient
        )
        guard let pair = result as? [Any], pair.count == 2, let status = (pair[0] as? NSNumber)?.intValue, let body = pair[1] as? String else {
            throw UsageError.failed(String(localized: "페이지 응답을 읽지 못했습니다"))
        }
        return (status, body)
    }

    private func finishLoading(_ error: (any Error)? = nil) {
        loadTimeout?.cancel()
        loadTimeout = nil
        let continuation = loading
        loading = nil
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoading()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finishLoading(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        finishLoading(error)
    }
}
