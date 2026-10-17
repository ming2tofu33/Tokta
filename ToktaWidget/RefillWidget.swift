import SwiftUI
import WidgetKit

/// 다음에 다시 차는 계정. 빠듯한 계정이 언제 리셋되는지 미리 보여준다.
struct RefillWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "refill", provider: RefillTimeline()) { entry in
            RefillView(entry: entry)
        }
        .configurationDisplayName("다음에 차는 계정")
        .description("빠듯한 계정이 언제 다시 차는지. 누르면 그 계정으로 열립니다.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// 남은 시간 문구가 맞도록 한 시간 동안 5분마다 다시 그린다. 앱이 새 값을 쓰면 그때도 다시 그린다.
struct RefillTimeline: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: .now, data: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: .now, data: WidgetData.load()?.estimated(at: .now) ?? (context.isPreview ? .sample : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let data = WidgetData.load()
        let entries = (0..<12).map { step in
            let date = Date.now.addingTimeInterval(Double(step) * 5 * 60)
            return UsageEntry(date: date, data: data?.estimated(at: date))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct RefillView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        Group {
            if let data = entry.data {
                let refills = data.refills(after: entry.date)
                if let first = refills.first {
                    content(first: first, rest: Array(refills.dropFirst()), palette: data.displayPalette)
                        .widgetURL(WidgetData.openURL(for: first.row.id))
                } else {
                    allRoomy(palette: data.displayPalette)
                }
            } else {
                Text("Tokta를 열면 보여요").font(.caption).foregroundStyle(.secondary)
            }
        }
        .containerBackground(.background, for: .widget)
    }

    @ViewBuilder
    private func content(first: WidgetData.Refill, rest: [WidgetData.Refill], palette: UsagePalette) -> some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 4) {
                character(palette: palette)
                Spacer(minLength: 0)
                Text("다음에 차는 계정").font(.caption2).foregroundStyle(.secondary)
                Text(name(first.row)).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                Text(RefillText.until(first.at, now: entry.date)).font(.title3.weight(.semibold)).monospacedDigit()
                Text("\(percent(first.to))로 차요").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 14) {
                character(palette: palette)
                VStack(alignment: .leading, spacing: 4) {
                    Text("다음에 차는 계정").font(.caption).foregroundStyle(.secondary)
                    Text(name(first.row)).font(.headline).lineLimit(1)
                    Text("\(RefillText.until(first.at, now: entry.date)) · \(percent(first.to))로 차요")
                        .font(.callout.weight(.medium)).monospacedDigit()
                    if !rest.isEmpty {
                        Divider().padding(.vertical, 2)
                        ForEach(rest, id: \.row.id) { refill in
                            HStack {
                                Text(name(refill.row)).lineLimit(1)
                                Spacer()
                                Text(RefillText.until(refill.at, now: entry.date)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func allRoomy(palette: UsagePalette) -> some View {
        HStack(spacing: 12) {
            PixelCharacterView(mood: .happy, remaining: 1, fill: palette.platformColor(for: .plenty), fillIsLight: false, animated: false)
                .frame(width: 40, height: 40)
            Text("모든 계정이 넉넉해요").font(.callout)
            Spacer(minLength: 0)
        }
    }

    private func character(palette: UsagePalette) -> some View {
        // 곧 다시 찰 테니 반가운 얼굴, 화면은 가득.
        PixelCharacterView(mood: .joy, remaining: 1, fill: palette.platformColor(for: .plenty), fillIsLight: false, animated: false)
            .frame(width: 40, height: 40)
    }

    private func name(_ row: WidgetData.Row) -> String {
        row.label == row.serviceName ? row.serviceName : "\(row.serviceName) \(row.label)"
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}
