import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Tokta 캐릭터의 표정. 단계와 같은 기준으로 앱에서 고른다(`CharacterMood.of`).
enum CharacterMood: String, Codable, Sendable {
    /// 여유 ^_^
    case happy
    /// 보통 •_•
    case calm
    /// 빠듯 >_< (땀방울)
    case squeeze
    /// 다 씀 -_- (Z)
    case sleep
    /// 방금 리셋 ^o^ (반짝임)
    case joy

    var emoticon: String {
        switch self {
        case .happy: "^_^"
        case .calm: "•_•"
        case .squeeze: ">_<"
        case .sleep: "-_-"
        case .joy: "^o^"
        }
    }
}

/// 16x16 캐릭터 그림. 맥 창은 `design/pixel-character-v5/sprites.py`, 나머지는 `PixelShape`(v6)와 같은 그림을 코드로 찍는다.
/// 화면이 아래부터 빛으로 찬 높이 = 남은 한도, 얼굴 = 표정.
enum PixelSprite {
    enum Ink: Hashable {
        case frame, titleBar, red, yellow, green, screen, fill, faceLight, faceDark, sweat, spark, zzz
        /// 캐릭터마다 한 가지 강조색(칩 다리, 물약 마개, 로봇 안테나). `PixelCharacter.accent`.
        case accent
        /// 머그컵 리셋 때 오르는 김.
        case steam
    }

    static let size = 16

    /// `grid[y][x]`. 비어 있으면 투명. `fillIsLight`면 빛 위의 얼굴을 진한 색으로 그린다.
    static func grid(mood: CharacterMood, remaining: Double, fillIsLight: Bool, blink: Bool = false, cursor: Bool = true,
                     character: PixelCharacter = .window) -> [[Ink?]] {
        guard let shape = character.shape else {
            return windowGrid(mood: mood, remaining: remaining, fillIsLight: fillIsLight, blink: blink, cursor: cursor)
        }
        return shape.grid(mood: mood, remaining: remaining, fillIsLight: fillIsLight, blink: blink, cursor: cursor)
    }

    private static func windowGrid(mood: CharacterMood, remaining: Double, fillIsLight: Bool, blink: Bool, cursor: Bool) -> [[Ink?]] {
        var g = [[Ink?]](repeating: [Ink?](repeating: nil, count: size), count: size)
        func put(_ x: Int, _ y: Int, _ ink: Ink) { if (0..<size).contains(x), (0..<size).contains(y) { g[y][x] = ink } }
        // 창 테두리와 제목 줄, 신호등 버튼
        for y in 1...14 { for x in 0..<size { put(x, y, .frame) } }
        for (x, y) in [(0, 1), (15, 1), (0, 14), (15, 14)] { g[y][x] = nil }
        for x in 1...14 { put(x, 2, .titleBar); put(x, 3, .titleBar) }
        for (x, ink) in [(2, Ink.red), (4, .yellow), (6, .green)] { put(x, 2, ink); put(x, 3, ink) }
        // 화면: 아래부터 남은 만큼 빛
        let top = 5, bottom = 13
        let level = bottom + 1 - Int((Double(bottom - top + 1) * min(1, max(0, remaining))).rounded())
        for y in top...bottom { for x in 1...14 { put(x, y, y >= level ? .fill : .screen) } }

        // 얼굴: 왼눈 x=5, 오른눈 x=10, 눈 윗줄 y=7, 입 y=10
        let l = 5, r = 10, ey = 7, my = 10
        func caret(_ x: Int) -> [(Int, Int)] { [(x - 1, ey + 1), (x, ey), (x + 1, ey + 1)] }
        func dot(_ x: Int) -> [(Int, Int)] { [(x, ey), (x, ey + 1)] }
        func line(_ x: Int) -> [(Int, Int)] { [(x - 1, ey + 1), (x, ey + 1), (x + 1, ey + 1)] }
        let under = [(7, my), (8, my), (9, my)]
        var eyes: [(Int, Int)]
        var mouth = under
        switch mood {
        case .happy: eyes = caret(l) + caret(r)
        case .calm: eyes = dot(l) + dot(r)
        case .squeeze: eyes = [(l - 1, ey), (l, ey + 1), (l - 1, ey + 2), (r + 1, ey), (r, ey + 1), (r + 1, ey + 2)]
        case .sleep: eyes = line(l) + line(r); mouth = [(8, my)]
        case .joy:
            eyes = caret(l) + caret(r)
            mouth = [(7, my - 1), (8, my - 1), (9, my - 1), (7, my), (9, my), (7, my + 1), (8, my + 1), (9, my + 1)]
        }
        if blink && mood != .sleep { eyes = line(l) + line(r) }
        func ink(_ x: Int, _ y: Int) -> Ink { g[y][x] == .fill && fillIsLight ? .faceDark : .faceLight }
        for (x, y) in eyes + mouth { put(x, y, ink(x, y)) }
        if cursor && mood != .sleep { put(13, my, ink(13, my)) }

        // 바깥 장식
        func deco(_ points: [(Int, Int)], _ i: Ink) { for (x, y) in points where g[y][x] == nil { put(x, y, i) } }
        switch mood {
        case .squeeze: deco([(15, 0), (15, 1), (14, 0)], .sweat)
        case .sleep:   // 잘 때는 커서 자리(화면 안 입 오른쪽)에 Z
            for (dx, dy) in [(0, 0), (1, 0), (2, 0), (3, 0), (2, 1), (1, 2), (0, 3), (1, 3), (2, 3), (3, 3)] { put(11 + dx, 9 + dy, .zzz) }
        case .joy: deco([(0, 0), (15, 0), (0, 15), (15, 15)], .spark)
        case .happy, .calm: break
        }
        return g
    }

