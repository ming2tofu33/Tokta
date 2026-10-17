import SwiftUI

/// Tokta 창 “오늘 하루”. 계정마다 24시간 줄 위에 쓴 때(색), 바닥이었던 때(주황), 리셋(초록 동그라미), 지금(세로선).
struct DayTimelineView: View {
    @Environment(UsageStore.self) private var store
    @AppStorage(UsagePalette.storageKey) private var palette: UsagePalette = .indigo
    /// 이 계정들만. nil이면 모든 계정.
    var accounts: [Account]? = nil

    var body: some View {
        // 1분마다 다시 그려서 “지금” 선과 진행 중인 구간이 따라간다.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeline = DayTimeline.make(accounts: accounts ?? store.accounts, history: store.history, now: context.date)
            VStack(alignment: .leading, spacing: 10) {
                header
                if timeline.rows.isEmpty {
                    Text("오늘 기록이 아직 없어요. 계정을 읽을 때마다 쌓여요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    hourLabels
                    ForEach(timeline.rows, id: \.account.id) { row in
                        HStack(spacing: 12) {
                            HStack(spacing: 6) {
                                ServiceBadge(service: row.account.service, size: 16)
                                Text(AccountName.short(row.account, among: store.accounts))
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .frame(width: 130, alignment: .leading)
                            track(row, timeline: timeline)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityText(row))
                    }
                    HStack(spacing: 12) {
                        Color.clear.frame(width: 130, height: 1)
                        GeometryReader { proxy in
                            Text("지금 \(LocalDate.time(timeline.now))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                .position(x: proxy.size.width * timeline.position(timeline.now), y: 6)
                        }
                        .frame(height: 12)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .card()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("오늘 하루").font(.headline)
            Text("언제 썼고, 언제 막혔고, 언제 다시 찼는지").font(.caption).foregroundStyle(.secondary)
            Spacer()
            legend(color: palette.color(for: .plenty), text: String(localized: "쓴 때"))
            legend(color: palette.color(for: .low), text: String(localized: "바닥"))
            HStack(spacing: 4) {
                Circle().strokeBorder(.green, lineWidth: 2).frame(width: 8, height: 8)
                Text("리셋")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 14, height: 6)
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var hourLabels: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 130, height: 1)
            HStack {
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    if hour > 0 { Spacer() }
                    Text(HourText.string(hour)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func track(_ row: DayTimeline.Row, timeline: DayTimeline) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5).fill(.quaternary.opacity(0.6))
                ForEach(Array(row.used.enumerated()), id: \.offset) { _, span in
                    bar(span, color: palette.color(for: .plenty), width: width, timeline: timeline)
                }
                ForEach(Array(row.empty.enumerated()), id: \.offset) { _, span in
                    bar(span, color: palette.color(for: .low), width: width, timeline: timeline)
                }
                ForEach(row.resets, id: \.self) { reset in
                    Circle()
                        .strokeBorder(.green, lineWidth: 2)
                        .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                        .frame(width: 9, height: 9)
                        .offset(x: width * timeline.position(reset) - 4.5)
                }
                Rectangle()
                    .fill(.primary.opacity(0.5))
                    .frame(width: 1.5, height: 24)
                    .offset(x: width * timeline.position(timeline.now))
            }
        }
        .frame(height: 16)
    }

    private func bar(_ span: DayTimeline.Span, color: Color, width: CGFloat, timeline: DayTimeline) -> some View {
        let x = width * timeline.position(span.start)
        // 아주 짧게 쓴 때도 보이게 최소 3pt.
        let length = max(3, width * (timeline.position(span.end) - timeline.position(span.start)))
        return Capsule().fill(color).frame(width: length, height: 8).offset(x: x)
    }

    private func accessibilityText(_ row: DayTimeline.Row) -> String {
        let name = AccountName.short(row.account, among: store.accounts)
        let spans = row.used.map { "\(LocalDate.time($0.start))–\(LocalDate.time($0.end))" }.joined(separator: ", ")
        var text = String(localized: "\(name), 쓴 때 \(spans.isEmpty ? "없음" : spans)")
        if !row.empty.isEmpty { text += String(localized: ", 바닥 \(row.empty.count)번") }
        if !row.resets.isEmpty { text += String(localized: ", 리셋 \(row.resets.count)번") }
        return text
    }
}
