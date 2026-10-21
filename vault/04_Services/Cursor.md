---
title: "Cursor"
project: Tokta
type: service
status: active
collection: web-session
created: 2026-10-13
updated: 2026-10-13
tags:
  - tokta/service
  - tokta/cursor
---

# Cursor

| 항목 | 내용 |
|---|---|
| 지원 상태 | 지원 — 계정 여러 개 (계정별 cursor.com 웹 로그인) |
| 수집 방식 | 계정별 WebKit 저장소 + cursor.com 내부 API |
| 마지막 확인 | 2026-10-13, 사용자 로그인 후 앱 표시 확인 |
| 코드 | `Tokta/Providers/CursorProvider.swift`, `WebSessions.swift`(`WebLoginSite`), `Tokta/UI/LoginWindow.swift` |

결정 배경: [[2026-10-13 Cursor 추가와 Grok Bot을 Cursor 계정에서 읽기]]

## 무엇을 보여주나

계정 카드 하나에 구간 세 개.

| 구간 | 응답 | 리셋 |
|---|---|---|
| Cursor 모델 | `individualUsage.plan.autoPercentUsed` | `billingCycleEnd` |
| 기타 모델 | `individualUsage.plan.apiPercentUsed` | `billingCycleEnd` |
| 플랜 (위 둘이 없을 때만) | `totalPercentUsed` 또는 `used / limit` | `billingCycleEnd` |
| **Grok Bot 주간** / Grok Bot 체험 | `get-sand-usage-status`의 `usagePercent` | `nextResetTimestampUtc` (체험은 없음) |

- 플랜 이름은 `membershipType`(예: Ultra).
- `billingCycleEnd`는 다음 결제일로도 쓴다(월 구독 기준, 연 구독이면 다를 수 있음). 2026-10-13 실제 계정에서 다음 결제일과 맞음을 확인.
- 팀 플랜·꺼진 플랜은 거부한다(개인 플랜만).
- **Grok Bot**: `/Applications/Grok Bot.app`(번들 ID `com.anysphere.sand`)은 Cursor 회사(Anysphere)가 만든 앱이고 한도도 Cursor 계정에 붙어 있다. 포함 한도가 있으면(`includedLimitZero == false`, 옛 응답은 `hasNonZeroIncludedLimit`) “주간”, 없고 체험 기간이면 “체험”, 둘 다 아니면 표시하지 않는다. xAI의 [[Grok]] 구독 한도와는 별개다.
- Grok Bot 조회가 실패해도 Cursor 숫자는 보여준다.
- **2026-10-15부터 Grok Bot은 따로 보여준다.** Cursor 계정을 읽을 때 Grok Bot 한도가 있으면 딸린 Grok Bot 계정이 저절로 생기고, 같은 로그인으로 읽는다(`GrokBotProvider`). Cursor 계정에는 Cursor 모델·기타 모델만. [[2026-10-15 Grok Bot 따로 보여주기]]

## 로그인

- 로그인 창은 `https://cursor.com/dashboard`를 연다 → 로그인 전이면 `/api/auth/login` → `authenticator.cursor.sh`로 이동 → 로그인 후 `cursor.com/dashboard`로 돌아오면 읽기를 시도한다.
- Google 로그인은 앱 안 창에서 막힐 수 있다. GitHub·이메일 로그인 안내. [[Google 로그인 제약]]

## 수집 순서

화면에 띄우지 않는 WKWebView로 `https://cursor.com/robots.txt`를 연 뒤 페이지 안에서 `fetch`.

1. `GET /api/auth/me` → `email`
2. `GET /api/usage-summary`
3. `POST /api/dashboard/get-sand-usage-status` body `{}` (실패해도 계속)

## 응답 형식 확인 이력

| 날짜 | 계정 | 확인 방법 | 내용 |
|---|---|---|---|
| 2026-10-13 | — | AI-Tracker `electron/providers/local.js` `parseCursor`·`parseGrokBot` 해석을 옮김 | 테스트 `CursorTests` |
| 2026-10-13 | 본인 | 사용자 로그인 후 앱 표시 | Cursor 모델·기타 모델·Grok Bot 주간 표시. 실제 응답 원문은 기록하지 않음 |
| 2026-10-13 | 로그인 안 함 | curl | `robots.txt` 200, **`/api/auth/me` 204(빈 응답)**, `/api/usage-summary` 401, `/dashboard` 307 → `/api/auth/login`. 204도 로그인 필요로 처리 |

## 깨짐 기록

아직 없음.
