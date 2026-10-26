import Charts
import SwiftUI

struct AccountRow: View {
    let account: Account
    let snapshot: UsageSnapshot?
    let error: String?
    let isRecommended: Bool
    /// 서비스가 섞인 그룹에서만 보여준다.
    var serviceName: String?
    var isLoggingIn = false
    /// ChatGPT 로그인 중이면 그 로그인 주소.
    var loginURL: URL?
    var onLogin: (() -> Void)?
    var onCancelLogin: (() -> Void)?
    var onRefresh: (() -> Void)?
    /// 그 계정으로 서비스를 연다(Tokta 창 또는 터미널).
    var onOpen: (() -> Void)?
    /// 서비스가 알려준 결제일. 같은 조직 다른 계정 값일 수도 있다.
    var detectedBilling: DetectedBilling?
    /// 구간 id별 지금 주기 사용 기록.
    var cycles: [String: [UsageSample]] = [:]
    var alertSettings = AlertSettings()

    @State private var isHovering = false
    @State private var isExpanded = false
    @AppStorage(UsagePalette.storageKey) private var palette: UsagePalette = .indigo

    var body: some View {
        // 1분마다 다시 그려서 “몇 분 전 값”, 남은 시간, 흐림 표시가 저절로 바뀌게 한다.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            row(now: context.date)
        }
        .contextMenu {
            if let onOpen { Button(AccountOpen.title(for: account.service), action: onOpen) }
            Button(isExpanded ? String(localized: "접기") : String(localized: "자세히 보기")) { toggleExpanded() }
            Divider()
            Button("브라우저에서 \(account.service.displayName) 열기") { NSWorkspace.shared.open(account.service.homeURL) }
            Button("사용량 페이지 열기") { NSWorkspace.shared.open(account.service.usageURL) }
            Divider()
            if let onRefresh { Button("지금 새로고침", action: onRefresh) }
            if let onLogin { Button("다시 로그인", action: onLogin) }
        }
    }

    private func toggleExpanded() {
        withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
    }

    /// "$200/월 · 11월 10일 결제 (D-28)". 금액을 안 적었어도 서비스에서 가져온 결제일은 보여준다.
    private func billingLine(now: Date) -> (text: String, isEnding: Bool)? {
        let renewal = Renewal.resolve(subscription: account.subscription, detected: detectedBilling, now: now)
        let price = account.subscription.map { "\(MoneyText.string($0.amount, currency: $0.currency))/\($0.cycle.label)" }
        let parts = [price, renewal.map { RenewalText.string($0, now: now) }].compactMap { $0 }
        return parts.isEmpty ? nil : (parts.joined(separator: " · "), renewal?.isEnding ?? false)
    }

    private func row(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            summaryLine(now: now)
                .contentShape(Rectangle())
                .onTapGesture { toggleExpanded() }
                .help(isRecommended
                    ? String(localized: "같은 서비스 계정 중 남은 한도가 가장 많아요 · 눌러서 \(isExpanded ? "접기" : "자세히 보기")")
                    : String(localized: "눌러서 \(isExpanded ? "접기" : "자세히 보기")"))
            if isLoggingIn {
                loginGuide
            } else if let error {
                HStack(alignment: .firstTextBaseline) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                    Spacer()
                    if let onLogin {
                        Button("로그인", action: onLogin).controlSize(.small)
                    }
                }
            }
            if isExpanded { details(now: now) }
        }
        .padding(.horizontal, Layout.padding)
        .padding(.vertical, 6)
        .background(background, in: RoundedRectangle(cornerRadius: Layout.rowRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .motion(.easeOut(duration: 0.15), value: isHovering)
    }

    /// 추천은 메뉴 맨 위 카드가 맡아서 줄은 칠하지 않는다. 마우스를 올리거나 펼쳤을 때만.
    private var background: AnyShapeStyle {
        if isHovering || isExpanded { return AnyShapeStyle(.quaternary.opacity(0.6)) }
        return AnyShapeStyle(.clear)
    }

    private func summaryLine(now: Date) -> some View {
        HStack(spacing: 6) {
            // 이름이 길면 플랜을 “…”로 자르지 않고 아예 뺀다. 플랜은 펼치면 보인다.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    Text(account.displayLabel)
                    if let detail = serviceName ?? snapshot?.plan {
                        Text(detail).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Text(account.displayLabel).lineLimit(1)
            }
            .frame(width: 100, alignment: .leading)

            if let snapshot {
                let summary = RowSummary.make(snapshot: snapshot, cycles: cycles, settings: alertSettings, now: now)
                let isStale = snapshot.isStale(at: now)
                Group {
                    MiniBars(windows: snapshot.windows, settings: alertSettings)
                    Text("\(Int((summary.remaining * 100).rounded()))%")
                        .font(.usageNumber(13))
                        .foregroundStyle(palette.textStyle(for: summary.level))
                        .rollingNumber(summary.remaining)
                        // "100%"가 둥근 숫자 글꼴로 약 38pt. 넘치면 잘리지 않고 조금 줄어든다.
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 44, alignment: .trailing)
                }
                .opacity(isStale ? 0.45 : 1)
                notice(summary.notice)
                    .frame(width: 14)
            } else {
                Spacer()
                if error == nil && !isLoggingIn { ProgressView().controlSize(.small) }
            }

            // 줄 어디를 눌러도 펼쳐진다. 화살표는 펼침 상태 표시.
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 14, height: 14)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isExpanded ? String(localized: "펼침") : String(localized: "접힘"))
        .accessibilityHint(isRecommended ? String(localized: "같은 서비스 계정 중 남은 한도가 가장 많음") : "")
    }

    /// 지금 쓰는 데 걸리는 일이 있을 때만 작은 아이콘. 문구는 마우스를 올리면 보인다.
    /// 아이콘이 없어도 칸 너비는 그대로 둬서 줄마다 막대 길이가 같다.
    @ViewBuilder
    private func notice(_ notice: RowSummary.Notice?) -> some View {
        if let notice {
            Image(systemName: Self.symbol(for: notice))
                .font(.caption)
                .foregroundStyle(style(for: notice))
                .help(notice.text)
                .accessibilityLabel(notice.text)
        } else {
            Color.clear.frame(height: 1)
        }
    }

    private static func symbol(for notice: RowSummary.Notice) -> String {
        switch notice {
        case .refillsIn, .exhausted: "hourglass"
        case .runsOutIn: "chart.line.uptrend.xyaxis"
        case .stale: "clock.arrow.circlepath"
        }
    }

    private func style(for notice: RowSummary.Notice) -> AnyShapeStyle {
        switch notice {
        case .runsOutIn(_, let soon): AnyShapeStyle(palette.color(for: soon ? .critical : .low))
        case .refillsIn, .exhausted, .stale: AnyShapeStyle(.secondary)
        }
    }

    private var loginGuide: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ProgressView().controlSize(.small)
                Text("브라우저에서 **추가할 \(account.service.displayName) 계정**으로 로그인하세요").font(.caption)
                Spacer()
                if let onCancelLogin {
                    Button("취소", action: onCancelLogin).controlSize(.small)
                }
            }
            Text("다른 계정이 이미 로그인돼 있으면 그 계정으로 연결될 수 있어요. 로그아웃하거나 시크릿 창에서 로그인하세요.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let loginURL {
                Button("로그인 주소 복사 (시크릿 창에 붙여넣기)") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(loginURL.absoluteString, forType: .string)
                }
                .controlSize(.small)
            }
        }
    }

    /// 펼친 화면. 막대는 접힌 줄에 이미 있으니 여기서는 구간마다 글자 한 줄로 남은 양·리셋·추이를 맞춰 보여준다.
    private func details(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                let identity = [snapshot?.plan, snapshot?.loginEmail ?? account.email].compactMap { $0 }
                if !identity.isEmpty {
                    Text(identity.joined(separator: " · ")).foregroundStyle(.secondary)
                }
                if let line = billingLine(now: now) {
                    Text(line.text)
                        .foregroundStyle(line.isEnding ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
            }
            .font(.caption)

            if let snapshot {
                let isStale = snapshot.isStale(at: now)
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    ForEach(snapshot.windows) { window in
                        // 오래된 값으로는 예측하지 않는다.
                        let exhaustsAt = isStale ? nil : Forecaster.exhaustion(cycle: cycles[window.id] ?? [], window: window, observedAt: snapshot.observedAt)
                        windowRow(window, cycle: cycles[window.id] ?? [], now: now)
                        if let exhaustsAt {
                            GridRow {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                Label(ForecastText.string(exhaustsAt: exhaustsAt, now: now), systemImage: "chart.line.uptrend.xyaxis")
                                    .foregroundStyle(palette.color(for: exhaustsAt.timeIntervalSince(now) < 3600 ? .critical : .low))
                                    .gridCellColumns(3)
                            }
                        }
                    }
                }
                .font(.caption)
                .opacity(isStale ? 0.45 : 1)

                if isStale {
                    Label("\(AgeText.string(since: snapshot.observedAt, now: now)) 값 · 최신이 아닐 수 있어요", systemImage: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let resets = snapshot.limitResetsLeft, resets > 0 {
                    Label("한도 리셋 \(resets)회 남음", systemImage: "arrow.counterclockwise")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("한도를 다 써도 바로 초기화할 수 있는 남은 횟수")
                }
            }

            HStack(spacing: 12) {
                if let onOpen {
                    Button(AccountOpen.title(for: account.service), action: onOpen)
                        .controlSize(.small)
                        .help(AccountOpen.help(for: account.service))
                }
                Group {
                    Button("브라우저에서 열기") { NSWorkspace.shared.open(account.service.homeURL) }
                    Button("사용량 페이지") { NSWorkspace.shared.open(account.service.usageURL) }
                }
                .buttonStyle(.link)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    /// 구간 이름 · 남은 % · 리셋까지 · 추이 선. 열을 맞춰서 구간끼리 비교하기 쉽게.
    private func windowRow(_ window: UsageWindow, cycle: [UsageSample], now: Date) -> some View {
        let level = StatusLevel(remaining: window.remaining, settings: alertSettings)
        let reset = window.resetsAt.map { ResetText.string(until: $0, now: now) } ?? (window.remaining >= 1 ? String(localized: "사용 전") : "")
        return GridRow {
            Text(window.title).foregroundStyle(.secondary)
            Text("\(Int((window.remaining * 100).rounded()))%")
                .monospacedDigit()
                .foregroundStyle(palette.textStyle(for: level))
                .gridColumnAlignment(.trailing)
            Text(reset)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            if cycle.count >= 3 {
                Sparkline(samples: cycle, width: 36).gridColumnAlignment(.trailing)
            } else {
                Color.clear.frame(width: 36, height: 12)
            }
        }
    }
}

/// 구간마다 얇은 막대 하나. 위에서부터 응답 순서(보통 짧은 구간 → 긴 구간).
struct MiniBars: View {
    let windows: [UsageWindow]
    let settings: AlertSettings
    @AppStorage(UsagePalette.storageKey) private var palette: UsagePalette = .indigo

    var body: some View {
        VStack(spacing: 2) {
            ForEach(windows.prefix(3)) { window in
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(palette.color(for: BarTone(remaining: window.remaining, settings: settings)))
                            .frame(width: proxy.size.width * window.remaining)
                            .motion(.smooth(duration: 0.6), value: window.remaining)
                    }
                }
                .frame(height: windows.count > 2 ? 3 : 4)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// 지금 주기 동안 사용 비율이 어떻게 올라왔는지 보여주는 작은 선.
private struct Sparkline: View {
    let samples: [UsageSample]
    var width: CGFloat = 56

    var body: some View {
        Chart(samples, id: \.t) { sample in
            LineMark(x: .value(String(localized: "시각"), sample.t), y: .value(String(localized: "사용"), sample.u))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.2))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
        .chartLegend(.hidden)
        .foregroundStyle(.secondary)
        .frame(width: width, height: 12)
        .help("이번 주기 사용 추이")
    }
}
