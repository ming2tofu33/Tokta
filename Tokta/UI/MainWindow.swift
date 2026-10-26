import SwiftUI

/// Tokta 창. 처음 실행(계정 연결 · 알림 받을 곳), “전체 계정”, “이번 달”.
struct MainWindowView: View {
    static let id = "main"
    @Environment(UsageStore.self) private var store
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var connecting = false
    /// 기본은 전체 계정. 결제 알림에서 열면 이번 달.
    @State private var tab = Tab.accounts

    enum Tab { case accounts, month }

    var body: some View {
        Group {
            if !didOnboard || store.accounts.isEmpty || connecting {
                OnboardingView(onDone: {
                    didOnboard = true
                    connecting = false
                })
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Picker("보기", selection: $tab) {
                            Text("전체 계정").tag(Tab.accounts)
                            Text("이번 달").tag(Tab.month)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        Spacer()
                        Button("계정 연결", systemImage: "plus") { connecting = true }
                            .buttonStyle(.borderless)
                        SettingsLink { Label("설정", systemImage: "gearshape") }
                            .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    switch tab {
                    case .accounts: AccountsTab()
                    case .month: MonthView()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showMonthTab)) { _ in tab = .month }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 560, idealHeight: 660)
        .background(.regularMaterial)
    }
}

// MARK: - 처음 실행

private struct OnboardingView: View {
    @Environment(UsageStore.self) private var store
    @AppStorage(UsagePalette.storageKey) private var palette: UsagePalette = .indigo
    let onDone: () -> Void
    @State private var step = 0
    @State private var showOthers = false

    /// 처음 화면에 바로 보이는 서비스. Grok·Antigravity는 “다른 서비스”에서.
    static let primary: [Service] = [.claude, .chatgpt, .cursor]

