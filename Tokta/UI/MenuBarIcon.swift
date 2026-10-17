import SwiftUI

/// 서비스마다 가장 여유 있는 계정 기준으로, 빠듯하거나 거의 다 쓰면 고른 색 조합의 경고 색으로 바뀐다.
struct MenuBarIcon: View {
    let level: StatusLevel
    /// 서비스마다 가장 여유 있는 계정 중 가장 빠듯한 남은 비율.
    let remaining: Double?
    /// 메뉴바 캐릭터를 켰을 때 그릴 표정과 색 단계.
    var character: (mood: CharacterMood, tone: BarTone, remaining: Double)?
    @AppStorage(MenuBarIcon.showsPercentKey) private var showsPercent = true
    @AppStorage(MenuBarIcon.showsCharacterKey) private var showsCharacter = false
    @AppStorage(UsagePalette.storageKey) private var palette: UsagePalette = .indigo
    @AppStorage(PixelCharacter.storageKey, store: PixelCharacter.defaults) private var pixelCharacter: PixelCharacter = .window

    static let showsPercentKey = "menuBarShowsPercent"
    static let showsCharacterKey = "menuBarShowsCharacter"

    var body: some View {
        HStack(spacing: 3) {
            if showsCharacter, let character {
                Image(nsImage: PixelSprite.image(mood: character.mood, remaining: character.remaining,
                                                 fill: palette.platformColor(for: character.tone), fillIsLight: character.tone == .moderate,
                                                 character: pixelCharacter))
            } else {
                Image(nsImage: Self.image(for: level, palette: palette))
            }
            // 기준 계정 값이 없거나 오래됐으면 숫자 대신 “—”.
            if showsPercent {
                Text(remaining.map { "\(Int(($0 * 100).rounded()))%" } ?? "—").monospacedDigit()
            }
        }
        .accessibilityLabel(Self.description(for: level))
    }

    static func image(for level: StatusLevel, palette: UsagePalette) -> NSImage {
        let color = palette.platformColor(for: level)
        guard let source = NSImage(named: "ToktaMenu") else { return NSImage() }
        let size = NSSize(width: 18, height: 18)
        let image: NSImage
        if let color {
            image = NSImage(size: size, flipped: false) { rect in
                source.draw(in: rect)
                color.setFill()
                rect.fill(using: .sourceIn)
                return true
            }
        } else {
            image = source.copy() as! NSImage
        }
        image.size = size
        // 평소에는 메뉴바 색을 따르고, 경고일 때만 색을 그대로 보여준다.
        image.isTemplate = color == nil
        return image
    }

    private static func description(for level: StatusLevel) -> String {
        switch level {
        case .normal: "Tokta"
        case .warning: String(localized: "Tokta, 한도 얼마 안 남음")
        case .critical: String(localized: "Tokta, 한도 거의 다 씀")
        }
    }
}
