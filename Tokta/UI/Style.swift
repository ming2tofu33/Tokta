import SwiftUI

/// v2 디자인(맥다운 반투명 바탕 + 한 문장 제목)에서 함께 쓰는 모양.
/// design/app-direction-v2/index.html
extension Service {
    /// 서비스 작은 아이콘 색.
    var tint: Color {
        switch self {
        case .chatgpt: Color(red: 0.06, green: 0.64, blue: 0.50)
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .grok: Color(red: 0.42, green: 0.42, blue: 0.45)
        // 검정 타일은 다크 모드 바탕에 묻혀서 그때만 밝힌다.
        case .cursor: Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.32, alpha: 1) : NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1) })
        case .grokBot: Color(red: 0.30, green: 0.30, blue: 0.34)
        case .antigravity: Color(red: 0.26, green: 0.52, blue: 0.96)
        }
    }

    var initial: String { String(displayName.prefix(1)) }
}

/// 둥근 네모 안에 서비스 로고(흰색). 로고 파일이 없으면 첫 글자.
/// 로고는 `Assets.xcassets`의 `Logo-<서비스 rawValue>`(한 가지 색 SVG, 템플릿으로 그림). 예: `Logo-claude`.
/// 출처: LobeHub Icons `@lobehub/icons-static-svg@1.95.1`(MIT). 로고 자체는 각 회사 상표라 서비스를 가리키는 데만 쓴다.
struct ServiceBadge: View {
    let service: Service
    var size: CGFloat = 22

    var body: some View {
        Group {
            // Grok Bot은 Grok 로고를 같이 쓴다.
            if let logo = NSImage(named: "Logo-\(service == .grokBot ? Service.grok.rawValue : service.rawValue)") {
                Image(nsImage: logo)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.2)
            } else {
                Text(service.initial)
                    .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(service.tint, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
        .accessibilityLabel(service.displayName)
    }
}

/// 간격과 모서리. 메뉴는 바깥 여백 8, 내용 시작선 20(바깥 8 + 안쪽 12)에 맞춘다.
/// 모서리는 카드 14 · 카드 안 줄과 버튼 8 · 작은 칸 6으로, 안쪽이 바깥보다 작게.
enum Layout {
    static let inset: CGFloat = 8
    static let padding: CGFloat = 12
    static let contentEdge: CGFloat = inset + padding
    static let cardRadius: CGFloat = 14
    static let rowRadius: CGFloat = 8
    static let smallRadius: CGFloat = 6
}

extension Font {
    /// 남은 % 같은 숫자. 둥근 글꼴에 자릿수 폭을 맞춰서 바뀌어도 흔들리지 않는다.
    static func usageNumber(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// 카드. macOS 26부터는 Liquid Glass, 그 전에는 흰(다크에선 짙은) 판.
struct CardBackground: ViewModifier {
    var radius: CGFloat = 14
    /// 유리에 아주 옅게 섞는 색. 맨 위 카드처럼 눈에 띄어야 하는 카드에만.
    var tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26, *) {
            content.glassEffect(tint.map { Glass.regular.tint($0.opacity(0.12)) } ?? .regular, in: shape)
        } else {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
                .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
        }
    }
}

extension View {
    func card(radius: CGFloat = 14, tint: Color? = nil) -> some View { modifier(CardBackground(radius: radius, tint: tint)) }

    /// 값이 바뀔 때만 움직인다. “동작 줄이기”를 켜면 바로 바뀐다.
    func motion<V: Equatable>(_ animation: Animation = .snappy(duration: 0.35), value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }

    /// 숫자가 바뀌면 자리마다 굴러가듯 바뀐다.
    func rollingNumber(_ value: Double) -> some View {
        contentTransition(.numericText(value: value)).motion(value: value)
    }

    /// 눈에 띄는 버튼. macOS 26부터는 색이 든 유리 버튼, 그 전에는 색 캡슐.
    @ViewBuilder
    func prominentButton(tint: Color) -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent).tint(tint)
        } else {
            buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(tint)
        }
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

/// 맨 위 한 문장 제목.
struct Headline: View {
    let calm: String
    var warning: String?
    var size: CGFloat = 19

    var body: some View {
        (Text(calm) + (warning.map { Text(verbatim: " ") + Text($0).foregroundColor(.orange) } ?? Text(verbatim: "")))
            .font(TitleFont.font(size: size))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 한 문장 제목 글꼴. 세리프(New York·나눔명조)를 써 봤다가 사용자 의견으로 기본 글꼴로 돌림(2026-10-16).
enum TitleFont {
    static func font(size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
}
