import Charts
import SwiftUI

/// Tokta 창 “전체 계정”. 한 서비스의 계정을 같은 열(구간)로 비교한다. 계정을 숨기거나 “+2”로 줄이지 않는다.
/// “전체”(기본)는 서비스마다 표를 하나씩 쌓는다. 서비스마다 구간이 달라서 한 표로 합치면 열이 맞지 않는다.
/// 칸마다 구간 이름과 숫자를 같이 쓰고, 오류·오래된 값·조회 전·해당 없음을 다르게 보여준다(기획서 F4, C).
struct AccountsTab: View {
    @Environment(UsageStore.self) private var store
    @AppStorage(UsagePalette.storageKey) private var palette: UsagePalette = .indigo
    /// nil = 전체 서비스
    @State private var service: Service?
    /// nil = 모든 그룹, `ungrouped` = 그룹 없음
    @State private var group: AccountGroup.ID?
    @State private var sort = Sort.mine
    @State private var selected: Account.ID?

    static let ungrouped = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    enum Sort: String, CaseIterable, Identifiable {
        case mine, roomy, resetSoon
        var id: String { rawValue }
        var title: String {
            switch self {
            case .mine: String(localized: "내 순서")
            case .roomy: String(localized: "여유 많은 순")
            case .resetSoon: String(localized: "리셋 빠른 순")
            }
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            // 전체에서 그룹으로 거르면 그 그룹에 계정이 없는 서비스는 뺀다.
            let services = service.map { [$0] } ?? store.activeServices.filter { group == nil || !rows($0, now: context.date).isEmpty }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    filters
                    ForEach(services) { current in
                        if service == nil {
                            HStack(spacing: 8) {
                                ServiceBadge(service: current, size: 20)
                                Text(current.displayName).font(.headline)
                                Text("\(store.accounts(for: current).count)개").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)
                        }
                        table(current, now: context.date)
                    }
                    if !services.isEmpty {
                        DisclosureGroup("오늘 하루 기록") {
                            DayTimelineView(accounts: services.flatMap { rows($0, now: context.date) })
                                .padding(.top, 6)
                        }
                        .font(.callout)
                    }
                }
                .padding(22)
            }
        }
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Picker("서비스", selection: Binding(get: { service }, set: { service = $0; selected = nil })) {
                Text(String(localized: "전체 · \(store.accounts.count)개")).tag(Service?.none)
                Divider()
                ForEach(store.activeServices) { service in
                    Text(String(localized: "\(service.displayName) · \(store.accounts(for: service).count)개")).tag(Service?.some(service))
                }
            }
            .fixedSize()
            if !store.groups.isEmpty {
                Picker("그룹", selection: $group) {
                    Text("모든 그룹").tag(AccountGroup.ID?.none)
                    ForEach(store.groups) { Text($0.name).tag(AccountGroup.ID?.some($0.id)) }
                    Text("그룹 없음").tag(AccountGroup.ID?.some(Self.ungrouped))
                }
                .fixedSize()
            }
            Picker("정렬", selection: $sort) {
                ForEach(Sort.allCases) { Text($0.title).tag($0) }
            }
            .fixedSize()
            Spacer()
        }
    }

    /// 걸러서 정렬한 계정.
    private func rows(_ service: Service, now: Date) -> [Account] {
        let members = store.accounts(for: service).filter { account in
            guard let group else { return true }
            return group == Self.ungrouped ? account.groupID == nil : account.groupID == group
        }
        switch sort {
        case .mine:
            return members
        case .roomy:
            return members.enumerated().sorted { a, b in
                let x = store.snapshots[a.element.id]?.bottleneck?.remaining ?? -1, y = store.snapshots[b.element.id]?.bottleneck?.remaining ?? -1
                return x != y ? x > y : a.offset < b.offset
            }.map(\.element)
        case .resetSoon:
            func next(_ account: Account) -> Date {
                store.snapshots[account.id]?.windows.compactMap(\.resetsAt).filter { $0 > now }.min() ?? .distantFuture
            }
            return members.enumerated().sorted { a, b in
                let x = next(a.element), y = next(b.element)
                return x != y ? x < y : a.offset < b.offset
            }.map(\.element)
        }
    }

    /// 열 = 이 서비스 계정들에 나오는 구간(처음 나온 순서). 이름이 같은 구간이 있으면 id로 구분.
    private func columns(_ service: Service) -> [(id: String, title: String)] {
        var seen: [(id: String, title: String)] = []
        for account in store.accounts(for: service) {
            for window in store.snapshots[account.id]?.windows ?? [] where !seen.contains(where: { $0.id == window.id }) {
                seen.append((window.id, window.title.isEmpty ? String(localized: "한도") : window.title))
            }
        }
        return seen
    }

    private func table(_ service: Service, now: Date) -> some View {
        let columns = columns(service)
        let accounts = rows(service, now: now)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("계정").frame(width: 110, alignment: .leading)
                ForEach(columns, id: \.id) { column in
                    Text(String(localized: "\(column.title) 남음")).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("확인").frame(width: 70, alignment: .leading)
                Color.clear.frame(width: 110, height: 1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            if accounts.isEmpty {
                Text("이 그룹에는 계정이 없어요").font(.callout).foregroundStyle(.secondary).padding(20)
            }
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 { Divider().padding(.leading, 14) }
                row(account, columns: columns, now: now)
                if selected == account.id {
                    AccountDetail(account: account, now: now)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                }
            }
        }
        .card()
    }

    private func row(_ account: Account, columns: [(id: String, title: String)], now: Date) -> some View {
        let snapshot = store.snapshots[account.id]
        let stale = snapshot?.isStale(at: now) ?? false
        let error = store.errors[account.id]
        return HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: selected == account.id ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).frame(width: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.displayLabel).lineLimit(1)
                    if let plan = snapshot?.plan { Text(plan).font(.caption2).foregroundStyle(.tertiary) }
                }
            }
            .frame(width: 110, alignment: .leading)
            ForEach(columns, id: \.id) { column in
                cell(snapshot?.windows.first { $0.id == column.id }, hasSnapshot: snapshot != nil, failed: error != nil, stale: stale, now: now)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(snapshot.map { AgeText.string(since: $0.observedAt, now: now) } ?? "—")
                .font(.caption)
                .foregroundStyle(stale ? Color.orange : Color.secondary)
                .frame(width: 70, alignment: .leading)
            action(account, error: error, stale: stale)
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy(duration: 0.2)) { selected = selected == account.id ? nil : account.id } }
    }

    /// 칸 하나: 막대 + “12% · 42분 후”. 막대만으로 뜻을 전하지 않는다.
    @ViewBuilder
    private func cell(_ window: UsageWindow?, hasSnapshot: Bool, failed: Bool, stale: Bool, now: Date) -> some View {
        if failed {
            Text("확인 필요").font(.caption).foregroundStyle(.orange)
        } else if !hasSnapshot {
            Text("조회 전").font(.caption).foregroundStyle(.secondary)
        } else if let window {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("\(Int((window.remaining * 100).rounded()))%")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.textStyle(for: StatusLevel(remaining: window.remaining, settings: store.alertSettings)))
                    Text(stale ? String(localized: "· 이전 값") : window.resetsAt.map { "· " + ResetText.string(until: $0, now: now) } ?? "")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(palette.color(for: BarTone(remaining: window.remaining, settings: store.alertSettings)))
                            .frame(width: proxy.size.width * window.remaining)
                    }
                }
                .frame(height: 4)
            }
            .opacity(stale ? 0.5 : 1)
        } else {
            Text("해당 없음").font(.caption).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func action(_ account: Account, error: String?, stale: Bool) -> some View {
        if store.loggingIn.contains(account.id) {
            ProgressView().controlSize(.small)
        } else if error != nil {
            Button("다시 로그인") { AccountLogin.start(for: account, store: store) }.controlSize(.small)
        } else if stale {
            Button("새로고침") { Task { await store.refresh(account) } }.controlSize(.small)
        } else {
            Button(String(localized: "열기")) { AccountOpen.open(account, store: store) }
                .controlSize(.small)
                .help(AccountOpen.title(for: account.service, label: account.displayLabel))
        }
    }
}