    /// 실제로 처음 읽어 온 계정. 계정 줄만 생긴 것은 연결 완료로 치지 않는다.
    private var firstReading: (account: Account, percent: Int)? {
        for account in store.accounts {
            if let remaining = store.snapshots[account.id]?.bottleneck?.remaining {
                return (account, Int((remaining * 100).rounded()))
            }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    PixelCharacterView(mood: .happy, remaining: 0.6, fill: palette.platformColor(for: BarTone.plenty), fillIsLight: false)
                        .frame(width: 64, height: 64)
                        .padding(.top, 24)
                    Text(step == 0 ? "쓰는 AI 구독을 연결해요" : "알림은 어디서 받을까요?")
                        .font(TitleFont.font(size: 26))
                    Text(step == 0
                         ? "로그인 정보는 이 Mac에만 남고, Tokta는 남은 한도만 읽어요.\n계정이 여러 개면 하나씩 더 추가할 수 있어요."
                         : "곧 바닥나요 · 다시 찼어요 · 내일 결제, 세 가지만 보내요.\niPhone 앱이 없어도 돼요. 나중에 설정 → 알림에서 바꿀 수 있어요.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 6) {
                        ForEach(0..<2) { index in
                            Capsule().fill(index <= step ? Color.accentColor : Color.secondary.opacity(0.2)).frame(width: 24, height: 4)
                        }
                    }
                    .padding(.bottom, 4)
                    if step == 0 {
                        VStack(spacing: 8) {
                            ForEach(Self.primary.filter(store.supportedServices.contains)) { ServiceConnectRow(service: $0) }
                            DisclosureGroup("다른 서비스", isExpanded: $showOthers) {
                                VStack(spacing: 8) {
                                    ForEach(store.supportedServices.filter { !Self.primary.contains($0) && $0 != .grokBot }) { ServiceConnectRow(service: $0) }
                                }
                                .padding(.top, 6)
                            }
                            .font(.callout)
                            .padding(.top, 4)
                            if let first = firstReading {
                                Label(String(localized: "\(AccountName.short(first.account, among: store.accounts)) \(first.percent)% 남음 — 이제 메뉴바에서 바로 볼 수 있어요"), systemImage: "checkmark.circle.fill")
                                    .font(.callout)
                                    .foregroundStyle(.green)
                                    .padding(.top, 6)
                            }
                        }
                    } else {
                        DestinationChoice()
                    }
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
            }
            HStack {
                if step == 0 {
                    Text("나중에 설정 → 계정에서 바꿀 수 있어요").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("이전") { step = 0 }
                }
                Spacer()
                if step == 0 {
                    Button("다음 — 알림 받을 곳") { step = 1 }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .disabled(firstReading == nil)
                        .help(firstReading == nil ? String(localized: "계정 하나를 연결해 남은 한도를 처음 읽어 오면 넘어갈 수 있어요") : "")
                } else {
                    Button("나중에", action: onDone)
                    Button("시작하기", action: onDone)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
    }
}

/// 서비스 하나: 이미 연결됐는지, CLI가 필요한지, 이 Mac 로그인을 바로 쓸 수 있는지에 따라 버튼이 달라진다.
private struct ServiceConnectRow: View {
    @Environment(UsageStore.self) private var store
    let service: Service

    private var accounts: [Account] { store.accounts(for: service) }
    private var installed: Bool { RequiredApp.isInstalled(for: service) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ServiceBadge(service: service, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.displayName).font(.body.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                action
            }
            ForEach(accounts) { account in
                AccountConnectStatus(account: account)
                    .padding(.leading, 40)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .card(radius: 12)
    }

    private var detail: String {
        if !installed, let requirement = RequiredApp.requirement(for: service) {
            return String(localized: "\(requirement.subject) 필요해요")
        }
        switch service {
        case .chatgpt: return String(localized: "ChatGPT 계정의 Codex 한도 · 이 Mac의 Codex 로그인을 그대로 써요")
        case .grok: return String(localized: "이 Mac의 Grok CLI 로그인을 그대로 써요")
        case .antigravity: return String(localized: "이 Mac의 Antigravity(agy) 로그인 하나만 써요")
        case .claude: return String(localized: "Tokta 창에서 로그인 · Google 계정은 ‘이메일로 계속하기’")
        case .cursor: return String(localized: "Tokta 창에서 로그인 · Grok Bot 한도도 함께 보여요")
        case .grokBot: return ""
        }
    }

    @ViewBuilder private var action: some View {
        if !installed, let requirement = RequiredApp.requirement(for: service) {
            Link(destination: requirement.downloadURL) { Text("설치 →").fontWeight(.semibold) }
        } else if service.hasSystemLogin && !store.hasSystemLogin(for: service) {
            Button {
                store.addSystemLogin(for: service)
            } label: { Text("연결 →").fontWeight(.semibold) }
            .buttonStyle(.borderless)
        } else if service.supportsMultipleAccounts {
            Button(action: addAccount) {
                Text(accounts.isEmpty ? "연결 →" : "하나 더").fontWeight(.semibold)
            }
            .buttonStyle(.borderless)
        }
    }

    /// 이름은 기본값(“계정 1”)으로 바로 로그인한다. 이름은 나중에 설정 → 계정에서 바꾼다.
    private func addAccount() {
        let account = Account(service: service, label: String(localized: "계정 \(accounts.count + 1)"))
        store.add(account)
        AccountLogin.start(for: account, store: store)
    }
}

/// 계정 하나의 연결 상태: 로그인 중 → 처음 읽는 중 → 남은 %(성공) / 실패면 다시 시도.
private struct AccountConnectStatus: View {
    @Environment(UsageStore.self) private var store
    let account: Account

    var body: some View {
        HStack(spacing: 6) {
            Text(account.displayLabel).font(.caption.weight(.medium))
            if let remaining = store.snapshots[account.id]?.bottleneck?.remaining, store.errors[account.id] == nil {
                Label(String(localized: "\(Int((remaining * 100).rounded()))% 남음"), systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else if let error = store.errors[account.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).lineLimit(1)
                Button("다시 시도") { AccountLogin.start(for: account, store: store) }.controlSize(.small)
                Button("나중에") { Task { await store.remove(account.id) } }.controlSize(.small)
            } else if store.loggingIn.contains(account.id) {
                ProgressView().controlSize(.mini)
                Text("로그인을 기다려요").font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.mini)
                Text("처음 읽는 중").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct DestinationChoice: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        VStack(spacing: 8) {
            option(.mac, title: String(localized: "이 맥 (추천)"), detail: String(localized: "바로 받아요. iPhone 앱이 없어도 돼요."))
            option(.iPhone, title: String(localized: "iPhone"), detail: String(localized: "iPhone Tokta 앱이 iCloud로 받아서 보내요. 몇 분 늦을 수 있어요. 설정 → 알림의 테스트 알림으로 먼저 확인해 보세요."))
            option(.both, title: String(localized: "둘 다"), detail: String(localized: "맥과 iPhone에 하나씩 와요."))
        }
    }

    private func option(_ destination: AlertDestination, title: String, detail: String) -> some View {
        let selected = store.alertSettings.destination == destination
        return Button {
            var settings = store.alertSettings
            settings.destination = destination
            store.updateAlertSettings(settings)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card(radius: 12)
    }
}

// MARK: - 이번 달

private struct MonthView: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        let report = store.monthReport()
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(periodText(report)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Headline(calm: report.headline(accounts: store.accounts), size: 27)
                    .padding(.bottom, 4)
                if !report.isCollecting {
                    kpis(report)
                    HStack(alignment: .top, spacing: 12) {
                        usageBox(report).frame(maxWidth: .infinity)
                        notesBox(report).frame(maxWidth: .infinity)
                    }
                } else {
                    usageBox(report)
                }
            }
            .padding(22)
        }
    }

    private func periodText(_ report: MonthReport) -> String {
        let end = Date.now
        return "\(LocalDate.monthDay(report.periodStart)) – \(LocalDate.monthDay(end))"
    }

    private func kpis(_ report: MonthReport) -> some View {
        HStack(spacing: 12) {
            kpi(String(localized: "이번 달 구독료"),
                value: MoneyText.monthlyTotal(report.subscribed.compactMap(\.subscription)) ?? "–",
                detail: report.nextRenewal.map { String(localized: "다음: \(RenewalText.string($0.renewal)) · \(AccountName.short($0.account, among: store.accounts))") }
                    ?? String(localized: "설정 → 구독에서 금액을 적어요"))
            kpi(String(localized: "한도가 바닥난 횟수"),
                value: String(localized: "\(report.exhaustedThisMonth)번"),
                detail: lastMonthText(report))
            kpi(String(localized: "거의 안 쓰는 구독"),
                value: String(localized: "\(report.idle.count)개"),
                detail: report.idle.first.map { idleDetail($0) } ?? String(localized: "모두 쓰고 있어요"),
                warn: !report.idle.isEmpty)
        }
    }

    private func lastMonthText(_ report: MonthReport) -> String {
        guard let last = report.exhaustedLastMonth else { return String(localized: "이번 달부터 세요") }
        let diff = report.exhaustedThisMonth - last
        if diff < 0 { return String(localized: "지난달보다 \(-diff)번 적어요") }
        if diff > 0 { return String(localized: "지난달보다 \(diff)번 많아요") }
        return String(localized: "지난달과 같아요")
    }

    private func idleDetail(_ account: Account) -> String {
        let name = AccountName.short(account, among: store.accounts)
        guard let subscription = account.subscription else { return name }
        return "\(name) · \(MoneyText.string(subscription.monthlyAmount, currency: subscription.currency))"
    }

    private func kpi(_ label: String, value: String, detail: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(warn ? Color.orange : Color.primary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }

    private func usageBox(_ report: MonthReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("구독 가치").font(.headline)
                Text("받은 한도 중 쓴 만큼").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)
            ForEach(Array(report.usage.enumerated()), id: \.element.account.id) { index, usage in
                if index > 0 { Divider() }
                HStack(spacing: 10) {
                    ServiceBadge(service: usage.account.service)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(AccountName.short(usage.account, among: store.accounts)).font(.callout)
                        Text(usageDetail(usage, report: report)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let subscription = usage.account.subscription {
                        Text(MoneyText.string(subscription.monthlyAmount, currency: subscription.currency))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(usage.utilization.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(report.idle.contains(usage.account) ? Color.orange : Color.primary)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.vertical, 7)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .card()
    }

    private func usageDetail(_ usage: MonthReport.Usage, report: MonthReport) -> String {
        if report.isCollecting { return String(localized: "기록 모으는 중 · \(report.collectedDays + 1)일째") }
        if report.idle.contains(usage.account) { return String(localized: "최근 \(report.idleDays)일 거의 안 씀") }
        if usage.exhaustions > 0 { return String(localized: "이번 달 \(usage.exhaustions)번 바닥") }
        if usage.utilization == nil { return String(localized: "기록 모으는 중") }
        return (usage.utilization ?? 0) >= MonthReport.heavyAbove ? String(localized: "꽉 차게 씀") : String(localized: "여유 있게 씀")
    }

    private func notesBox(_ report: MonthReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tokta가 본 것").font(.headline)
            ForEach(report.patterns, id: \.account.id) { pattern in
                note(String(localized: "바닥나는 때"), patternText(pattern))
            }
            ForEach(report.idle.filter { $0.subscription != nil }, id: \.id) { account in
                let subscription = account.subscription!
                let name = AccountName.short(account, among: store.accounts)
                note(String(localized: "아낄 수 있는 것"),
                     String(localized: "\(name) 구독을 해지하면 한 달 \(MoneyText.string(subscription.monthlyAmount, currency: subscription.currency))을 아껴요."),
                     warn: true)
            }
            if let next = report.nextRenewal {
                let amount = next.account.subscription.map { " " + MoneyText.string($0.amount, currency: $0.currency) } ?? ""
                note(String(localized: "다음 결제"), "\(RenewalText.string(next.renewal)) · \(AccountName.short(next.account, among: store.accounts))\(amount)")
            }
            if report.patterns.isEmpty && report.idle.isEmpty && report.nextRenewal == nil {
                Text("아직 눈에 띄는 것이 없어요. 기록이 쌓이면 언제 바닥나는지, 아낄 수 있는 구독이 있는지 알려드려요.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .card()
    }

    private func note(_ title: String, _ text: String, warn: Bool = false) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1).fill(warn ? Color.orange : Color.accentColor).frame(width: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func patternText(_ pattern: MonthReport.Pattern) -> String {
        let name = AccountName.short(pattern.account, among: store.accounts)
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let days = pattern.weekdays.map { symbols[$0 - 1] }.joined(separator: "·")
        let hours = "\(HourText.string(pattern.startHour))–\(HourText.string(pattern.endHour))"
        let base = String(localized: "\(name)\(Josa.topic(name)) \(days) \(hours)에 자주 바닥나요.")
        guard let alternative = pattern.alternative else { return base }
        let other = alternative.displayLabel
        return base + " " + String(localized: "그때는 \(other)\(Josa.subject(other) == "이" ? "으로" : "로") 바꿔 쓰면 돼요.")
    }
}

enum HourText {
    /// “오후 3시”, “3 PM”
    static func string(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour % 24, minute: 0, second: 0, of: .now) ?? .now
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("j")
        if Bundle.main.preferredLocalizations.first?.hasPrefix("ko") ?? true { formatter.locale = Locale(identifier: "ko_KR") }
        return formatter.string(from: date)
    }
}
