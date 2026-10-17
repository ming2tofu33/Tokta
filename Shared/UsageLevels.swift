import Foundation

/// 남은 양 단계. 알림 기준선(기본 20%·5%)으로 나눈다. 앱과 위젯이 같이 쓴다.
enum StatusLevel: String, Codable, Sendable {
    case normal, warning, critical
}

/// 막대 색 단계. 아래 두 단계는 알림 기준선과 같고, 그 위는 절반을 기준으로 나눈다. 색은 `UsagePalette`.
enum BarTone: String, Codable, Hashable, Sendable {
    case plenty, moderate, low, critical

    static let plentyAbove = 0.5
}
