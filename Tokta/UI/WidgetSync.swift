import Foundation
import OSLog
import WidgetKit

/// 앱이 사용량을 읽거나 계정이 바뀔 때마다 위젯 파일을 새로 쓴다.
/// 파일은 매번 쓰고(“몇 분 전” 판단이 맞게), 보이는 내용이 바뀌었을 때만 위젯을 다시 그리게 한다.
/// 위젯은 다시 그리는 횟수에 하루 한도가 있어서다.
@MainActor
enum WidgetSync {
    private static var lastVisible: WidgetData?
    private static var lastUpload: Date?

    static var palette: UsagePalette {
        UserDefaults.standard.string(forKey: UsagePalette.storageKey).flatMap(UsagePalette.init) ?? .indigo
    }

    static func publish(_ store: UsageStore) {
        var data = WidgetData.build(from: store, palette: palette)
        data.character = PixelCharacter.current
        do { try data.save() } catch { return }
        let visible = data.withoutTimestamps
        let changed = visible != lastVisible
        uploadToCloudIfNeeded(data, changed: changed)
        guard changed else { return }
        lastVisible = visible
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// iPhone용으로 iCloud에 올린다. 보이는 내용이 바뀌었거나 10분이 지났을 때만(“몇 분 전 값”이 맞게).
    /// iCloud 권한이 있는 설치본에서만 돈다. 실패해도 맥 앱에는 영향이 없다.
    private static func uploadToCloudIfNeeded(_ data: WidgetData, changed: Bool) {
        guard CloudSync.isAvailable else { return }
        if !changed, let lastUpload, Date.now.timeIntervalSince(lastUpload) < 600 { return }
        lastUpload = .now
        Task.detached {
            do {
                try await CloudSync.upload(data)
                Logger.cloud.info("iCloud에 올림")
            } catch {
                Logger.cloud.error("iCloud에 올리지 못함: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

private extension WidgetData {
    /// 시각만 다른 경우는 같은 화면으로 본다.
    var withoutTimestamps: WidgetData {
        var copy = self
        copy.updatedAt = .distantPast
        func strip(_ row: Row) -> Row { var row = row; row.observedAt = nil; return row }
        copy.sections = sections.map { section in var section = section; section.rows = section.rows.map(strip); return section }
        copy.services = services.map { service in var service = service; service.best = service.best.map(strip); return service }
        return copy
    }
}

extension Logger {
    /// `log show --predicate 'subsystem == "app.tokta.Tokta"'`로 본다.
    static let cloud = Logger(subsystem: "app.tokta.Tokta", category: "cloud")
}
