import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("일반", systemImage: "gearshape") }
            AccountsSettingsView()
                .tabItem { Label("계정", systemImage: "person.2") }
            GroupsSettingsView()
                .tabItem { Label("그룹", systemImage: "folder") }
            SubscriptionsSettingsView()
                .tabItem { Label("구독", systemImage: "creditcard") }
            AlertsSettingsView()
                .tabItem { Label("알림", systemImage: "bell") }
        }
        .frame(width: 540, height: 460)
    }
}

private struct AccountsSettingsView: View {
    @Environment(UsageStore.self) private var store
    @State private var service: Service = .claude
    @State private var label = ""
    @State private var email = ""

    private var trimmedLabel: String { label.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                // 메뉴와 같은 묶음으로 보여주고, 묶음 안에서 끌어서 순서를 바꾼다.
                ForEach(store.sections) { section in
                    Section(section.title) {
                        ForEach(section.accounts) { account in
                            HStack {
                                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                                VStack(alignment: .leading) {
                                    HStack(spacing: 6) {
                                        TextField("이름", text: labelBinding(for: account))
                                            .textFieldStyle(.plain)
                                            .frame(minWidth: 60, maxWidth: 180, alignment: .leading)
                                        if section.showsService {
                                            Text(account.service.displayName).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    if let error = store.errors[account.id] {
                                        Text(error).font(.caption).foregroundStyle(.orange)
                                    }
                                    if let email = account.email {
                                        Text(email).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if !store.groups.isEmpty {
                                    Picker("그룹", selection: groupBinding(for: account)) {
                                        Text("그룹 없음").tag(AccountGroup.ID?.none)
                                        ForEach(store.groups) { group in
                                            Text(group.name.isEmpty ? String(localized: "이름 없는 그룹") : group.name).tag(AccountGroup.ID?.some(group.id))
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 130)
                                }
                                Button(role: .destructive) {
                                    Task { await store.remove(account.id) }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("계정 삭제")
                                .disabled(store.deleting.contains(account.id))
                                if store.deleting.contains(account.id) { ProgressView().controlSize(.small) }
                            }
                        }
                        .onMove { store.moveAccounts(inSection: section.id, fromOffsets: $0, toOffset: $1) }
                    }
                }
            }
            .overlay {
                if store.accounts.isEmpty {
                    Text("추가한 계정이 없습니다").foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("이름을 눌러 바꾸고, 끌어서 메뉴 순서를 바꿉니다. 다른 그룹으로 옮기려면 오른쪽에서 그룹을 고르세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                // 이미 터미널·앱에서 로그인해 둔 Codex·Grok·Antigravity CLI 로그인을 그대로 쓴다.
                Menu("이 Mac 로그인 연결") {
                    ForEach(Service.allCases.filter(\.hasSystemLogin)) { service in
                        let installed = RequiredApp.isInstalled(for: service)
                        Button(Self.systemLoginTitle(for: service) + (installed ? "" : String(localized: " — 설치 필요"))) {
                            store.addSystemLogin(for: service)
                        }
                        .disabled(store.hasSystemLogin(for: service) || !installed)
                    }
                }
                .fixedSize()
            }

            HStack {
                // Antigravity처럼 계정 하나만 쓰는 서비스는 위 “이 Mac 로그인 연결”로만 추가한다.
                Picker("서비스", selection: $service) {
                    ForEach(store.supportedServices.filter(\.supportsMultipleAccounts)) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
                TextField("별칭", text: $label)
                TextField("이메일 (선택)", text: $email)
                Button("추가") {
                    let email = email.trimmingCharacters(in: .whitespaces)
                    let account = Account(service: service, label: trimmedLabel, email: email.isEmpty ? nil : email)
                    store.add(account)
                    AccountLogin.start(for: account, store: store)
                    label = ""
                    self.email = ""
                }
                .disabled(trimmedLabel.isEmpty || !RequiredApp.isInstalled(for: service))
            }
            if let requirement = RequiredApp.requirement(for: service) {
                RequirementLine(requirement: requirement, installed: RequiredApp.isInstalled(for: service))
            }
            Text(AccountsSettingsHint.text(for: service))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private static func systemLoginTitle(for service: Service) -> String {
        switch service {
        case .chatgpt: String(localized: "Codex (ChatGPT 계정 로그인)")
        case .grok: String(localized: "Grok (Grok CLI 로그인)")
        case .antigravity: String(localized: "Antigravity (agy 로그인 · Gemini·Claude·GPT 한도)")
        case .claude, .cursor, .grokBot: service.displayName
        }
    }

    private func labelBinding(for account: Account) -> Binding<String> {
        Binding(get: { account.label }, set: { store.renameAccount(account.id, to: $0) })
    }

    private func groupBinding(for account: Account) -> Binding<AccountGroup.ID?> {
        Binding(get: { account.groupID }, set: { store.assign(account.id, to: $0) })
    }
}

private struct GroupsSettingsView: View {
    @Environment(UsageStore.self) private var store
    @State private var newName = ""

    private var trimmedName: String { newName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                ForEach(store.groups) { group in
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        TextField("그룹 이름", text: nameBinding(for: group))
                            .textFieldStyle(.plain)
                        Spacer()
                        Text("계정 \(store.accounts.filter { $0.groupID == group.id }.count)개")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            store.removeGroup(group.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("그룹 삭제 (계정은 남습니다)")
                    }
                }
                .onMove { store.moveGroups(fromOffsets: $0, toOffset: $1) }
            }
            .overlay {
                if store.groups.isEmpty {
                    Text("그룹이 없으면 메뉴에 서비스별로 보입니다").foregroundStyle(.secondary)
                }
            }

            Text("이름을 눌러 바꾸고, 끌어서 메뉴에 보이는 순서를 바꿀 수 있습니다. 계정은 계정 탭에서 그룹에 넣으세요.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("새 그룹 이름 (예: 회사, 개인)", text: $newName)
                    .onSubmit(addGroup)
                Button("추가", action: addGroup)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding()
    }

    private func addGroup() {
        guard !trimmedName.isEmpty else { return }
        store.addGroup(named: trimmedName)
        newName = ""
    }

    private func nameBinding(for group: AccountGroup) -> Binding<String> {
        Binding(get: { group.name }, set: { store.renameGroup(group.id, to: $0) })
    }
}

private struct AlertsSettingsView: View {
    @Environment(UsageStore.self) private var store

    private static let warningOptions: [Double] = [0.5, 0.3, 0.25, 0.2, 0.15, 0.1]

    var body: some View {
        Form {
            Section {
                Picker("받을 곳", selection: destinationBinding) {
                    Text("iPhone").tag(AlertDestination.iPhone)
                    Text("이 맥").tag(AlertDestination.mac)
                    Text("둘 다").tag(AlertDestination.both)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("iPhone으로 받으면 맥이 정한 알림을 iCloud로 넘겨 iPhone Tokta가 보냅니다. 다시 찼어요·내일 결제는 미리 예약돼서 맥이 꺼져 있어도 옵니다.")
            }
            Section {
                Toggle("곧 바닥나요", isOn: binding(\.lowEnabled))
                Picker("기준", selection: thresholdBinding) {
                    ForEach(Self.warningOptions, id: \.self) { Text(percent($0) + String(localized: " 남았을 때")).tag($0) }
                }
                .disabled(!store.alertSettings.lowEnabled)
                Toggle("다시 찼어요", isOn: binding(\.resetEnabled))
                Toggle("내일 결제", isOn: binding(\.renewalEnabled))
            } footer: {
                Text("곧 바닥나요: 기준 아래로 내려가거나 이 속도면 1시간 안에 바닥날 때, 한 주기에 한 번만. 다시 찼어요: 곧 바닥나요가 왔던 한도가 리셋될 때. 내일 결제: 구독 결제 전날 오전 9시.")
            }
            Section {
                Button("테스트 알림 보내기") { store.sendTestAlert() }
                Text(store.alertSettings.destination.onPhone
                     ? String(localized: "iPhone 알림은 맥이 iCloud에 올린 뒤 iPhone Tokta가 받아서 보냅니다(몇 분 걸릴 수 있어요). 오지 않으면 iPhone 설정 → 알림에서 Tokta를 허용하세요.")
                     : String(localized: "알림이 오지 않으면 시스템 설정 → 알림에서 Tokta를 허용하세요."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var destinationBinding: Binding<AlertDestination> {
        Binding(get: { store.alertSettings.destination }, set: { value in
            var settings = store.alertSettings
            settings.destination = value
            store.updateAlertSettings(settings)
        })
    }

    private func binding(_ keyPath: WritableKeyPath<AlertSettings, Bool>) -> Binding<Bool> {
        Binding(get: { store.alertSettings[keyPath: keyPath] }, set: { value in
            var settings = store.alertSettings
            settings[keyPath: keyPath] = value
            store.updateAlertSettings(settings)
        })
    }

    /// 알림 기준은 하나. 둘째(5%)는 메뉴 색(빨강)에만 쓴다.
    private var thresholdBinding: Binding<Double> {
        Binding(get: { store.alertSettings.warning }, set: { value in
            var settings = store.alertSettings
            settings.thresholds = [value, 0.05]
            store.updateAlertSettings(settings)
        })
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}

/// 계정을 추가하기 전에 그 서비스 로그인에서 막히기 쉬운 점을 알려준다.
enum AccountsSettingsHint {
    static func text(for service: Service) -> String {
        switch service {
        case .claude: String(localized: "Tokta 창에서 로그인합니다. Google로 가입한 계정은 Google 버튼 대신 같은 Gmail 주소로 ‘이메일로 계속하기’를 쓰세요.")
        case .cursor: String(localized: "Tokta 창에서 로그인합니다. Google 로그인은 막히니 GitHub이나 이메일 로그인을 쓰세요. Grok Bot 한도가 있으면 Grok Bot 줄이 저절로 생깁니다.")
        case .grokBot: String(localized: "Grok Bot은 Cursor 회사 앱이라 Cursor 계정을 추가하면 저절로 생깁니다.")
        case .antigravity: String(localized: "Antigravity는 이 Mac의 Antigravity CLI(agy) 로그인 하나만 씁니다. 위 ‘이 Mac 로그인 연결’에서 추가하세요.")
        case .chatgpt, .grok: String(localized: "평소 쓰는 브라우저가 열립니다. 추가할 계정으로 로그인하세요. 브라우저에 다른 계정이 이미 로그인돼 있으면 그 계정으로 연결될 수 있어요.")
        }
    }
}

/// 이 서비스에 필요한 프로그램과 설치 여부.
private struct RequirementLine: View {
    let requirement: RequiredApp.Requirement
    let installed: Bool

    var body: some View {
        HStack(spacing: 6) {
            if installed {
                Label("\(requirement.name) 설치됨", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("\(requirement.subject) 필요해요. \(requirement.purpose).", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Link("다운로드", destination: requirement.downloadURL)
            }
        }
        .font(.caption)
    }
}
