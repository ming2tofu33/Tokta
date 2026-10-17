import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Tokta

/// 앱이 찍는 캐릭터가 `design/pixel-character-v6/sprites.py`가 만든 그림과 한 칸도 다르지 않은지 본다.
struct PixelCharacterTests {
    /// 디자인 스크립트의 상태: (파일 이름, 표정, 남은 비율, 빛 색, 밝은 빛인지)
    private static let states: [(String, CharacterMood, Double, UInt32, Bool)] = [
        ("plenty", .happy, 0.92, 0x6366F1, false),
        ("moderate", .calm, 0.55, 0xA5A8F5, true),
        ("low", .squeeze, 0.2, 0xF0803C, false),
        ("empty", .sleep, 0, 0xE5484D, false),
        ("reset", .joy, 1, 0x6366F1, false),
    ]

    private static let sprites = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "design/pixel-character-v6/sprites")

    /// 라이트 모드 색. 디자인 스크립트의 색표와 같다.
    private static func hex(_ ink: PixelSprite.Ink?, fill: UInt32, accent: UInt32) -> UInt32? {
        guard let ink else { return nil }
        switch ink {
        case .frame, .faceDark: return 0x1E1B4B
        case .titleBar: return 0xE3E5FB
        case .screen: return 0x24214F
        case .fill: return fill
        case .faceLight: return 0xFFFFFF
        case .sweat: return 0x7DD3FC
        case .spark: return 0xF59E0B
        case .zzz: return 0x8B8FF8
        case .steam: return 0xA5A8F5
        case .accent: return accent
        case .red: return 0xFF5F57
        case .yellow: return 0xFEBC2E
        case .green: return 0x28C840
        }
    }

    /// PNG의 칸마다 색. 투명이면 nil.
    private static func pixels(_ url: URL) throws -> [[UInt32?]] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let n = PixelSprite.size
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        let context = try #require(CGContext(data: &bytes, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        return (0..<n).map { y in
            (0..<n).map { x in
                let i = (y * n + x) * 4
                guard bytes[i + 3] > 0 else { return nil }
                return UInt32(bytes[i]) << 16 | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2])
            }
        }
    }

    @Test(arguments: PixelCharacter.allCases.filter { $0 != .window })
    func spriteMatchesDesignSheet(_ character: PixelCharacter) throws {
        let accent = try #require(character.shape).accent
        for (name, mood, remaining, fill, fillIsLight) in Self.states {
            let expected = try Self.pixels(Self.sprites.appending(path: "\(character.rawValue)-\(name)@1x.png"))
            let grid = PixelSprite.grid(mood: mood, remaining: remaining, fillIsLight: fillIsLight, character: character)
            let actual = grid.map { $0.map { Self.hex($0, fill: fill, accent: accent) } }
            #expect(actual == expected, "\(character.rawValue) \(name)")
        }
    }

    @Test func everyCharacterShowsTheGaugeAndAllFaces() {
        for character in PixelCharacter.allCases {
            let full = PixelSprite.grid(mood: .happy, remaining: 1, fillIsLight: false, character: character)
            let empty = PixelSprite.grid(mood: .sleep, remaining: 0, fillIsLight: false, character: character)
            let count = { (g: [[PixelSprite.Ink?]], ink: PixelSprite.Ink) in g.joined().filter { $0 == ink }.count }
            #expect(count(full, .fill) > 0 && count(full, .screen) == 0, "\(character) 가득 차면 빈 칸이 없다")
            #expect(count(empty, .fill) == 0, "\(character) 다 쓰면 빛이 없다")
            #expect(count(empty, .zzz) > 0, "\(character) 잘 때 Z가 보인다")
            for mood in [CharacterMood.happy, .calm, .squeeze, .sleep, .joy] {
                let g = PixelSprite.grid(mood: mood, remaining: 0.5, fillIsLight: false, character: character)
                #expect(count(g, .faceLight) + count(g, .faceDark) >= 4, "\(character) \(mood) 얼굴")
            }
        }
    }

    @Test func widgetDataCarriesTheCharacter() throws {
        var data = WidgetData(updatedAt: .now, palette: .indigo, sections: [], services: [])
        data.character = .potion
        let decoded = try JSONDecoder().decode(WidgetData.self, from: JSONEncoder().encode(data))
        #expect(decoded.character == .potion)
        // 예전 파일(캐릭터 없음)도 읽힌다.
        let old = try JSONDecoder().decode(WidgetData.self, from: JSONEncoder().encode(WidgetData(updatedAt: .now, palette: .indigo, sections: [], services: [])))
        #expect(old.character == nil)
    }
}
