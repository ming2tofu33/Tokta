import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(UsageStore.self) private var store
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var needsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var failure: String?
    @AppStorage(MenuBarIcon.showsPercentKey) private var showsPercent = true
    @AppStorage(MenuBarIcon.showsCharacterKey) private var showsCharacter = false
    @AppStorage(UsagePalette.storageKey) private var palette: UsagePalette = .indigo
    @AppStorage(PixelCharacter.storageKey, store: PixelCharacter.defaults) private var character: PixelCharacter = .window

    /// 로그인 항목은 앱 위치를 기억하므로, Xcode 빌드 폴더가 아니라 설치된 앱에서 켜야 한다.
    private let isInstalled = Bundle.main.bundlePath.hasPrefix("/Applications/")

    var body: some View {
        Form {
            Section {
                Toggle("로그인 시 Tokta 열기", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                    .disabled(!isInstalled)
                if !isInstalled {
                    Text("응용 프로그램 폴더에 설치한 Tokta에서 켜세요. 지금 실행 중인 앱은 Xcode 빌드입니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if needsApproval {
                    HStack {
                        Text("시스템 설정에서 Tokta를 허용해야 합니다.").font(.caption)
                        Spacer()
                        Button("로그인 항목 열기") { SMAppService.openSystemSettingsLoginItems() }
                            .controlSize(.small)
                    }
                }
                if let failure {
                    Text(failure).font(.caption).foregroundStyle(.orange)
                }
            }
            Section {
                Toggle("메뉴바에 남은 양 표시", isOn: $showsPercent)
                Toggle("메뉴바 아이콘을 캐릭터로", isOn: $showsCharacter)
            } footer: {
                Text("서비스마다 가장 여유 있는 계정을 고르고, 그중 가장 빠듯한 서비스의 남은 %를 아이콘 옆에 보여줍니다. 아이콘 색과 같은 기준입니다. 캐릭터로 바꾸면 화면이 찬 높이와 표정(^_^ •_• >_< -_-)으로 보여줍니다.")
            }
            Section {
                CharacterPicker(selection: $character, fill: palette.platformColor(for: BarTone.plenty))
            } header: {
                Text("캐릭터")
            } footer: {
                Text("메뉴, 위젯, iPhone, 메뉴바 아이콘에 같은 캐릭터가 나옵니다. 어떤 캐릭터든 차오른 높이가 남은 한도, 얼굴이 상태예요.")
            }
            .onChange(of: character) { WidgetSync.publish(store) }
            Section {
                Picker("맨 위 카드", selection: Binding(get: { store.cardPin }, set: { store.cardPin = $0 })) {
                    Text("자동 (마지막으로 연 서비스)").tag(CardPin?.none)
                    Section("서비스 고정 · 그 안에서 추천 계정") {
                        ForEach(store.activeServices) { service in
                            Text(service.displayName).tag(CardPin?.some(.service(service)))
                        }
                    }
                    Section("계정 고정 · 빠듯할 때만 다른 계정 제안") {
                        ForEach(store.accounts) { account in
                            Text("\(account.service.displayName) · \(account.displayLabel)").tag(CardPin?.some(.account(account.id)))
                        }
                    }
                }
            } footer: {
                Text("메뉴 맨 위 카드에 크게 보여줄 것입니다. 계정을 고정하면 그 계정이 알림 기준선 아래로 내려가거나 1시간 안에 바닥날 것 같을 때만 같은 서비스의 다른 계정을 제안합니다. 카드의 핀이나 아래 줄 오른쪽 클릭으로도 바꿀 수 있어요.")
            }
            Section {
                Picker("사용량 색", selection: $palette) {
                    ForEach(UsagePalette.allCases) { option in
                        HStack(spacing: 10) {
                            PaletteSwatch(palette: option)
                            Text(option.title)
                        }
                        .tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: palette) { WidgetSync.publish(store) }
            } footer: {
                Text("왼쪽부터 50% 넘음 · 알림 기준선까지 · 알림 기준선 아래 · 위험 기준선 아래. 메뉴 막대와 메뉴바 아이콘 경고 색이 같이 바뀝니다.")
            }
            Section {
                LabeledContent("버전", value: Self.version)
                LabeledContent("위치", value: Bundle.main.bundlePath)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            failure = nil
        } catch {
            failure = String(localized: "로그인 항목을 바꾸지 못했습니다: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        needsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return String(localized: "\(short) (빌드 \(build))")
    }
}

/// 캐릭터 고르기. 누르면 바로 바뀐다.
private struct CharacterPicker: View {
    @Binding var selection: PixelCharacter
    let fill: PlatformColor

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PixelCharacter.allCases) { character in
                Button { selection = character } label: {
                    VStack(spacing: 4) {
                        PixelCharacterView(mood: .happy, remaining: 0.7, fill: fill, animated: selection == character, character: character)
                            .frame(width: 32, height: 32)
                        Text(character.displayName).font(.caption2).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(selection == character ? Color.accentColor.opacity(0.15) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selection == character ? Color.accentColor : .clear, lineWidth: 1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(character.displayName)
                .accessibilityAddTraits(selection == character ? .isSelected : [])
            }
        }
    }
}
