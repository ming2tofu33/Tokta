import SwiftUI

struct PhoneContentView: View {
    @Environment(PhoneStore.self) private var store

    var body: some View {
        NavigationStack {
            // 1분마다 다시 그려서 리셋 시각이 지난 구간을 “다시 찼을 거예요”로 바꾼다.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                content(now: context.date)
            }
            .navigationTitle("계정 현황")
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { PaletteMenu() }
            }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let raw = store.data, !raw.services.isEmpty {
            let data = raw.estimated(at: now)
            let palette = store.localPalette ?? data.palette
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    freshness(data, raw: raw, now: now)
                    // 계정이 많은 서비스(예: Claude 5계정)는 먼저, 한 줄을 다 쓰고 모든 계정을 보여준다. 나머지는 두 개씩 빈칸 없이.
                    ForEach(TileLayout.lines(data.services) { rows(of: $0, in: data).count }, id: \.self) { line in
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(line, id: \.self) { id in
                                if let service = data.services.first(where: { $0.id == id }) {
                                    NavigationLink(value: service.id) {
                                        ServiceTile(service: service, rows: rows(of: service, in: data), palette: palette,
                                                    wide: line.count == 1 && rows(of: service, in: data).count >= TileLayout.wideFrom)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            if line.count == 1 && rows(of: data.services.first { $0.id == line[0] }!, in: data).count < TileLayout.wideFrom {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                        // 나란히 놓인 두 타일 높이를 맞춘다.
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    let refills = Refill.upcoming(in: data, now: now)
                    if !refills.isEmpty {
                        Text("다음에 다시 차는 것")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                            .padding(.horizontal, 4)
                        RefillList(refills: refills, palette: palette, now: now)
                    }
                    alertNote(toPhone: raw.alerts?.toPhone ?? false)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationDestination(for: String.self) { id in
                if let service = data.services.first(where: { $0.id == id }) {
                    ServiceDetail(service: service, rows: rows(of: service, in: data), palette: palette, now: now)
                }
            }
        } else {
            ContentUnavailableView {
                Label("아직 받은 값이 없어요", systemImage: "icloud.and.arrow.down")
            } description: {
                Text(store.lastError ?? String(localized: "맥의 Tokta(응용 프로그램 폴더에 설치한 앱)가 켜져 있고 같은 iCloud 계정이면 몇 분 안에 보여요."))
            } actions: {
                Button("다시 받기") { Task { await store.refresh() } }
            }
        }
    }

    /// 그룹으로 묶여 있어도 서비스별로 모은다.
    private func rows(of service: WidgetData.Service, in data: WidgetData) -> [WidgetData.Row] {
        data.sections.flatMap(\.rows).filter { $0.serviceID == service.id }
    }

    private func alertNote(toPhone: Bool) -> some View {
        Label {
            Text(toPhone
                 ? String(localized: "알림은 이 iPhone으로 와요. 켜고 끄기와 받을 곳은 맥 Tokta 설정 → 알림에서 바꿔요.")
                 : String(localized: "알림은 지금 맥에서만 와요. 맥 Tokta 설정 → 알림에서 iPhone으로 바꿀 수 있어요."))
        } icon: {
            Image(systemName: toPhone ? "bell.badge" : "bell.slash")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    /// 맥이 마지막으로 올린 시각. 오래됐으면 추정값이 섞여 있다고 알려준다.
    private func freshness(_ data: WidgetData, raw: WidgetData, now: Date) -> some View {
        let stale = now.timeIntervalSince(raw.updatedAt) > WidgetData.staleAfter
        let estimated = data.sections.flatMap(\.rows).contains { $0.isEstimated == true }
        return VStack(alignment: .leading, spacing: 4) {
            Label {
                Text("맥에서 \(raw.updatedAt, style: .relative) 전에 받은 값")
            } icon: {
                Image(systemName: stale ? "desktopcomputer.trianglebadge.exclamationmark" : "desktopcomputer")
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(stale ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(stale ? .orange : .secondary)
            if stale {
                // 마지막 수신만으로 맥이 꺼졌다고 단정하지 않는다.
                Text(estimated ? String(localized: "새 값이 아직 도착하지 않았어요. 리셋 예정 시각이 지난 한도는 “확인 필요”로 보여줘요.") : String(localized: "새 값이 아직 도착하지 않았어요. 맥의 Tokta가 새로 읽으면 iCloud로 와요."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct PhoneRow: View {
    @Environment(PhoneStore.self) private var store
    let row: WidgetData.Row
    let palette: UsagePalette
    let now: Date

    var body: some View {
        Button { store.open(row) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.label)
                    if let plan = row.plan { Text(plan).font(.caption2).foregroundStyle(.tertiary) }
                }
                .frame(width: 96, alignment: .leading)
                PhoneBars(bars: row.bars, palette: palette)
                if row.problem != nil {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).frame(width: 46, alignment: .trailing)
                } else {
                    Percent(row: row, palette: palette).frame(width: 46, alignment: .trailing)
                }
            }
            .opacity(row.isEstimated == true ? 0.75 : 1)
            .overlay(alignment: .topTrailing) {
                if row.isEstimated == true {
                    Text("추정").font(.caption2).foregroundStyle(.secondary).offset(y: -10)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PhoneBars: View {
    let bars: [WidgetData.Bar]
    let palette: UsagePalette

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(palette.color(for: bar.tone)).frame(width: proxy.size.width * bar.remaining)
                    }
                }
                .frame(height: bars.count > 2 ? 4 : 5)
            }
        }
    }
}

private struct Percent: View {
    let row: WidgetData.Row
    let palette: UsagePalette

    var body: some View {
        // 리셋 예정 시각이 지났을 뿐 맥이 다시 읽지 않았으면 추정 100%를 숫자로 보여주지 않는다.
        if row.isEstimated == true {
            Text("확인 필요").foregroundStyle(.orange).lineLimit(1).minimumScaleFactor(0.6)
        } else {
            Text(row.remaining.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                .monospacedDigit()
                .foregroundStyle(palette.textStyle(for: row.level))
        }
    }
}

enum TileLayout {
    /// 계정이 이만큼이면 넓은 타일.
    static let wideFrom = 3

    /// 서비스 id를 줄 단위로: 넓은 타일을 먼저 하나씩, 그 뒤 나머지를 순서대로 두 개씩.
    /// 넓은 타일 사이에 좁은 타일이 혼자 끼어 옆이 비는 일이 없게 한다.
    static func lines(_ services: [WidgetData.Service], accountCount: (WidgetData.Service) -> Int) -> [[String]] {
        let wide = services.filter { accountCount($0) >= wideFrom }.map { [$0.id] }
        let narrow = services.filter { accountCount($0) < wideFrom }.map(\.id)
        return wide + stride(from: 0, to: narrow.count, by: 2).map { Array(narrow[$0..<min($0 + 2, narrow.count)]) }
    }
}

/// 서비스 하나: 가장 여유 있는 계정의 %, 아래에 계정마다 이름 · 가로 막대 · %.
/// 넓은 타일은 계정마다 구간별 막대(5시간·주간)를 겹쳐 보여준다.
private struct ServiceTile: View {
    let service: WidgetData.Service
    let rows: [WidgetData.Row]
    let palette: UsagePalette
    var wide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(service.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if !wide, let windows = windowTitles { Text(windows).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            if wide {
                // 계정마다 숫자가 있으니 큰 숫자 대신 어느 계정이 가장 여유 있는지만.
                HStack {
                    Text(service.best.map { String(localized: "가장 여유: \($0.label)") } ?? String(localized: "지금 쓸 계정 없음"))
                    Spacer()
                    // 막대가 위에서부터 어느 구간인지.
                    if let legend { Text(legend) }
                }
                .font(.caption).foregroundStyle(.secondary)
            } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let best = service.best {
                    Percent(row: best, palette: palette).font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(service.accountCount > 1 ? "→ \(best.label)" : best.label)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("—").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    Text("지금 쓸 계정 없음").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            }
            if rows.count == 1, let row = rows.first {
                // 계정 하나면 위 숫자와 같아서 이름·숫자 없이 구간별 막대만.
                WindowBars(bars: row.bars, palette: palette, height: 6)
                    .opacity(row.isEstimated == true ? 0.55 : 1)
            } else {
                let barCount = rows.map(\.bars.count).max() ?? 1
                VStack(spacing: wide ? 10 : 6) {
                    ForEach(rows) { row in
                        AccountGauge(row: row, palette: palette, wide: wide, isBest: row.id == service.best?.id, barSlots: wide ? barCount : 1)
                    }
                }
                .padding(.top, wide ? 6 : 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: wide ? nil : 120, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
    }

    /// 넓은 타일: “막대 위부터 5시간 · 주간 · Opus”
    private var legend: String? {
        let titles = rows.max { $0.bars.count < $1.bars.count }?.bars.compactMap(\.title) ?? []
        return titles.count > 1 ? String(localized: "막대 위부터 \(titles.joined(separator: " · "))") : nil
    }

    /// “5시간·주간”
    private var windowTitles: String? {
        let titles = (service.best ?? rows.first)?.bars.compactMap(\.title) ?? []
        let joined = titles.joined(separator: "·")
        // “Cursor 모델·기타 모델”처럼 길면 타일이 어수선해서 뺀다.
        return titles.isEmpty || joined.count > 10 ? nil : joined
    }
}

/// 계정 한 줄: 이름 · 가로 막대 · %. 숫자가 같이 있어서 막대를 어림할 필요가 없다.
private struct AccountGauge: View {
    let row: WidgetData.Row
    let palette: UsagePalette
    let wide: Bool
    let isBest: Bool
    /// 막대 자리 수. 넓은 타일은 계정마다 구간 수가 달라도 줄 높이를 같게 맞춘다.
    var barSlots = 1

    var body: some View {
        HStack(spacing: 8) {
            Text(row.label)
                .font(wide ? .subheadline : .caption)
                .fontWeight(isBest ? .semibold : .regular)
                .foregroundStyle(row.isEstimated == true ? Color.orange : Color.primary)
                .lineLimit(1)
                .frame(width: wide ? 72 : 40, alignment: .leading)
            // 좁은 타일은 가장 빠듯한 구간 하나, 넓은 타일은 구간마다.
            WindowBars(bars: wide ? row.bars : Array(row.bars.min { $0.remaining < $1.remaining }.map { [$0] } ?? []), palette: palette, height: 5)
                .frame(height: CGFloat(barSlots) * 5 + CGFloat(barSlots - 1) * 3)
                .opacity(row.isEstimated == true ? 0.55 : 1)
            if row.problem != nil {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).frame(width: wide ? 44 : 36, alignment: .trailing)
            } else {
                Percent(row: row, palette: palette)
                    .font((wide ? Font.subheadline : .caption).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: wide ? 44 : 36, alignment: .trailing)
            }
        }
    }
}

/// 다시 차는 것 하나: 리셋 시각이 남아 있고, 지금 덜 차 있는 구간.
struct Refill: Identifiable, Equatable {
    var id: String
    var row: WidgetData.Row
    var bar: WidgetData.Bar
    var date: Date

    /// 빨리 다시 차는 순서로. 거의 가득 찬 구간(95% 넘게 남음)은 뺀다.
    static func upcoming(in data: WidgetData, now: Date, limit: Int = 3) -> [Refill] {
        data.sections.flatMap(\.rows).filter { $0.problem == nil }.flatMap { row in
            row.bars.enumerated().compactMap { index, bar -> Refill? in
                guard let date = bar.resetsAt, date > now, bar.remaining < 0.95 else { return nil }
                return Refill(id: "\(row.id.uuidString)|\(index)", row: row, bar: bar, date: date)
            }
        }
        .sorted { $0.date < $1.date }
        .prefix(limit)
        .map { $0 }
    }
}

private struct RefillList: View {
    @Environment(PhoneStore.self) private var store
    let refills: [Refill]
    let palette: UsagePalette
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(refills.enumerated()), id: \.element.id) { index, refill in
                if index > 0 { Divider().padding(.leading, 36) }
                Button { store.open(refill.row) } label: {
                    HStack(spacing: 12) {
                        Circle().fill(palette.color(for: refill.bar.tone)).frame(width: 10, height: 10).frame(width: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(whenText(refill.date)).font(.caption.weight(.semibold)).foregroundStyle(palette.color(for: refill.bar.tone))
                            Text(verbatim: "\(refill.row.serviceName) \(refill.row.label) · \(refill.bar.title ?? String(localized: "한도"))")
                                .font(.subheadline.weight(.medium))
                        }
                        Spacer()
                        Text(refill.bar.remaining <= 0 ? String(localized: "다 씀") : String(localized: "지금 \(Int((refill.bar.remaining * 100).rounded()))%"))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// “50분 뒤 · 오전 10:31”, 하루 넘으면 “2일 뒤 · 토 오후 3:00”
    private func whenText(_ date: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        let duration = seconds >= 86400 ? String(localized: "\(seconds / 86400)일")
            : seconds >= 3600 ? String(localized: "\(seconds / 3600)시간 \(seconds % 3600 / 60)분") : String(localized: "\(max(1, seconds / 60))분")
        let formatter = DateFormatter()
        if Bundle.main.preferredLocalizations.first?.hasPrefix("ko") ?? true {
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = seconds >= 86400 ? "E a h:mm" : "a h:mm"
        } else {
            formatter.setLocalizedDateFormatFromTemplate(seconds >= 86400 ? "EEE j:mm" : "j:mm")
        }
        let time = formatter.string(from: date)
        return String(localized: "\(duration) 뒤 · \(time)")
    }
}

/// 타일을 누르면: 그 서비스 계정 전부.
private struct ServiceDetail: View {
    let service: WidgetData.Service
    let rows: [WidgetData.Row]
    let palette: UsagePalette
    let now: Date

    var body: some View {
        List {
            Section {
                ForEach(rows) { PhoneRow(row: $0, palette: palette, now: now) }
            } footer: {
                Text("계정을 누르면 그 서비스를 열어요. 어느 계정으로 열지는 iPhone에서 고를 수 없어요.")
            }
        }
        .navigationTitle(service.name)
    }
}

/// 구간마다 가로 막대 하나씩 위아래로.
private struct WindowBars: View {
    let bars: [WidgetData.Bar]
    let palette: UsagePalette
    var height: CGFloat = 5

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(palette.color(for: bar.tone)).frame(width: max(0, proxy.size.width * bar.remaining))
                    }
                }
                .frame(height: height)
            }
        }
    }
}

/// 색 조합: 기본은 맥과 같게, iPhone만 따로 고를 수도 있다(위젯도 따라간다).
private struct PaletteMenu: View {
    @Environment(PhoneStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Menu {
            Picker("색 조합", selection: $store.localPalette) {
                Text(macTitle).tag(UsagePalette?.none)
                ForEach(UsagePalette.allCases) { palette in
                    Text(palette.title).tag(UsagePalette?.some(palette))
                }
            }
        } label: {
            Image(systemName: "paintpalette")
        }
        .accessibilityLabel(Text("색 조합"))
    }

    private var macTitle: String {
        guard let mac = store.data?.palette else { return String(localized: "맥과 같게") }
        return String(localized: "맥과 같게 (\(mac.title))")
    }
}
