import CloudKit
import Foundation

/// 맥이 읽은 위젯 데이터를 본인 iCloud(CloudKit 개인 데이터베이스)에 올리고, iPhone이 받아 간다.
/// WidgetData 전체(그룹·설정·결제 금액이 들어갈 수 있는 알림 포함)를 보낸다. 인증정보는 없다. README 참고.
enum CloudSync {
    static let containerID = BuildConfig.iCloudContainer
    static let recordType = "UsageSnapshot"
    static let recordID = CKRecord.ID(recordName: "latest")

    /// iCloud 권한이 있는 빌드인지. 맥의 테스트용 빌드에는 권한이 없고, 권한 없이 컨테이너를 만들면 앱이 멈춘다.
    static var isAvailable: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String]
        else { return false }
        return value.contains(containerID)
        #else
        return true
        #endif
    }

    private static var database: CKDatabase { CKContainer(identifier: containerID).privateCloudDatabase }

    static func upload(_ data: WidgetData) async throws {
        let record = CKRecord(recordType: recordType, recordID: recordID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        record["payload"] = try encoder.encode(data) as NSData
        record["updatedAt"] = data.updatedAt as NSDate
        // 늘 같은 레코드를 덮어쓴다.
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    static func fetch() async throws -> WidgetData? {
        do {
            let record = try await database.record(for: recordID)
            guard let payload = record["payload"] as? Data else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WidgetData.self, from: payload)
        } catch let error as CKError where error.code == .unknownItem {
            return nil   // 맥이 아직 한 번도 올리지 않았다
        }
    }

    /// 맥이 새로 올리면 iPhone을 조용히 깨우는 구독. 한 번 만들어 두면 된다.
    static func subscribe() async throws {
        let subscription = CKQuerySubscription(recordType: recordType, predicate: NSPredicate(value: true),
                                               subscriptionID: "tokta-latest", options: [.firesOnRecordCreation, .firesOnRecordUpdate])
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
    }
}
