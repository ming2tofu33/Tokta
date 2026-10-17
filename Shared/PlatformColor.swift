import SwiftUI
#if canImport(AppKit)
import AppKit
/// 맥은 NSColor, iPhone은 UIColor. 색 코드는 이 이름으로 둘 다에서 쓴다.
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

extension PlatformColor {
    static func rgb(_ hex: UInt32) -> PlatformColor {
        PlatformColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// 라이트·다크 모드에 따라 바뀌는 색.
    static func adaptive(light: UInt32, dark: UInt32) -> PlatformColor {
        #if canImport(AppKit)
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(dark) : rgb(light) }
        #else
        UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) }
        #endif
    }
}

extension Color {
    init(platform color: PlatformColor) {
        #if canImport(AppKit)
        self.init(nsColor: color)
        #else
        self.init(uiColor: color)
        #endif
    }
}
