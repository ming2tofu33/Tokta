import SwiftUI

/// 메뉴 맨 위 “지금 쓸 계정” 카드. 서비스 하나는 크게(링 · 리셋이나 소진 예측 · 다음 계정과 비교 · 열기 버튼),
/// 나머지 서비스는 지금 쓸 계정을 한 줄씩. 어느 줄을 눌러도 그 계정으로 연다.
struct NowCard: View {
    @Environment(UsageStore.self) private var store
    @AppStorage(UsagePalette.storageKey) private var palette: UsagePalette = .indigo
    let pick: NowPick

    var body: some View {
        // 1분마다 다시 그려서 리셋·소진까지 남은 시간이 저절로 줄게 한다.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 10) {
                primary(now: context.date)
                if let switchTo = pick.switchTo, let remaining = pick.switchToRemaining {
                    suggestion(switchTo, remaining: remaining)
                }
                openButton
                if !pick.others.isEmpty {
                    Divider()
                    VStack(spacing: 2) {
                        ForEach(pick.others, id: \.service) { OtherServiceLine(line: $0, settings: store.alertSettings) }
                    }
                }
            }
        }
        .padding(Layout.padding)
        .card(radius: Layout.cardRadius, tint: palette.color(for: .plenty))
        // 다른 계정으로 바뀌면 부드럽게 넘어간다.
        .motion(value: pick.primary.id)
    }

    private func primary(now: Date) -> some View {
        let account = pick.primary
        let remaining = pick.primaryRemaining ?? 0
        return HStack(spacing: 14) {
            // 캐릭터: 화면이 찬 높이 = 남은 한도, 얼굴 = 단계. 16픽셀을 3배로.
            VStack(spacing: 3) {
                PixelCharacterView(
                    mood: store.mood(for: account, now: now),
                    remaining: remaining,
                    fill: palette.platformColor(for: tone(remaining)),
                    fillIsLight: tone(remaining) == .moderate
                )
                .frame(width: 48, height: 48)
                Text(pick.primaryRemaining.map { "\(percent($0))%" } ?? "–")
                    .font(.usageNumber(20, weight: .bold))
                    .foregroundStyle(palette.textStyle(for: StatusLevel(remaining: remaining, settings: store.alertSettings)))
                    .rollingNumber(remaining)
                    // "100%"가 20pt 굵게 약 58pt. 넘치면 잘리지 않고 조금 줄어든다.
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 66)
            .opacity(pick.isBlocked ? 0.45 : 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(basisText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.color(for: .plenty))
                    pinMenu
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(account.service.displayName).fontWeight(.semibold)
                    Text(account.displayLabel).lineLimit(1)
                }
                .font(.title3)
                statusLine(now: now)
                windowLines(now: now)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(account.service.displayName) \(account.displayLabel), \(pick.primaryRemaining.map { "\(percent($0))퍼센트 남음" } ?? "아직 못 읽음")")
    }

    /// 쓸 수 없으면 그 까닭, 곧 바닥나면 그 예측, 아니면 가장 빠듯한 구간과 리셋까지 남은 시간.
    @ViewBuilder
    private func statusLine(now: Date) -> some View {
        let account = pick.primary
        if let error = store.errors[account.id] {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else if let snapshot = store.snapshots[account.id] {
            let summary = RowSummary.make(snapshot: snapshot, cycles: cycles(account), settings: store.alertSettings, now: now)
            switch summary.notice {
            case .runsOutIn(_, let soon)?:
                Label(summary.notice!.text, systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(palette.color(for: soon ? .critical : .low))
            case .refillsIn?, .exhausted?, .stale?:
                Text(summary.notice!.text).font(.caption).foregroundStyle(.secondary)
            case nil:
                // 평소에는 줄을 더하지 않는다. 확인 시각은 메뉴 머리줄에 있다.
                EmptyView()
            }
        } else {
            Text("아직 못 읽었어요").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// 왜 이 계정이 카드에 있는지. 외부에서 실제로 쓰는지는 몰라서 “사용 중”이라고 하지 않는다.
    private var basisText: String {
        switch pick.basis {
        case .pinned: String(localized: "고정한 계정")
        case .recent: String(localized: "최근 연 계정")
        case .first: String(localized: "기준 계정")
        }
    }

    /// 구간마다 한 줄: “세션 12% 남음 · 42분 후 리셋”. 다음 리셋이 다른 구간에 막히면 그렇다고 덧붙인다.
    @ViewBuilder
    private func windowLines(now: Date) -> some View {
        if let snapshot = store.snapshots[pick.primary.id], store.errors[pick.primary.id] == nil {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(snapshot.windows) { window in
                    HStack(spacing: 4) {
                        Text(window.title.isEmpty ? String(localized: "한도") : window.title)
                        Text("\(percent(window.remaining))% 남음")
                            .fontDesign(.rounded)
                            .fontWeight(.semibold)
                            .foregroundStyle(palette.textStyle(for: StatusLevel(remaining: window.remaining, settings: store.alertSettings)))
                            .rollingNumber(window.remaining)
                        if let resetsAt = window.resetsAt {
                            Text("· \(ResetText.string(until: resetsAt, now: now))").foregroundStyle(.tertiary)
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                }
                if let note = blockingNote(snapshot, now: now) {
                    Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(.top, 1)
        }
    }

    /// 가장 먼저 리셋되는 구간이 차도 다른 구간이 빠듯하면 계속 막힐 수 있다.
    private func blockingNote(_ snapshot: UsageSnapshot, now: Date) -> String? {
        let upcoming = snapshot.windows.filter { ($0.resetsAt ?? .distantPast) > now }.min { $0.resetsAt! < $1.resetsAt! }
        guard let upcoming, upcoming.remaining <= store.alertSettings.warning,
              let other = snapshot.windows.first(where: { $0.id != upcoming.id && $0.remaining <= store.alertSettings.warning }) else { return nil }
        return String(localized: "\(upcoming.title)\(Josa.subject(upcoming.title)) 차도 \(other.title) 한도 때문에 계속 제한될 수 있어요")
    }

    /// "다음은 개인 31% · 이 속도면 1시간 40분 뒤 바닥". 같은 서비스 다른 계정과 비교해서 왜 이 계정인지 보여준다.
    private func comparison(_ account: Account, remaining: Double, now: Date) -> String {
        var parts = ["\(account.displayLabel) \(percent(remaining))%"]
        if let snapshot = store.snapshots[account.id],
           let notice = RowSummary.make(snapshot: snapshot, cycles: cycles(account), settings: store.alertSettings, now: now).notice,
           case .runsOutIn = notice {
            parts.append(notice.text)
        }
        return String(localized: "다음은 ") + parts.joined(separator: " · ")
    }

    /// 고정한 계정이 빠듯할 때만 나오는 제안. 고정은 그대로 두고 이번만 다른 계정으로 연다.
    private func suggestion(_ account: Account, remaining: Double) -> some View {
        Button {
            AccountOpen.open(account, store: store)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.swap")
                VStack(alignment: .leading, spacing: 1) {
                    Text(pick.isBlocked ? String(localized: "지금은 \(account.displayLabel) 계정을 쓸 수 있어요") : String(localized: "같은 그룹의 \(account.displayLabel) 계정이 더 여유 있어요"))
                        .fontWeight(.medium)
                    if let snapshot = store.snapshots[account.id] {
                        Text(snapshot.windows.map { "\($0.title) \(percent($0.remaining))%" }.joined(separator: " · ")
                             + (remaining <= store.alertSettings.warning ? String(localized: " · 이 계정도 빠듯해요") : ""))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Spacer()
                Text(AccountOpen.title(for: account.service, label: account.displayLabel))
                    .fontWeight(.medium)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right").font(.caption2)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(SuggestionBackground(tint: palette.color(for: .plenty)))
        .transition(.move(edge: .top).combined(with: .opacity))
        .help("이번에 \(account.displayLabel) 계정으로 엽니다. 자동으로 바꾸지는 않아요")
    }

    /// 서비스를 고정하면 그 서비스 안에서 계속 추천 계정을, 계정을 고정하면 그 계정을 보여준다.
    /// 고정한 서비스에 쓸 계정이 없어 다른 서비스를 보여주는 중이면 그렇다고 알려준다.
    @ViewBuilder
    private var pinMenu: some View {
        let account = pick.primary
        Menu {
            Button("\(account.service.displayName) 고정 · 그 안에서 최근 연 계정") { store.cardPin = .service(account.service) }
            Button("\(account.displayLabel) 계정 고정 · 빠듯할 때만 다른 계정 제안") { store.cardPin = .account(account.id) }
            if store.cardPin != nil {
                Divider()
                Button("고정 풀기 · 최근 연 계정") { store.cardPin = nil }
            }
        } label: {
            Image(systemName: pick.pin == nil ? "pin" : "pin.fill")
                .font(.caption2)
                .foregroundStyle(pick.pin == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(palette.color(for: .plenty)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("맨 위 카드 고정")
        .accessibilityLabel("맨 위 카드 고정")
        if let missing = pick.pinnedUnavailable {
            Text("· 고정한 \(missing.displayName)는 지금 쓸 계정 없음")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private var openButton: some View {
        let target = pick.openTarget
        return HStack {
            Button {
                AccountOpen.open(target, store: store)
            } label: {
                Label(AccountOpen.title(for: target.service, label: target.displayLabel), systemImage: "arrow.up.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 4)
            }
            .prominentButton(tint: palette.color(for: .plenty))
            .keyboardShortcut(.return, modifiers: .command)
            .help(AccountOpen.help(for: target.service))
            Spacer()
            Text("⌘↩").font(.caption.monospaced()).foregroundStyle(.tertiary)
        }
    }

    private func cycles(_ account: Account) -> [String: [UsageSample]] {
        Dictionary(uniqueKeysWithValues: (store.snapshots[account.id]?.windows ?? []).map { ($0.id, store.cycle(for: account.id, window: $0)) })
    }

    private func tone(_ remaining: Double) -> BarTone { BarTone(remaining: remaining, settings: store.alertSettings) }
}

/// “바꾸기” 줄 바탕. macOS 26부터는 누르면 반응하는 색 유리, 그 전에는 옅은 색 판.
private struct SuggestionBackground: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Layout.rowRadius, style: .continuous)
        if #available(macOS 26, *) {
            content.glassEffect(.regular.tint(tint.opacity(0.18)).interactive(), in: shape)
        } else {
            content.background(tint.opacity(0.12), in: shape)
        }
    }
}

/// 나머지 서비스 한 줄. 쓸 계정이 없으면 그렇다고만 쓴다.
private struct OtherServiceLine: View {
    @Environment(UsageStore.self) private var store
    @AppStorage(UsagePalette.storageKey) private var palette: UsagePalette = .indigo
    let line: NowPick.Line
    let settings: AlertSettings
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            if let remaining = line.remaining {
                UsageRing(value: remaining, color: palette.color(for: BarTone(remaining: remaining, settings: settings)), lineWidth: 2.5)
                    .frame(width: 12, height: 12)
            } else {
                Circle().strokeBorder(.quaternary, lineWidth: 2.5).frame(width: 12, height: 12)
            }
            Text(line.service.displayName).font(.caption.weight(.medium))
            if let account = line.account {
                Text("→ \(account.displayLabel)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("지금 쓸 계정 없음").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            if let remaining = line.remaining {
                Text("\(percent(remaining))%")
                    .font(.usageNumber(11))
                    .foregroundStyle(palette.textStyle(for: StatusLevel(remaining: remaining, settings: settings)))
                    .rollingNumber(remaining)
                Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary)
                    .offset(x: isHovering ? 2 : 0, y: isHovering ? -2 : 0)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(isHovering && line.account != nil ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: Layout.smallRadius, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .motion(.easeOut(duration: 0.15), value: isHovering)
        .onTapGesture { if let account = line.account { AccountOpen.open(account, store: store) } }
        .contextMenu {
            Button("\(line.service.displayName) 맨 위에 고정") { store.cardPin = .service(line.service) }
            if let account = line.account {
                Button("\(account.displayLabel) 계정 맨 위에 고정") { store.cardPin = .account(account.id) }
            }
            if store.cardPin != nil {
                Button("고정 풀기") { store.cardPin = nil }
            }
        }
        .help(line.account.map { _ in AccountOpen.help(for: line.service) } ?? String(localized: "다 썼거나, 값이 오래됐거나, 확인이 필요한 계정뿐이에요"))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(line.account == nil ? [] : .isButton)
    }
}

/// 남은 비율을 12시 방향부터 시계 방향으로 채우는 링.
struct UsageRing: View {
    let value: Double
    let color: Color
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .motion(.smooth(duration: 0.6), value: value)
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

private func percent(_ remaining: Double) -> Int { Int((remaining * 100).rounded()) }
