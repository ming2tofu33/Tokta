import SwiftUI
import WebKit

/// 계정 하나가 로그인된 채로 서비스를 쓰는 창. 로그인 창과 같은 계정 전용 저장소를 쓰므로
/// 브라우저에서 로그아웃·로그인을 반복하지 않고 계정마다 창을 따로 띄울 수 있다.
/// 위쪽 막대에 남은 양을 보여주고, 빠듯하면 같은 서비스에서 여유 있는 계정으로 바로 바꾼다.
@MainActor
final class AccountWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private static var openWindows: [Account.ID: AccountWindowController] = [:]

    private let accountID: Account.ID
    private let service: Service
    private let window: NSWindow
    private let webView: EditableWebView

    static func show(for account: Account, store: UsageStore, frame: NSRect? = nil) {
        guard store.canUse(account.id) else { return }
        if let controller = openWindows[account.id] {
            controller.window.makeKeyAndOrderFront(nil)
        } else {
            let controller = AccountWindowController(account: account, store: store)
            openWindows[account.id] = controller
            if let frame { controller.window.setFrame(frame, display: false) }
            controller.window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
    }

    static func close(for id: Account.ID) {
        openWindows[id]?.window.close()
    }

    private init(account: Account, store: UsageStore) {
        accountID = account.id
        service = account.service
        webView = EditableWebView(frame: .zero, configuration: WebSessions.configuration(for: account.id))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        window.title = "\(account.service.displayName) · \(account.displayLabel)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: AccountWindowView(
            accountID: account.id,
            webView: webView,
            onSwitch: { [weak self] other in self?.switchTo(other, store: store) },
            onGone: { [weak self] in self?.window.close() }
        ).environment(store))
        window.center()
        window.setFrameTopLeftPoint(cascadePoint())
        webView.load(URLRequest(url: account.service.homeURL))
    }

    /// 같은 서비스 창이 여러 개면 겹치지 않게 조금씩 비켜 놓는다.
    private func cascadePoint() -> NSPoint {
        let others = Self.openWindows.values.filter { $0 !== self && $0.service == service }
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        return NSPoint(x: topLeft.x + CGFloat(others.count) * 24, y: topLeft.y - CGFloat(others.count) * 24)
    }

    /// 같은 자리, 같은 크기로 다른 계정 창을 띄우고 이 창은 닫는다.
    private func switchTo(_ other: Account, store: UsageStore) {
        let frame = window.frame
        window.close()
        Self.show(for: other, store: store, frame: frame)
    }

    func windowWillClose(_ notification: Notification) {
        webView.stopLoading()
        window.contentView = nil
        Self.openWindows[accountID] = nil
    }

    // MARK: 링크·파일

    /// 새 창으로 여는 링크: 같은 서비스면 이 창에서, 다른 사이트면 기본 브라우저에서.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url, WebURLPolicy.allowsExternal(url) else { return nil }
        if isServiceHost(url) { webView.load(navigationAction.request) } else { NSWorkspace.shared.open(url) }
        return nil
    }

    private func isServiceHost(_ url: URL) -> Bool {
        guard let host = url.host(), let home = service.homeURL.host() else { return false }
        let base = home.split(separator: ".").suffix(2).joined(separator: ".")
        return host == base || host.hasSuffix("." + base)
    }

    /// 파일 첨부 버튼.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.request.url.map(WebURLPolicy.allowsNavigation) == true else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    /// 다운로드는 ~/Downloads에 같은 이름이 있으면 번호를 붙여 저장하고, 끝나면 Finder에서 보여준다.
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
        completionHandler(Self.uniqueDownloadURL(for: suggestedFilename))
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let url = download.progress.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    nonisolated static func uniqueDownloadURL(for filename: String, in directory: URL = .downloadsDirectory) -> URL {
        let name = (filename as NSString).deletingPathExtension, ext = (filename as NSString).pathExtension
        var candidate = directory.appending(path: filename)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: ext.isEmpty ? "\(name) \(number)" : "\(name) \(number).\(ext)")
            number += 1
        }
        return candidate
    }
}

