import Foundation

/// 위젯이 보여줄 내용. 위젯은 사용량을 직접 읽지 않고, 앱이 읽을 때마다 App Group 공유 폴더에 써 둔 이 파일을 보여준다.
/// 계산(추천, 색 단계, 문구)은 앱에서 끝내 두고 위젯은 그리기만 한다.
struct WidgetData: Codable, Equatable, Sendable {
    struct Bar: Codable, Equatable, Sendable {
        var tone: BarTone
        var remaining: Double
        /// 구간 이름(“5시간”, “주간”)과 리셋 시각. 예전 파일에는 없다.
        var title: String?
        var resetsAt: Date?
    }

    struct Row: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        var serviceID: String
        var serviceName: String
        var label: String
        var plan: String?
        /// 가장 빠듯한 구간의 남은 비율. 아직 못 읽었으면 nil.
        var remaining: Double?
        var level: StatusLevel
        var bars: [Bar]
        var isRecommended: Bool
        /// 오류가 붙었으면 짧은 문구.
        var problem: String?
        var observedAt: Date?
        /// 캐릭터 표정. 예전 파일에는 없다.
        var mood: CharacterMood?
        /// 맥이 읽은 값이 아니라 리셋 시각으로 추정한 값이면 true(`estimated(at:)`).
        var isEstimated: Bool?
    }

    struct Section: Codable, Equatable, Identifiable, Sendable {
        var id: String
        var title: String
        var rows: [Row]
    }

    /// 서비스마다 지금 쓸 계정. 중간·작은 위젯이 쓴다.
    struct Service: Codable, Equatable, Identifiable, Sendable {
        var id: String
        var name: String
        /// 추천 계정. 계정이 하나면 그 계정, 쓸 만한 계정이 없으면 nil.
        var best: Row?
        /// 알림 기준선 위로 여유 있는 계정 수
        var roomyCount: Int
        var accountCount: Int
    }

    var updatedAt: Date
    var palette: UsagePalette
    /// 맥에서 고른 캐릭터. iPhone이 받아 자기 App Group 설정에 쓴다. 예전 파일에는 없다.
    var character: PixelCharacter?
    var sections: [Section]
    var services: [Service]
    /// 알림 기준선(기본 20%·5%). 받는 쪽이 추정한 값의 색 단계를 다시 매길 때 쓴다.
    var warning: Double?
    var critical: Double?
    /// 맥이 정한 알림 중 iPhone이 보낼 것. 예전 파일에는 없다.
    var alerts: AlertRelay?

    static let staleAfter: TimeInterval = 15 * 60

    // MARK: iPhone 색 조합

    /// iPhone에서 따로 고른 색 조합. nil이면 맥 색을 따른다. 맥에서는 늘 nil.
    /// App Group 설정에 둬서 iPhone 앱과 iPhone 위젯이 같이 쓴다.
    static var localPalette: UsagePalette? {
        get {
            #if os(iOS)
            UserDefaults(suiteName: appGroup)?.string(forKey: "localPalette").flatMap(UsagePalette.init(rawValue:))
            #else
            nil
            #endif
        }
        set { UserDefaults(suiteName: appGroup)?.set(newValue?.rawValue, forKey: "localPalette") }
    }

    /// 화면에 쓸 색 조합.
    var displayPalette: UsagePalette { Self.localPalette ?? palette }

    // MARK: 공유 파일

    /// 앱과 위젯 확장이 같이 쓰는 App Group. 맥은 팀 ID로, iPhone은 group.으로 시작한다.
    static let appGroup = BuildConfig.appGroup

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appending(path: "widget.json")
    }

    static func load(from url: URL? = fileURL) -> WidgetData? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetData.self, from: data)
    }

    func save(to url: URL? = Self.fileURL) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    // MARK: 위젯 → 앱

    /// 위젯을 누르면 여는 주소. 앱이 받아서 그 계정으로 연다(Claude·Cursor 창, CLI 터미널).
    static func openURL(for accountID: UUID) -> URL { URL(string: "tokta://open/\(accountID.uuidString)")! }

    static func accountID(fromOpenURL url: URL) -> UUID? {
        guard url.scheme == "tokta", url.host() == "open" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}

// MARK: - 맥이 꺼져 있을 때: 리셋 시각으로 추정

extension WidgetData {
    /// 맥이 마지막으로 읽은 뒤 리셋 시각이 지난 구간을 표시한다(`isEstimated`).
    /// 화면은 이 값을 확정된 %처럼 크게 보여주지 않고 “리셋 예정 시각 지남 · 확인 필요”로 보여준다(2026-10-17 기획서 F2).
    func estimated(at now: Date) -> WidgetData {
        var copy = self
        let warning = warning ?? 0.2, critical = critical ?? 0.05
        copy.sections = sections.map { section in
            var section = section
            section.rows = section.rows.map { $0.estimated(at: now, warning: warning, critical: critical) }
            return section
        }
        let rows = copy.sections.flatMap(\.rows)
        copy.services = services.map { service in
            var service = service
            let mine = rows.filter { $0.serviceID == service.id }
            guard mine.contains(where: { $0.isEstimated == true }) else {
                service.best = service.best.flatMap { best in mine.first { $0.id == best.id } ?? best }
                return service
            }
            // 추정이 섞이면 확인된 값 중에서만 다시 고른다(오류·다 쓴 계정·추정 제외). 추정만으로는 추천하지 않는다.
            let usable = mine.filter { $0.problem == nil && $0.isEstimated != true && ($0.remaining ?? 0) > 0 }
            service.best = mine.count == 1 ? mine.first : usable.max { ($0.remaining ?? 0) < ($1.remaining ?? 0) }
            service.roomyCount = mine.filter { $0.problem == nil && ($0.remaining ?? 0) > warning }.count
            return service
        }
        return copy
    }
}

extension WidgetData.Row {
    func estimated(at now: Date, warning: Double, critical: Double) -> WidgetData.Row {
        guard let observedAt else { return self }
        var refilled = false
        let bars = bars.map { bar -> WidgetData.Bar in
            guard let resetsAt = bar.resetsAt, resetsAt > observedAt, resetsAt <= now, bar.remaining < 1 else { return bar }
            refilled = true
            var bar = bar
            bar.remaining = 1
            bar.tone = .plenty
            return bar
        }
        guard refilled else { return self }
        var row = self
        row.bars = bars
        let remaining = bars.map(\.remaining).min() ?? 1
        row.remaining = remaining
        row.level = remaining <= critical ? .critical : remaining <= warning ? .warning : .normal
        row.mood = remaining <= 0 ? .sleep : row.level != .normal ? .squeeze : .joy
        row.isEstimated = true
        return row
    }
}

// MARK: - 알림 전달 (맥 → iPhone)

extension WidgetData {
    /// 알림 하나. `date`는 예약 알림이면 보낼 시각, 바로 보내는 알림이면 맥이 정한 시각.
    struct RelayedAlert: Codable, Equatable, Sendable {
        var id: String
        var title: String
        var body: String
        var date: Date
    }

    /// 판단은 맥이 하고 iPhone은 보내기만 한다.
    /// `scheduled`(다시 찼어요·내일 결제)는 iPhone이 미리 예약해서 맥이 꺼져 있어도 온다.
    /// `recent`(곧 바닥나요)는 맥이 최근 2시간 안에 정한 것. iPhone이 아직 안 보낸 것만 바로 보낸다.
    struct AlertRelay: Codable, Equatable, Sendable {
        var toPhone: Bool
        var scheduled: [RelayedAlert]
        var recent: [RelayedAlert]
    }
}
