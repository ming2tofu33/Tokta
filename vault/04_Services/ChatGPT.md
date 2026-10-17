---
title: "ChatGPT"
project: Tokta
type: service
status: active
collection: codex-rpc
last_verified: 2026-10-13
created: 2026-10-13
updated: 2026-10-13
tags:
  - tokta/service
  - tokta/chatgpt
---

# ChatGPT

| 항목 | 내용 |
|---|---|
| 지원 상태 | 지원 — 계정 여러 개 (계정마다 전용 Codex 로그인, 또는 이 Mac의 기본 로그인 1개) |
| 수집 방식 | 공식 Codex 실행 파일의 `app-server` RPC |
| 필요한 프로그램 | **ChatGPT 데스크톱 앱**(Codex 포함) 또는 Codex CLI. 설정에서 설치 여부를 보여준다 |
| 마지막 확인 | 2026-10-13, Pro 계정 실제 조회 · 두 번째 계정 전용 로그인 사용자 확인 |
| 코드 | `Tokta/Providers/CodexProvider.swift`, `CodexLogin.swift`, `Executables.swift` |

## 무엇을 보여주나

ChatGPT 구독에 딸린 **Codex 한도**다. ChatGPT 웹은 일반 채팅 한도를 숫자로 주지 않아서, 구독에서 숫자로 볼 수 있는 한도는 이것뿐이다. 오해가 없게 구간 이름 앞에 `Codex`를 붙인다. [[2026-10-13 서비스를 ChatGPT와 Claude 두 개로 정리]]

## 플랜별 한도 규칙

| 플랜 | 관찰한 구간 | 확인 |
|---|---|---|
| Pro | `Codex 주간`(10080분) 하나. 5시간 구간 없음 | 2026-10-13 실제 응답 |
| Plus 등 | 미확인. 5시간(300분) 구간이 오면 같이 표시하도록 만들어둠 | — |

- 리셋 시각은 응답의 `resetsAt`(Unix 초)을 그대로 쓴다.
- 응답에 한도 리셋 남은 횟수(`rateLimitResetCredits.availableCount`)가 들어온다. 2026-10-13 기준 2회. 카드 아래에 “한도 리셋 N회 남음”으로 표시한다(1회 이상일 때만). 이 값이 없거나 형식이 바뀌어도 한도 숫자는 그대로 보인다.

## 수집 순서

공식 Codex를 `codex app-server --listen stdio://`로 띄우고 줄 단위 JSON-RPC로 묻는다. 로그인과 토큰 갱신은 Codex가 맡고 Tokta는 토큰을 다루지 않는다.

1. `initialize` → `initialized` 알림
2. `account/read` (params `{}`) → `{account: {type: "chatgpt", email, planType}}`
3. `account/rateLimits/read`

- 20초 안에 끝나지 않으면 프로세스를 끈다. 상대가 먼저 죽어도 앱이 같이 죽지 않게 SIGPIPE를 무시한다.
- 실행 파일 찾는 순서: PATH → `~/.local/bin`, `/opt/homebrew/bin` 등 → `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex` → `/Applications/Codex.app/...`. GUI 앱은 셸 PATH를 물려받지 않아 직접 찾는다. 이 Mac은 ChatGPT 앱 안의 Codex를 쓴다.

## 응답 형식 확인 이력

| 날짜 | 계정·플랜 | 확인 방법 | 내용 |
|---|---|---|---|
| 2026-10-13 | 본인, Pro | RPC 직접 호출 + Swift 수집기 실제 조회 | 아래 형식. `account/read`에 `{refreshToken: false}`를 주면 응답이 오지 않아 빈 params를 쓴다 |
| 2026-10-13 | 로그인 전 빈 폴더 | RPC 직접 호출 (브라우저 열지 않음) | `account/read` → `account: null`. `account/login/start` → `authUrl` 호스트 `auth.openai.com` |

```json
{"rateLimitsByLimitId": {"codex": {
  "primary": {"usedPercent": 4, "windowDurationMins": 10080, "resetsAt": 1792472315},
  "secondary": null, "planType": "pro",
  "credits": {"hasCredits": true, "balance": "..."}}},
 "rateLimitResetCredits": {"availableCount": 2, "credits": [...]}}
```

같은 형식이 테스트 `CodexParsingTests`에 들어 있다.

## 깨짐 기록

아직 없음. 생기면 `01_Logs/Incidents`에 남기고 여기에 연결한다.

## 다중 계정

| 계정 종류 | 로그인 위치 | 만드는 방법 |
|---|---|---|
| 기본 로그인 (`usesSystemLogin`) | 이 Mac의 `~/.codex` — Codex 앱·CLI와 같은 로그인 | 첫 화면 “ChatGPT 연결”. 하나만 둔다 |
| 전용 로그인 | `~/Library/Application Support/Tokta/codex/<계정 ID>/` | 설정에서 ChatGPT 계정 추가 → 브라우저 로그인 |

- 전용 폴더에는 `config.toml`에 `cli_auth_credentials_store = "file"`을 써서 로그인 정보가 키체인이 아니라 그 폴더의 `auth.json`에 저장되게 한다. 그래야 계정끼리 섞이지 않는다. 폴더 권한은 700.
- **전용 로그인 계정이 아직 로그인 전이면 기본 로그인으로 대신 읽지 않는다.** 별칭에 다른 계정 숫자가 붙는 것을 막는다.
- 다중 계정 전에 만든 ChatGPT 계정은 읽을 때 기본 로그인 계정으로 본다.
- 계정을 지우면 전용 폴더도 지운다. 기본 `~/.codex`는 건드리지 않는다.

### 로그인 흐름

1. 전용 폴더를 `CODEX_HOME`으로 Codex를 띄움 (최대 5분)
2. `account/login/start` `{type: "chatgpt"}` → `{authUrl, loginId, type}`. 주소가 `https`이고 OpenAI 로그인 도메인일 때만 기본 브라우저로 연다
3. Codex가 로컬 포트로 로그인 결과를 받고 `account/login/completed` `{success}` 알림
4. 그 계정 사용량을 바로 읽고, 이메일이 비어 있으면 로그인한 이메일로 묶는다

- Codex 로그인은 같은 로컬 포트를 쓰므로 한 번에 하나만 진행한다. 새 로그인을 시작하면 진행 중이던 것은 취소된다.
- 메뉴 카드에 “브라우저에서 ChatGPT 로그인을 마치세요”와 취소 버튼이 보인다.
- 참고 구현: AI-Tracker `electron/native-sync.js`의 `connectCodex`.