    /// 화면 빛 색과 함께 그릴 색. 테두리·화면은 다크 모드에서 배경에 묻히지 않게 조금 밝힌다.
    static func color(_ ink: Ink, fill: PlatformColor, character: PixelCharacter = .window) -> PlatformColor {
        switch ink {
        case .frame: .adaptive(light: 0x1E1B4B, dark: 0x4A4690)
        case .titleBar: .adaptive(light: 0xE3E5FB, dark: 0xD9DCF7)
        case .red: .rgb(0xFF5F57)
        case .yellow: .rgb(0xFEBC2E)
        case .green: .rgb(0x28C840)
        case .screen: .adaptive(light: 0x24214F, dark: 0x1A1840)
        case .fill: fill
        case .faceLight: .rgb(0xFFFFFF)
        case .faceDark: .rgb(0x1E1B4B)
        case .sweat: .rgb(0x7DD3FC)
        case .spark: .rgb(0xF59E0B)
        case .zzz: .rgb(0x8B8FF8)
        case .accent: .rgb(character.shape?.accent ?? 0x8B8FF8)
        case .steam: .rgb(0xA5A8F5)
        }
    }

    #if canImport(AppKit)
    /// 메뉴바용 그림. 1픽셀 = 1pt라서 레티나에서도 선명하다.
    static func image(mood: CharacterMood, remaining: Double, fill: NSColor, fillIsLight: Bool, character: PixelCharacter = .window) -> NSImage {
        let cells = grid(mood: mood, remaining: remaining, fillIsLight: fillIsLight, character: character)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            for (y, row) in cells.enumerated() {
                for (x, ink) in row.enumerated() {
                    guard let ink else { continue }
                    color(ink, fill: fill, character: character).setFill()
                    NSRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
    #endif

}

/// 캐릭터 그림. `animated`면 커서와 눈이 깜빡이고, 방금 리셋(^o^)이면 화면이 아래부터 차오른다.
/// 위젯처럼 움직일 수 없는 곳에서는 `animated: false`.
struct PixelCharacterView: View {
    let mood: CharacterMood
    let remaining: Double
    let fill: PlatformColor
    var fillIsLight = false
    var animated = true
    /// nil이면 설정에서 고른 캐릭터.
    var character: PixelCharacter?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PixelCharacter.storageKey, store: PixelCharacter.defaults) private var stored: PixelCharacter = .window
    @State private var appearedAt = Date.now

    var body: some View {
        if animated && !reduceMotion {
            TimelineView(.periodic(from: appearedAt, by: 0.25)) { context in
                let t = context.date.timeIntervalSince(appearedAt)
                let tick = Int(t / 0.25)
                // 커서는 0.5초마다, 눈은 4초에 한 번 0.25초 깜빡인다. 리셋이면 처음 1초 동안 0 → 1/4 → … 로 차오른다.
                let shown = mood == .joy && tick < 4 ? Double(tick) / 4 : remaining
                pixels(blink: tick % 16 == 15, cursor: tick / 2 % 2 == 0, remaining: shown)
            }
            .onAppear { appearedAt = .now }
        } else {
            pixels(blink: false, cursor: true, remaining: remaining)
        }
    }

    private func pixels(blink: Bool, cursor: Bool, remaining: Double) -> some View {
        Canvas { context, size in
            let cell = size.width / CGFloat(PixelSprite.size)
            let shown = character ?? stored
            let cells = PixelSprite.grid(mood: mood, remaining: remaining, fillIsLight: fillIsLight, blink: blink, cursor: cursor, character: shown)
            for (y, row) in cells.enumerated() {
                for (x, ink) in row.enumerated() {
                    guard let ink else { continue }
                    let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(Color(platform: PixelSprite.color(ink, fill: fill, character: shown))))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(mood.emoticon)
    }
}
