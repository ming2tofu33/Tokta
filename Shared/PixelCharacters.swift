import Foundation

/// 고를 수 있는 캐릭터. 모두 같은 규칙을 따라서 어떤 캐릭터든 읽는 법이 같다:
/// 16x16, 몸 안 게이지 칸이 남은 한도만큼 빛으로 차고, 얼굴은 같은 다섯 표정(`CharacterMood`).
/// 그림은 `design/pixel-character-v6/sprites.py`와 같다. 맥 창(`window`)만 v5 그림(`PixelSprite.windowGrid`).
enum PixelCharacter: String, CaseIterable, Codable, Identifiable, Sendable {
    case window, battery, chip, mug, potion, slime, robot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .window: String(localized: "맥 창")
        case .battery: String(localized: "배터리")
        case .chip: String(localized: "칩")
        case .mug: String(localized: "머그컵")
        case .potion: String(localized: "물약")
        case .slime: String(localized: "슬라임")
        case .robot: String(localized: "로봇")
        }
    }

    // MARK: 저장

    /// 앱·위젯이 같이 읽도록 App Group 설정에 둔다. iPhone은 맥이 보낸 값(`WidgetData.character`)을 받아 여기에 쓴다.
    static let storageKey = "pixelCharacter"
    nonisolated(unsafe) static let defaults = UserDefaults(suiteName: BuildConfig.appGroup)

    static var current: PixelCharacter {
        get { defaults?.string(forKey: storageKey).flatMap(PixelCharacter.init) ?? .window }
        set { defaults?.set(newValue.rawValue, forKey: storageKey) }
    }

    /// 맥 창이 아닌 캐릭터의 지도.
    var shape: PixelShape? {
        switch self {
        case .window: nil
        case .battery:
            PixelShape(map: [
            "................",
            "................",
            "OOOOOOOOOOOOOO..",
            "OSSSSSSSSSSSSO..",
            "OSSSSSSSSSSSSO..",
            "OSSSSSSSSSSSSOO.",
            "OSSSSSSSSSSSSOO.",
            "OSSSSSSSSSSSSOO.",
            "OSSSSSSSSSSSSOO.",
            "OSSSSSSSSSSSSOO.",
            "OSSSSSSSSSSSSO..",
            "OSSSSSSSSSSSSO..",
            "OOOOOOOOOOOOOO..",
            "................",
            "................",
            "................",
            ], accent: 0x28C840, face: (4, 6), z: (13, 0), fillsRight: true, steams: false)
        case .chip:
            PixelShape(map: [
            "....A.A..A.A....",
            "....A.A..A.A....",
            "..OOOOOOOOOOOO..",
            "..OLLLLLLLLLLO..",
            "AAOLSSSSSSSSLOAA",
            "..OLSSSSSSSSLO..",
            "AAOLSSSSSSSSLOAA",
            "..OLSSSSSSSSLO..",
            "..OLSSSSSSSSLO..",
            "AAOLSSSSSSSSLOAA",
            "..OLSSSSSSSSLO..",
            "AAOLSSSSSSSSLOAA",
            "..OLLLLLLLLLLO..",
            "..OOOOOOOOOOOO..",
            "....A.A..A.A....",
            "....A.A..A.A....",
            ], accent: 0xA7A9C9, face: (5, 6), z: (13, 0), fillsRight: false, steams: false)
        case .mug:
            PixelShape(map: [
            "................",
            "................",
            "................",
            "OOOOOOOOOOOO....",
            "OSSSSSSSSSSO....",
            "OSSSSSSSSSSOOO..",
            "OSSSSSSSSSSO.OO.",
            "OSSSSSSSSSSO..O.",
            "OSSSSSSSSSSO..O.",
            "OSSSSSSSSSSO.OO.",
            "OSSSSSSSSSSOOO..",
            "OSSSSSSSSSSO....",
            "OSSSSSSSSSSO....",
            ".OSSSSSSSSO.....",
            "..OOOOOOOO......",
            "................",
            ], accent: 0xE3E5FB, face: (3, 6), z: (13, 1), fillsRight: false, steams: true)
        case .potion:
            PixelShape(map: [
            ".....AAAAAA.....",
            ".....AAAAAA.....",
            "......OSSO......",
            "......OSSO......",
            "....OOSSSSOO....",
            "...OSSSSSSSSO...",
            "..OSSSSSSSSSSO..",
            ".OSLSSSSSSSSSSO.",
            ".OSLSSSSSSSSSSO.",
            ".OSSSSSSSSSSSSO.",
            ".OSSSSSSSSSSSSO.",
            ".OSSSSSSSSSSSSO.",
            "..OSSSSSSSSSSO..",
            "...OSSSSSSSSO...",
            "....OOOOOOOO....",
            "................",
            ], accent: 0xC08A5B, face: (5, 7), z: (12, 1), fillsRight: false, steams: false)
        case .slime:
            PixelShape(map: [
            "................",
            "................",
            "................",
            ".......OO.......",
            ".....OOSSOO.....",
            "....OSSSSSSO....",
            "...OSSSSSSSSO...",
            "..OSSSSSSSSSSO..",
            ".OSSSSSSSSSSSSO.",
            ".OSSSSSSSSSSSSO.",
            "OSSSSSSSSSSSSSSO",
            "OSSSSSSSSSSSSSSO",
            "OSSSSSSSSSSSSSSO",
            ".OOOOOOOOOOOOOO.",
            "................",
            "................",
            ], accent: 0x6366F1, face: (5, 7), z: (12, 1), fillsRight: false, steams: false)
        case .robot:
            PixelShape(map: [
            ".......AA.......",
            "........O.......",
            ".OOOOOOOOOOOOOO.",
            ".OLLLLLLLLLLLLO.",
            ".OLSSSSSSSSSSLO.",
            ".OLSSSSSSSSSSLO.",
            "OOLSSSSSSSSSSLOO",
            "OOLSSSSSSSSSSLOO",
            "OOLSSSSSSSSSSLOO",
            "OOLSSSSSSSSSSLOO",
            ".OLSSSSSSSSSSLO.",
            ".OLSSSSSSSSSSLO.",
            ".OLLLLLLLLLLLLO.",
            ".OOOOOOOOOOOOOO.",
            "...OO......OO...",
            "................",
            ], accent: 0xFF5F57, face: (5, 6), z: (12, 0), fillsRight: false, steams: false)
        }
    }
}

