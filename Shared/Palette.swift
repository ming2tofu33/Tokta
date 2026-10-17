import SwiftUI

/// 사용량 단계 색 조합. 설정 → 일반에서 고른다.
/// 막대, % 글자, 소진 예측 표시, 추천 줄 배경, 메뉴바 아이콘 경고 색이 같이 쓴다.
enum UsagePalette: String, CaseIterable, Identifiable, Codable, Sendable {
    /// 평소에는 인디고 하나(여유 있으면 진하게, 줄면 연하게), 알림 기준선 아래만 코랄·로즈.
    case indigo
    /// 신호등 순서 그대로, 채도만 낮춘 세이지·샌드·테라코타·크림슨.
    case signal
    /// 여유 있으면 차가운 색, 줄수록 따뜻한 색. 틸·스카이·앰버·코랄.
    case coolWarm
    /// 평소에는 회색, 알림 기준선 아래만 코랄·로즈.
    case graphite

    static let storageKey = "usagePalette"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .indigo: String(localized: "인디고")
        case .signal: String(localized: "차분한 신호등")
        case .coolWarm: String(localized: "쿨에서 웜으로")
        case .graphite: String(localized: "그래파이트")
        }
    }

    /// 여유, 보통, 알림 기준선 아래, 위험 기준선 아래. (라이트, 다크)
    private var hexes: [(UInt32, UInt32)] {
        switch self {
        case .indigo: [(0x6366F1, 0x8B8FF8), (0xA5A8F5, 0x5559B0), (0xF0803C, 0xF59152), (0xE5484D, 0xF2555A)]
        case .signal: [(0x5FAF8E, 0x6CC29E), (0xD4B062, 0xC9A85E), (0xDE7E58, 0xE58A66), (0xCF4B4B, 0xE05A5A)]
        case .coolWarm: [(0x14B8A6, 0x2DD4BF), (0x60A5FA, 0x4F8FE0), (0xF59E0B, 0xFBBF24), (0xF2555A, 0xF87171)]
        case .graphite: [(0x6B7280, 0xA1A6B0), (0xA9AEB8, 0x5F6470), (0xF0803C, 0xF59152), (0xE5484D, 0xF2555A)]
        }
    }

    func platformColor(for tone: BarTone) -> PlatformColor {
        let index = switch tone {
        case .plenty: 0
        case .moderate: 1
        case .low: 2
        case .critical: 3
        }
        let (light, dark) = hexes[index]
        return PlatformColor.adaptive(light: light, dark: dark)
    }

    func color(for tone: BarTone) -> Color { Color(platform: platformColor(for: tone)) }

    /// % 글자와 메뉴바 아이콘. 평소에는 nil(기본 글자색, 메뉴바 색).
    func platformColor(for level: StatusLevel) -> PlatformColor? {
        switch level {
        case .normal: nil
        // StatusLevel에도 .critical이 있어서 BarTone을 꼭 적는다. 안 적으면 이 함수가 자기 자신을 부른다.
        case .warning: platformColor(for: BarTone.low)
        case .critical: platformColor(for: BarTone.critical)
        }
    }

    func textStyle(for level: StatusLevel) -> AnyShapeStyle {
        platformColor(for: level).map { AnyShapeStyle(Color(platform: $0)) } ?? AnyShapeStyle(.primary)
    }

}

/// 설정에서 색 조합을 고를 때 보여주는 네 단계 견본.
struct PaletteSwatch: View {
    let palette: UsagePalette

    var body: some View {
        HStack(spacing: 3) {
            ForEach([BarTone.plenty, .moderate, .low, .critical], id: \.self) { tone in
                Capsule().fill(palette.color(for: tone)).frame(width: 18, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}
