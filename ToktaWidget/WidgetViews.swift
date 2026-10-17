import SwiftUI
import WidgetKit

/// 앱이 꺼져 있거나 읽기가 멈춰서 값이 오래되면 흐리게 보여준다.
private func isStale(_ date: Date?, now: Date) -> Bool {
    date.map { now.timeIntervalSince($0) > WidgetData.staleAfter } ?? false
}

struct OverviewView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        Group {
            if let data = entry.data, !data.services.isEmpty {
                if family == .systemLarge { AllAccounts(data: data, now: entry.date) } else { ServiceList(data: data, now: entry.date) }
            } else {
                EmptyState()
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

struct ServiceView: View {
    let entry: UsageEntry

    var body: some View {
        Group {
            if let data = entry.data, let service = data.services.first(where: { $0.id == entry.serviceID }) ?? data.services.first {
                SingleService(service: service, palette: data.displayPalette, updatedAt: data.updatedAt, now: entry.date)
            } else {
                EmptyState()
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

private struct Header: View {
    let title: String
    let updatedAt: Date
    let now: Date

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if isStale(updatedAt, now: now) {
                Label { Text(updatedAt, style: .relative) } icon: { Image(systemName: "clock.arrow.circlepath") }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 중간: 서비스마다 한 줄. 줄을 누르면 그 계정으로 연다.
private struct ServiceList: View {
    let data: WidgetData
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Header(title: String(localized: "지금 쓸 계정"), updatedAt: data.updatedAt, now: now)
            ForEach(data.services.prefix(4)) { service in
                if let best = service.best {
                    Link(destination: WidgetData.openURL(for: best.id)) {
                        UsageLine(
                            title: service.accountCount > 1 ? "\(service.name) · \(best.label)" : service.name,
                            row: best, palette: data.displayPalette, now: now
                        )
                    }
                } else {
                    HStack {
                        Text(service.name)
                        Spacer()
                        Text("쓸 수 있는 계정 없음").font(.caption).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// 크게: 메뉴와 같은 묶음별 전체 계정. 넘치면 몇 개 더 있는지 적는다.
private struct AllAccounts: View {
    let data: WidgetData
    let now: Date
    private let maxLines = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Header(title: "Tokta", updatedAt: data.updatedAt, now: now)
            let (visible, hidden) = layout()
            ForEach(visible) { section in
                Text(section.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 3)
                ForEach(section.rows) { row in
                    Link(destination: WidgetData.openURL(for: row.id)) {
                        UsageLine(title: row.label, row: row, palette: data.displayPalette, now: now)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(row.isRecommended ? data.displayPalette.color(for: .plenty).opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
            if hidden > 0 {
                Text("계정 \(hidden)개 더 · Tokta 메뉴에서 보기").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    /// 묶음 제목과 계정 줄을 합쳐 `maxLines`줄까지만 넣는다.
    private func layout() -> ([WidgetData.Section], Int) {
        var lines = 0, hidden = 0
        var visible: [WidgetData.Section] = []
        for section in data.sections {
            let room = maxLines - lines - 1
            guard room > 0 else { hidden += section.rows.count; continue }
            var shown = section
            shown.rows = Array(section.rows.prefix(room))
            hidden += section.rows.count - shown.rows.count
            lines += 1 + shown.rows.count
            visible.append(shown)
        }
        return (visible, hidden)
    }
}

/// 작게: 서비스 하나. 누르면 지금 쓸 계정으로 연다.
private struct SingleService: View {
    let service: WidgetData.Service
    let palette: UsagePalette
    let updatedAt: Date
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(service.name).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if isStale(updatedAt, now: now) { Image(systemName: "clock.arrow.circlepath").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if let best = service.best {
                HStack(spacing: 8) {
                    // 화면이 찬 높이 = 가장 빠듯한 구간의 남은 양, 얼굴 = 단계
                    let tone = best.bars.min { $0.remaining < $1.remaining }?.tone ?? .plenty
                    PixelCharacterView(mood: best.mood ?? .calm, remaining: best.remaining ?? 0,
                                       fill: palette.platformColor(for: tone), fillIsLight: tone == .moderate, animated: false)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(service.accountCount > 1 ? String(localized: "지금 쓸 계정") : String(localized: "남은 양")).font(.caption2).foregroundStyle(.secondary)
                        Text(best.label).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline) {
                    Percent(row: best, palette: palette).font(.title2.weight(.medium))
                    Spacer()
                    if service.accountCount > 1 {
                        Text("\(service.accountCount)개 중 \(service.roomyCount)개 여유").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Bars(bars: best.bars, palette: palette, height: 5)
            } else {
                Text("쓸 수 있는 계정 없음").font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .opacity(isStale(service.best?.observedAt, now: now) ? 0.5 : 1)
        .widgetURL(service.best.map { WidgetData.openURL(for: $0.id) })
    }
}

/// 이름 · 막대 · %. 오류가 있으면 % 대신 표시.
private struct UsageLine: View {
    let title: String
    let row: WidgetData.Row
    let palette: UsagePalette
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Bars(bars: row.bars, palette: palette, height: row.bars.count > 2 ? 3 : 4).frame(width: 90)
            Group {
                if row.problem != nil {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else {
                    Percent(row: row, palette: palette)
                }
            }
            .frame(width: 38, alignment: .trailing)
        }
        .font(.callout)
        .opacity(isStale(row.observedAt, now: now) ? 0.5 : 1)
    }
}

private struct Percent: View {
    let row: WidgetData.Row
    let palette: UsagePalette

    var body: some View {
        // 리셋 예정 시각이 지났을 뿐 다시 읽지 않은 값은 확정된 %처럼 보여주지 않는다.
        if row.isEstimated == true {
            Text("확인 필요").foregroundStyle(.orange).lineLimit(1).minimumScaleFactor(0.5)
        } else {
            Text(row.remaining.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                .monospacedDigit()
                .foregroundStyle(palette.textStyle(for: row.level))
        }
    }
}

private struct Bars: View {
    let bars: [WidgetData.Bar]
    let palette: UsagePalette
    let height: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(palette.color(for: bar.tone)).frame(width: proxy.size.width * bar.remaining)
                    }
                }
                .frame(height: height)
            }
        }
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.33percent").font(.title2).foregroundStyle(.secondary)
            Text("Tokta에서 계정을 추가하세요").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