/// Tokta는 메뉴바 앱이라 편집 메뉴가 없어서, 웹 페이지 안 복사·붙여넣기 같은 단축키를 직접 넘긴다.
final class EditableWebView: WKWebView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let action: Selector? = switch (key, flags.contains(.shift)) {
        case ("x", false): #selector(NSText.cut(_:))
        case ("c", false): #selector(NSText.copy(_:))
        case ("v", false): #selector(NSText.paste(_:))
        case ("a", false): #selector(NSText.selectAll(_:))
        case ("z", false): Selector(("undo:"))
        case ("z", true): Selector(("redo:"))
        case ("r", false): #selector(WKWebView.reload(_:))
        case ("w", false): #selector(NSWindow.performClose(_:))
        default: nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// 창 위쪽 막대: 계정 이름 · 남은 양 · 바꾸기. 아래는 그 계정으로 로그인된 서비스 페이지.
private struct AccountWindowView: View {
    @Environment(UsageStore.self) private var store
    let accountID: Account.ID
    let webView: WKWebView
    let onSwitch: (Account) -> Void
    let onGone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let account = store.accounts.first(where: { $0.id == accountID }) {
                AccountWindowBar(account: account, onSwitch: onSwitch, onReload: { webView.reload() })
                Divider()
            }
            AccountWebView(webView: webView)
        }
        .onChange(of: store.accounts.contains { $0.id == accountID }) { _, exists in
            // 계정을 지우면 그 계정 저장소도 지워지므로 창을 닫는다.
            if !exists { onGone() }
        }
    }
}

private struct AccountWindowBar: View {
    @Environment(UsageStore.self) private var store
    @AppStorage(UsagePalette.storageKey) private var palette: UsagePalette = .indigo
    let account: Account
    let onSwitch: (Account) -> Void
    let onReload: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            bar(now: context.date)
        }
    }

    private func bar(now: Date) -> some View {
        let snapshot = store.snapshots[account.id]
        let summary = snapshot.map { RowSummary.make(snapshot: $0, cycles: [:], settings: store.alertSettings, now: now) }
        let alternative = store.bestAlternative(to: account)
        let isTight = summary.map { $0.level != .normal || $0.notice != nil } ?? (store.errors[account.id] != nil)
        let others = store.accounts(for: account.service).filter { $0.id != account.id }
        return HStack(spacing: 12) {
            Text(account.displayLabel).font(.headline)
            if let snapshot, let summary {
                MiniBars(windows: snapshot.windows, settings: store.alertSettings)
                    .frame(width: 120)
                Text("\(Int((summary.remaining * 100).rounded()))% 남음")
                    .monospacedDigit()
                    .foregroundStyle(palette.textStyle(for: summary.level))
                if let detail = summary.notice?.text ?? snapshot.bottleneck?.resetsAt.map({ ResetText.string(until: $0, now: now) }) {
                    Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            } else if let error = store.errors[account.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(1)
            }
            Spacer()
            // 빠듯하거나 쓸 수 없을 때만 바로 바꾸기 버튼을 크게 보여준다.
            if isTight, let alternative, let remaining = store.snapshots[alternative.id]?.bottleneck?.remaining {
                Button("\(alternative.displayLabel) 계정으로 바꾸기 · \(Int((remaining * 100).rounded()))%") { onSwitch(alternative) }
                    .buttonStyle(.borderedProminent)
            }
            if !others.isEmpty {
                Menu("계정 바꾸기") {
                    ForEach(others) { other in
                        Button(menuTitle(for: other, isBest: other.id == alternative?.id)) { onSwitch(other) }
                    }
                }
                .fixedSize()
            }
            Button(action: onReload) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("페이지 새로고침 (⌘R)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func menuTitle(for other: Account, isBest: Bool) -> String {
        let percent = store.snapshots[other.id]?.bottleneck.map { "\(Int(($0.remaining * 100).rounded()))%" } ?? "—"
        let state = store.errors[other.id] != nil ? String(localized: " · 확인 필요") : isBest ? String(localized: " · 가장 여유") : ""
        return "\(other.displayLabel)  \(percent)\(state)"
    }
}

private struct AccountWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
