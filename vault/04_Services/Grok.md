---
title: "Grok"
project: Tokta
type: service
status: active
collection: grok-cli
last_verified: 2026-10-13
created: 2026-10-13
updated: 2026-10-13
tags:
  - tokta/service
  - tokta/grok
---

# Grok

| 항목 | 내용 |
|---|---|
| 지원 상태 | 지원 — 계정 여러 개 (이 Mac의 `~/.grok` 로그인 1개 + 계정마다 전용 Grok CLI 로그인) |
| 수집 방식 | 공식 Grok CLI 로그인 토큰 → xAI 사용량 API |
| 필요한 프로그램 | **Grok CLI** (`~/.grok/bin/grok`). 설정에서 설치 여부를 보여준다 |
| 마지막 확인 | 2026-10-13, 사용자 유료 계정, 이 Mac 실제 조회 |
| 코드 | `Tokta/Providers/GrokProvider.swift`, `GrokLogin.swift` |

결정 배경: [[2026-10-13 Grok 추가와 토큰 갱신을 CLI에 맡김]]

## 무엇을 보여주나

xAI 통합 구독 한도. Grok 웹·앱과 Grok CLI가 같이 쓴다(`isUnifiedBillingUser`).

**Grok Bot**(`/Applications/Grok Bot.app`)은 이름과 달리 Cursor 회사 앱이고 한도도 Cursor 계정에 있다 → [[Cursor]].

## 플랜별 한도 규칙

| 관찰한 구간 | 확인 |
|---|---|
| 주간 (`USAGE_PERIOD_TYPE_WEEKLY`), 리셋은 `currentPeriod.end` | 2026-10-13 실제 응답 |

- 사용 비율 `creditUsagePercent`는 **그 주에 하나도 안 썼으면 응답에서 빠진다.** 통합 구독 사용자이고 기간이 제대로 있으면 0%로 본다. 공식 CLI도 같게 해석한다(AI-Tracker 메모).
- 주간이 아닌 응답은 “구독 기간”으로 표시. `monthlyLimit`/`used`가 오면 그 비율을 쓴다.
- 응답에 추가 사용 크레딧(`onDemandCap`, `onDemandUsed`, `prepaidBalance`)도 온다. 표시하지 않음.
- 플랜 이름은 응답에 없어 표시하지 않는다.

## 로그인과 토큰

- 로그인 정보: `GROK_HOME/auth.json`의 `"https://auth.x.ai::<id>"` 항목 (`key`, `refresh_token`, `expires_at`, `email`, `principal_type` 등). Tokta는 `key`·`email`·`expires_at`만 읽는다.
- 팀 계정(`principal_type: Team`)은 거부한다.
- **토큰은 몇 시간이면 만료된다**(2026-10-13 확인 시 약 2.6시간 남음). 만료 5분 전이면 Tokta가 `grok models`를 실행해 **CLI가 스스로 갱신하게** 한 뒤 다시 읽는다. Tokta는 토큰을 직접 갱신하거나 쓰지 않는다.
  - `grok models`: 로그인이 필요한 가벼운 명령, 약 1.7초.
  - ⚠️ **만료된 토큰을 이 명령이 실제로 갱신하는지는 아직 확인 전.** 확인되면 이 줄을 고친다. 안 되면 “Grok 로그인이 만료됐습니다”가 뜬다 → [[00 깨짐 기록 목차]]에 기록.
- CLI 위치: PATH → `~/.grok/bin/grok`.

## 다중 계정

ChatGPT와 같은 구조. [[ChatGPT#다중 계정]]

| 계정 종류 | 로그인 위치 | 만드는 방법 |
|---|---|---|
| 기본 로그인 | `~/.grok` (터미널 `grok`과 같은 로그인) | 설정 → 계정 → “이 Mac 로그인 연결” → Grok |
| 전용 로그인 | `~/Library/Application Support/Tokta/grok/<계정 ID>/` | 설정에서 Grok 계정 추가 → `grok login --oauth`가 브라우저를 연다 |

- `GROK_HOME` 환경 변수로 폴더를 나눈다(2026-10-13 확인).
- 로그인은 최대 5분, 한 번에 하나. 종료 코드 0이면 성공으로 보고 바로 사용량을 읽는다.

## 응답 형식 확인 이력

| 날짜 | 계정 | 확인 방법 | 내용 |
|---|---|---|---|
| 2026-10-13 | 본인 유료, `~/.grok` | 직접 호출(값 가림) + Swift 수집기 실제 조회 | 아래 형식. 주간 100% 남음, 5일 6시간 후 리셋 |

```json
{"config": {
  "currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY", "start": "...", "end": "..."},
  "onDemandCap": {"val": 0}, "onDemandUsed": {"val": 0},
  "isUnifiedBillingUser": true, "prepaidBalance": {"val": 0},
  "billingPeriodStart": "...", "billingPeriodEnd": "..."}}
```

요청: `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits`, 헤더 `Authorization: Bearer <key>`, `x-xai-token-auth: xai-grok-cli`. 테스트 `GrokTests`.

## 깨짐 기록

아직 없음.