/// 계정을 누르면: 모든 구간(리셋 시각까지), 확인 시각, 최근 7일 추이, 구독.
private struct AccountDetail: View {
    @Environment(UsageStore.self) private var store
    @AppStorage(UsagePalette.storageKey) private var palette: UsagePalette = .indigo
    let account: Account
    let now: Date

    var body: some View {
        let snapshot = store.snapshots[account.id]
        VStack(alignment: .leading, spacing: 10) {
            if let error = store.errors[account.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
            if let snapshot {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(snapshot.windows) { window in
                        HStack {
                            Text(window.title).frame(width: 90, alignment: .leading)
                            Text("\(Int((window.remaining * 100).rounded()))% 남음").monospacedDigit()
                            if let resetsAt = window.resetsAt {
                                Text("· \(LocalDate.weekdayTime(resetsAt)) 리셋 (\(ResetText.string(until: resetsAt, now: now)))").foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                    }
                    Text("\(LocalDate.weekdayTime(snapshot.observedAt))에 확인 (\(AgeText.string(since: snapshot.observedAt, now: now)))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                trend(snapshot)
            }
            HStack(spacing: 14) {
                if let subscription = account.subscription {
                    Text("\(MoneyText.string(subscription.amount, currency: subscription.currency))/\(subscription.cycle.label)").font(.caption)
                }
                if let renewal = store.renewal(for: account, now: now) {
                    Text(RenewalText.string(renewal, now: now)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(AccountOpen.title(for: account.service, label: account.displayLabel)) { AccountOpen.open(account, store: store) }
                    .controlSize(.small)
                    .help(AccountOpen.help(for: account.service))
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    /// 최근 7일 남은 비율. 관측 사이에 기록이 없으면 그대로 비워 둔다(선으로 잇지 않음).
    @ViewBuilder
    private func trend(_ snapshot: UsageSnapshot) -> some View {
        let series = snapshot.windows.map { window in
            (window, (store.history.series[UsageHistory.key(account.id, window.id)] ?? []).filter { now.timeIntervalSince($0.t) <= 7 * 86400 })
        }.filter { $0.1.count > 1 }
        if !series.isEmpty {
            // 점을 미리 한 줄로 펴 둔다. 중첩 ForEach 안의 LineMark는 컴파일러가 타입을 늦게 풀어서 Xcode에 따라 빌드가 실패했다.
            let points: [TrendPoint] = series.flatMap { window, samples in
                segments(samples).enumerated().flatMap { index, segment in
                    segment.map { TrendPoint(time: $0.t, remaining: 1 - $0.u, line: "\(window.id)-\(index)", title: window.title) }
                }
            }
            Chart(points) { point in
                LineMark(x: .value("시각", point.time), y: .value("남음", point.remaining), series: .value("구간", point.line))
                    .foregroundStyle(by: .value("구간", point.title))
            }
            .chartYScale(domain: 0...1)
            .chartYAxis { AxisMarks(values: [0, 0.5, 1]) { AxisValueLabel(format: FloatingPointFormatStyle<Double>.Percent()) ; AxisGridLine() } }
            .frame(height: 110)
        }
    }

    /// 두 기록 사이가 1시간 넘게 비면 끊는다(그 사이 사용을 모름).
    private func segments(_ samples: [UsageSample]) -> [[UsageSample]] {
        var result: [[UsageSample]] = []
        for sample in samples {
            if let last = result.last?.last, sample.t.timeIntervalSince(last.t) <= 3600 {
                result[result.count - 1].append(sample)
            } else {
                result.append([sample])
            }
        }
        return result
    }
}

/// 추이 선의 점 하나. `line`이 같은 점끼리 선으로 잇는다(1시간 넘게 빈 곳은 다른 줄).
private struct TrendPoint: Identifiable {
    let time: Date
    let remaining: Double
    let line: String
    let title: String
    var id: String { "\(line)-\(time.timeIntervalSinceReferenceDate)" }
}
