import Foundation

/// 팀마다 달라지는 식별자. Config/Tokta.xcconfig 값이 Info.plist를 거쳐 들어온다.
enum BuildConfig {
    /// 앱과 위젯 확장이 같이 쓰는 App Group.
    static let appGroup = value(for: "TOKTAAppGroup")
    /// 맥이 읽은 값을 iPhone으로 보내는 iCloud 컨테이너.
    static let iCloudContainer = value(for: "TOKTAICloudContainer")

    private static func value(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty, !value.hasPrefix(".") else {
            fatalError("Info.plist에 \(key) 값이 없다. Config/Tokta.xcconfig와 Config/Local.xcconfig의 DEVELOPMENT_TEAM을 확인한다.")
        }
        return value
    }
}
