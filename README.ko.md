# Tokta

**돈 내고 쓰는 AI 계정을 전부 Mac 메뉴바에서. 다음엔 어느 계정을 쓸지 작은 픽셀 친구가 알려줘요.**

[English](README.md)

<!-- TODO: 메뉴바 캐릭터 GIF (docs/images/hero.gif) -->

Tokta는 Claude, Codex(ChatGPT), Grok, Cursor, Antigravity 구독이 얼마나 남았는지 계정 수와 상관없이 한눈에 보여줘요. 지금 쓸 계정을 골라주고, 한도가 떨어지기 전에 알려주고, 그 계정을 한 번에 열어줘요.

## 기능

- **서비스마다 여러 계정.** 회사 Claude, 개인 Claude, 팀원 좌석까지 계정마다 따로 로그인하고 따로 추적해요.
- **"지금 쓰기" 카드.** 쓰고 있는 계정을 그대로 보여주다가, 그 계정이 빠듯하거나 막혔을 때만 같은 서비스·같은 그룹에서 더 여유 있는 계정을 제안해요.
- **픽셀 캐릭터.** Mac 창, 배터리, 칩, 머그컵, 물약, 슬라임, 로봇 중에서 16×16 캐릭터를 골라요. 한도가 차오르면 몸이 빛으로 차고, 표정으로 상태를 알려줘요. 메뉴와 위젯에 나오고, 원하면 메뉴바에도 띄울 수 있어요.
- **알림.** 한도가 빠듯하거나 1시간 안에 다 쓸 것 같을 때, 리셋 예정 시각이 됐을 때, 구독 결제 전날에 알려줘요.
- **한 번에 열기.** 추천 계정이 로그인된 창(Claude, Cursor)이나 CLI 터미널(Codex, Grok)을 바로 열어요.
- **그룹.** 회사·개인처럼 직접 이름 붙인 그룹으로 계정을 묶어요.
- **사용 기록과 소진 예측.** 계정마다 얼마나 빨리 줄고 있는지 보여줘요.
- **Tokta 창.** 모든 계정을 정렬해서 보는 목록, 오늘 하루 타임라인, 이번 달에 쓰고 낸 것을 한 창에서 봐요.
- **구독 관리.** 얼마를 내는지, 언제 결제되는지 기록해요.
- **위젯과 iPhone 앱.** Mac 데스크톱 위젯, 그리고 내 iCloud로 동기화되는 iPhone 앱과 위젯이 있어요. iPhone 앱은 아직 App Store에 없어서 지금은 [직접 빌드](#iphone)해야 해요.
- **한국어와 영어.**

## 지원 서비스

| 서비스 | 여러 계정 | 사용량을 읽는 방법 | 필요한 것 |
|---|---|---|---|
| Claude | 지원 | 계정별 웹 로그인 | — |
| Codex (ChatGPT) | 지원 | ChatGPT 요금제의 Codex 한도를 ChatGPT 데스크톱 앱에 들어 있는 Codex로 읽기 | [ChatGPT 데스크톱 앱](https://openai.com/chatgpt/download/) 또는 Codex CLI |
| Grok | 지원 | Grok CLI 로그인과 xAI 사용량 API | [Grok CLI](https://x.ai/build) |
| Cursor | 지원 | 계정별 cursor.com 로그인 | — |
| Grok Bot | Cursor 계정을 따라감 | 연결된 Cursor 로그인 | — |
| Antigravity | 계정 하나 | Antigravity CLI (`agy -p /usage`) | [Antigravity CLI](https://antigravity.google) |

이 서비스들은 개인 요금제용 공식 사용량 API가 없어요. 그래서 **서비스가 웹사이트나 CLI를 바꾸면 언제든 깨질 수 있어요.** 깨지면 [이슈](../../issues)로 알려주세요. 서비스마다 정확히 어떻게 읽는지는 [docs/services](docs/services/)에 있어요(영어).

## 설치

### Mac

**macOS 15** 이상이 필요해요.

1. [Releases](../../releases)에서 최신 `Tokta-x.y.z.dmg`를 받아요. Apple 서명과 공증을 받은 파일이에요.
2. Tokta를 응용 프로그램 폴더로 끌어다 놓고 열어요. Tokta는 메뉴바에 있고 Dock 아이콘은 없어요.
3. **설정 → 계정**에서 계정을 추가해요.

### iPhone

iPhone 앱과 위젯은 Mac이 읽은 값을 내 iCloud로 받아서 보여줘요. 아직 App Store나 TestFlight에 없어서, 지금은 직접 빌드해야 해요.

- Apple Developer 계정, Xcode, **iOS 18** 이상 iPhone이 필요해요.
- **Mac 앱과 iPhone 앱을 둘 다 같은 팀으로 직접 빌드해야 해요.** 동기화는 팀에 속한 iCloud 컨테이너로 이뤄져서, Releases에서 받은 Mac 앱은 직접 빌드한 iPhone 앱과 연결되지 않아요.
- 두 기기 모두 같은 Apple ID로 iCloud에 로그인돼 있어야 해요.

순서:

1. [직접 빌드하기](#직접-빌드하기)대로 `Config/Local.xcconfig`에 팀 ID와 식별자 앞부분을 적어요.
2. `scripts/install.sh`로 Mac 앱을 빌드해서 설치해요. iCloud 동기화는 Release 빌드에서만 켜져서, Xcode에서 Debug로 실행한 Mac 앱은 동기화되지 않아요.
3. Xcode에서 **ToktaPhone** 스킴을 iPhone에 실행해요.

자동 서명을 쓰면 처음 빌드할 때 Xcode가 App ID, App Group, iCloud 컨테이너(`iCloud.<내 식별자 앞부분>`)를 등록해 줘요. 안 되면 Apple Developer 포털에서 직접 추가해요.

## 데이터는 어디에 있나요

Tokta에는 서버가 없어요.

- **로그인 정보**는 내 Mac에만 있어요. 계정마다 웹 세션을 따로 분리된 WebKit 저장소에 둬요. Codex, Grok, Antigravity는 공식 앱이나 CLI의 로그인을 그대로 써요.
- **사용량 숫자와 설정**은 내 Mac에 저장돼요.
- **iCloud 동기화**(iPhone 앱용)는 계정 이름, 요금제, 남은 %, 리셋 시각만 내 개인 iCloud 데이터베이스에 올려요. 로그인 정보는 절대 올리지 않아요.

계정을 지우면 그 계정의 로그인 쿠키와 캐시도 함께 지워요.

## 직접 빌드하기

Xcode 27로 개발하고 있어요.

```bash
git clone https://github.com/ming2tofu33/Tokta.git
cd Tokta
cp Config/Local.example.xcconfig Config/Local.xcconfig
```

`Config/Local.xcconfig`를 고쳐요.

```
DEVELOPMENT_TEAM = ABCDE12345          // 내 Apple Developer 팀 ID
TOKTA_BUNDLE_PREFIX = com.example.tokta // 내가 쓸 식별자 앞부분
```

그다음 `Tokta.xcodeproj`를 열고 **Tokta** 스킴을 실행해요.

Apple Developer 계정이 없다면 `Local.xcconfig` 없이 바로 실행해도 돼요. Mac 앱은 로컬 서명으로 빌드되고 실행돼요. 위젯과 iPhone 동기화에는 팀 ID가 필요해요. 모든 타깃의 App Group, iCloud 컨테이너, bundle ID는 `Config/Tokta.xcconfig`가 이 두 값으로 만들어요.

`scripts/install.sh`는 Release로 빌드해서 `/Applications`에 설치해요. `scripts/release.sh`는 Developer ID로 서명하고 공증한 뒤 DMG를 만들어요.

## 기여하기

Tokta는 여유 시간에 관리하는 개인 프로젝트라 답이 늦을 수 있어요. 서비스가 깨졌을 때 알려주는 방법, 테스트 실행, 서비스·캐릭터 추가 방법은 [CONTRIBUTING.md](CONTRIBUTING.md)(영어)에 있어요. 보안 문제는 [SECURITY.md](SECURITY.md)대로 비공개로 알려주세요.

이슈와 PR을 환영해요. 특히 이런 것들이요.

- **서비스가 깨졌어요.** 서비스, 요금제, 카드에 나온 오류 문구를 그대로 적어주세요.
- **새 서비스 추가.** 서비스별 코드는 `Tokta/Providers/`에 있고, 각각 `UsageProvider`를 구현해요. [docs/services](docs/services/README.md#adding-a-service)를 참고하세요.

왜 이렇게 만들었는지는 [docs/decisions](docs/decisions/)에 정리돼 있어요(영어). 로그인이나 데이터 저장 방식을 바꾸기 전에 읽어주세요.

## 면책

Tokta는 개인 프로젝트예요. Anthropic, OpenAI, xAI, Anysphere(Cursor), Google과 관계가 없고, 이들이 보증하거나 후원하지 않아요. Tokta는 비공식 경로로 사용량을 읽기 때문에 언제든 작동을 멈출 수 있어요. 각 서비스의 약관에 맞게 쓰고 있는지 직접 확인해주세요.

`Tokta/Assets.xcassets`에 있는 서비스 로고는 각 회사의 상표이며 MIT 라이선스 대상이 아니에요.

## 라이선스

[MIT](LICENSE) © 2026 Domin Kim