/// 지도로 그리는 캐릭터. `.` 빈칸 · `O` 테두리 · `L` 밝은 면 · `S` 게이지 칸 · `A` 강조색.
struct PixelShape: Sendable {
    let map: [String]
    let accent: UInt32
    /// 왼눈 가운데 x와 눈 윗줄 y. 오른눈은 x+5, 입은 y+3, 커서는 x+8(게이지 칸일 때만).
    let face: (x: Int, y: Int)
    /// 잘 때 Z(3x3)의 왼쪽 위.
    let z: (x: Int, y: Int)
    /// 배터리처럼 왼쪽부터 찬다. 아니면 아래부터.
    var fillsRight = false
    /// 리셋 때 위로 김이 오른다(머그컵).
    var steams = false

    typealias Ink = PixelSprite.Ink

    func grid(mood: CharacterMood, remaining: Double, fillIsLight: Bool, blink: Bool, cursor: Bool) -> [[Ink?]] {
        let size = PixelSprite.size
        let rows = map.map(Array.init)
        var g = [[Ink?]](repeating: [Ink?](repeating: nil, count: size), count: size)
        var gauge: [(Int, Int)] = []
        for y in 0..<size {
            for x in 0..<size {
                switch rows[y][x] {
                case "O": g[y][x] = .frame
                case "L": g[y][x] = .titleBar
                case "A": g[y][x] = .accent
                case "S": gauge.append((x, y))
                default: break
                }
            }
        }
        // 게이지: 남은 만큼 빛. 반올림은 디자인 스크립트(파이썬 round)와 같게 짝수 쪽으로.
        let share = min(1, max(0, remaining))
        func count(_ n: Int) -> Int { Int((Double(n) * share).rounded(.toNearestOrEven)) }
        let lit: (Int, Int) -> Bool
        if fillsRight {
            let xs = Set(gauge.map(\.0)).sorted()
            let on = Set(xs.prefix(count(xs.count)))
            lit = { x, _ in on.contains(x) }
        } else {
            let ys = Set(gauge.map(\.1)).sorted()
            let on = Set(ys.suffix(count(ys.count)))
            lit = { _, y in on.contains(y) }
        }
        for (x, y) in gauge { g[y][x] = lit(x, y) ? .fill : .screen }

        // 얼굴
        let (lx, ey) = face, my = ey + 3, c = lx + 3
        func caret(_ x: Int) -> [(Int, Int)] { [(x - 1, ey + 1), (x, ey), (x + 1, ey + 1)] }
        func dot(_ x: Int) -> [(Int, Int)] { [(x, ey), (x, ey + 1)] }
        func line(_ x: Int) -> [(Int, Int)] { [(x - 1, ey + 1), (x, ey + 1), (x + 1, ey + 1)] }
        let r = lx + 5
        var eyes: [(Int, Int)]
        var mouth = [(c - 1, my), (c, my), (c + 1, my)]
        switch mood {
        case .happy: eyes = caret(lx) + caret(r)
        case .calm: eyes = dot(lx) + dot(r)
        case .squeeze: eyes = [(lx - 1, ey), (lx, ey + 1), (lx - 1, ey + 2), (r + 1, ey), (r, ey + 1), (r + 1, ey + 2)]
        case .sleep: eyes = line(lx) + line(r); mouth = [(c, my)]
        case .joy:
            eyes = caret(lx) + caret(r)
            mouth = [(c - 1, my - 1), (c, my - 1), (c + 1, my - 1), (c - 1, my), (c + 1, my), (c - 1, my + 1), (c, my + 1), (c + 1, my + 1)]
        }
        if blink && mood != .sleep { eyes = line(lx) + line(r) }
        var points = eyes + mouth
        if cursor && mood != .sleep && rows[my][lx + 8] == "S" { points.append((lx + 8, my)) }
        for (x, y) in points { g[y][x] = g[y][x] == .fill && fillIsLight ? .faceDark : .faceLight }

        // 바깥 장식은 빈칸에만
        func deco(_ points: [(Int, Int)], _ ink: Ink) {
            for (x, y) in points where (0..<size).contains(x) && (0..<size).contains(y) && g[y][x] == nil { g[y][x] = ink }
        }
        switch mood {
        case .squeeze: deco([(15, 0), (15, 1), (14, 0)], .sweat)
        case .sleep: deco([(0, 0), (1, 0), (2, 0), (1, 1), (0, 2), (1, 2), (2, 2)].map { (z.x + $0.0, z.y + $0.1) }, .zzz)
        case .joy:
            if steams { deco([(3, 0), (3, 1), (4, 2), (6, 0), (6, 1), (7, 2), (9, 0), (9, 1), (8, 2)], .steam) }
            deco([(0, 0), (15, 0), (0, 15), (15, 15)], .spark)
        case .happy, .calm: break
        }
        return g
    }
}
