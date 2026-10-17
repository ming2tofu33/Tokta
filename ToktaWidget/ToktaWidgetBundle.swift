import SwiftUI
import WidgetKit

@main
struct ToktaWidgetBundle: WidgetBundle {
    var body: some Widget {
        OverviewWidget()
        ServiceWidget()
        RefillWidget()
    }
}

/// 중간: 서비스마다 지금 쓸 계정. 크게: 메뉴와 같은 전체 계정 목록.
struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "overview", provider: UsageTimeline()) { entry in
            OverviewView(entry: entry)
        }
        .configurationDisplayName("지금 쓸 계정")
        .description("서비스마다 가장 여유 있는 계정. 크게 두면 모든 계정을 보여줍니다. 누르면 그 계정으로 열립니다.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// 작게: 고른 서비스 하나의 지금 쓸 계정.
struct ServiceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "service", intent: SelectServiceIntent.self, provider: ServiceTimeline()) { entry in
            ServiceView(entry: entry)
        }
        .configurationDisplayName("서비스 하나")
        .description("고른 서비스에서 지금 쓸 계정과 남은 양. 누르면 그 계정으로 열립니다.")
        .supportedFamilies([.systemSmall])
    }
}
