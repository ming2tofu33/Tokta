import SwiftUI

struct MenuContentView: View {
    @Environment(UsageStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            let pick = store.nowPick()
            if let pick {
                NowCard(pick: pick)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
            }
            if store.accounts.isEmpty {
                emptyState
            } else if store.accounts.count == 1 {
                // 계정 하나면 위 카드와 같은 내용이라 목록은 뺀다.
                Spacer().frame(height: 10)
            } else if store.accounts.count > 12 {
                // 위 카드만큼 목록을 줄여서 메뉴가 화면을 넘지 않게.
                ScrollView { sectionList(titled: pick != nil) }
                    .frame(height: pick == nil ? 560 : 420)
            } else {
                sectionList(titled: pick != nil)
            }
            Divider()
            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack {
            Text("Tokta").font(.headline)
            Spacer()
            if store.accounts.contains(where: { store.errors[$0.id] != nil }) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                    .help("확인이 필요한 계정이 있어요")
            }
            if let lastRefresh = store.lastRefresh {
                Text("\(lastRefresh, style: .relative) 전")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await store.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    // 읽는 동안 돈다.
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: store.isRefreshing)
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
            .help("지금 새로고침")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func openMainWindow() {
        openWindow(id: MainWindowView.id)
        NSApp.activate()
    }

    private func openMonth() {
        openMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(name: .showMonthTab, object: nil)
        }
    }

    /// 위에 카드가 있으면 “모든 계정” 제목을 붙여 둘을 나눈다.
    private func sectionList(titled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if titled {
                Text("모든 계정")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
            ForEach(store.sections) { SectionView(section: $0, titled: titled) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            PixelCharacterView(mood: .calm, remaining: 0.3, fill: UsagePalette.indigo.platformColor(for: BarTone.plenty), fillIsLight: false)
                .frame(width: 48, height: 48)
            Text("쓰는 AI 구독을 연결해요")
                .font(TitleFont.font(size: 17))
            Text("Claude · Codex · Cursor · Grok · Antigravity")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("연결하기", action: openMainWindow)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let total = store.monthlySubscriptionTotal {
                (Text("이번 달 ").foregroundColor(.secondary) + Text(total).fontWeight(.semibold))
                    .font(.caption.monospacedDigit())
                    .help("설정 → 구독에서 입력한 구독료의 월 합계")
            }
            Spacer()
            Button("전체 계정", action: openMainWindow)
                .keyboardShortcut("o")
                .help("계정을 같은 열로 비교 (⌘O)")
            Button("이번 달", action: openMonth)
            Button("설정") {
                NSApp.activate()
                openSettings()
            }
            Button("종료") { NSApp.terminate(nil) }
        }
        .font(.callout)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct SectionView: View {
    @Environment(UsageStore.self) private var store
    let section: AccountSection
    /// “모든 계정” 아래에서는 묶음 제목을 한 단계 흐리게.
    var titled = false

    var body: some View {
        let recommended = store.recommendedAccountIDs
        VStack(alignment: .leading, spacing: 1) {
            Text(section.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(titled ? .tertiary : .secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
            ForEach(section.accounts) { account in
                AccountRow(
                    account: account,
                    snapshot: store.snapshots[account.id],
                    error: store.errors[account.id],
                    isRecommended: recommended.contains(account.id),
                    serviceName: section.showsService ? account.service.displayName : nil,
                    isLoggingIn: store.loggingIn.contains(account.id),
                    loginURL: store.loginURLs[account.id],
                    onLogin: { AccountLogin.start(for: account, store: store) },
                    onCancelLogin: { AccountLogin.cancel(account, store: store) },
                    onRefresh: { Task { await store.refresh(account) } },
                    onOpen: { AccountOpen.open(account, store: store) },
                    detectedBilling: store.detectedBilling(for: account),
                    cycles: Dictionary(uniqueKeysWithValues: (store.snapshots[account.id]?.windows ?? []).map { ($0.id, store.cycle(for: account.id, window: $0)) }),
                    alertSettings: store.alertSettings
                )
            }
        }
    }
}

