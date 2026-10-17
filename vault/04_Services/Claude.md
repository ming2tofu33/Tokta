---
title: "Claude"
project: Tokta
type: service
status: active
collection: web-session
last_verified: 2026-10-13
created: 2026-10-13
updated: 2026-10-13
tags:
  - tokta/service
  - tokta/claude
---

# Claude

| 항목 | 내용 |
|---|---|
| 지원 상태 | 지원 — 계정 여러 개 (계정별 웹 로그인) |
| 수집 방식 | 계정별 WebKit 저장소 + claude.ai 내부 API |
| 마지막 확인 | 2026-10-13, 사용자 실제 로그인 |
| 코드 | `Tokta/Providers/ClaudeWebProvider.swift`, `WebSessions.swift`, `ClaudeUsageParser.swift`, `Tokta/UI/LoginWindow.swift` |

결정 배경: [[2026-10-13 Claude는 계정별 웹 로그인으로 수집]]

## 무엇을 보여주나

Claude 구독 한도. claude.ai, 데스크톱 앱, Claude Code가 이 한도를 같이 쓰므로 Claude Code 사용량도 여기에 포함된다.

## 플랜별 한도 규칙

| 구간 | 응답 키 | 비고 |
|---|---|---|
| 5시간 | `five_hour` / `limits.kind=session` | |
| 주간 | `seven_day` / `limits.kind=weekly_all` | |
| 모델별 주간 | `seven_day_opus`, `seven_day_sonnet`, `seven_day_fable` / `limits.kind=weekly_scoped` | 플랜에 따라 있거나 없다 |

- 플랜 표시는 조직 기능에 `claude_max`가 있으면 Max, `claude_pro`가 있으면 Pro.
- 5시간 구간은 그 구간의 첫 메시지부터 5시간 뒤에 리셋된다는 외부 설명이 있다(Usagebar 블로그). Tokta에서 직접 확인하지는 않았고, 앱은 응답의 `resets_at`만 쓴다.

## 계정별 저장소와 로그인

- `WKWebsiteDataStore(forIdentifier: account.id)` — 계정 하나에 쿠키 저장소 하나. 계정을 지우면 저장소도 지운다.
- 로그인 창은 그 계정 저장소로 `https://claude.ai/login`을 연다. 페이지 이동이 끝날 때와 4초마다, 주소가 login이 아니면 사용량 읽기를 시도하고 성공하면 창을 닫는다.
- 새 창으로 여는 로그인 단계는 같은 창에서 이어서 연다.
- Google 로그인이 막히면 같은 이메일로 “이메일로 계속하기”. [[Google 로그인 제약]]

## 수집 순서

화면에 띄우지 않는 WKWebView로 `https://claude.ai/robots.txt`(가장 가벼운 같은 출처 페이지)를 연 뒤 페이지 안에서 `fetch`를 실행한다. 사이트가 직접 보내는 요청과 같아서 쿠키·보안 확인을 그대로 통과한다.

1. `/api/account` → 이메일, uuid
2. `/api/organizations` → 채팅 가능한 조직 중 `lastActiveOrg` 쿠키의 조직, 하나뿐이면 그 조직. 애매하면 임의로 고르지 않고 실패
3. `/api/organizations/{id}/usage`
3-1. `/api/organizations/{id}/subscription_details` → 다음 결제일·주기·통화·해지 여부 (실패해도 계속). [[2026-10-13 구독료와 결제일 관리#후속 — 결제일 자동으로 가져오기 (같은 날)]]
4. `/api/account` 다시 → 도중에 계정이 바뀌었으면 버림

401/403 → 로그인 필요, 429 → 조회 제한, JSON이 아니면 → 보안 확인 필요.

## 응답 형식 확인 이력

| 날짜 | 계정·플랜 | 확인 방법 | 내용 |
|---|---|---|---|
| 2026-10-13 | — | AI-Tracker `electron/claude-accounts.js`의 해석 규칙을 옮김 | 키 방식과 `limits` 배열 방식 둘 다 읽음. `resets_at` 소수점 자릿수가 일정하지 않아 초 단위로 자름 |
| 2026-10-13 | 본인 | 사용자 로그인 후 앱 표시 | 실제 응답 원문은 아직 기록하지 않음 |
| 2026-10-13 | 본인 5계정(같은 Team 조직) | 역할·응답 코드만 출력 | 소유자(`owner`·`primary_owner`)만 200, 일반 멤버(`user`)는 403 `permission_error`. 멤버는 같은 조직 소유자 계정 값을 쓴다 |
| 2026-10-13 | 본인 2계정 | `subscription_details` 항목 이름만 출력해 확인 | `next_charge_date: "2026-11-10"`, `next_charge_at`, `billing_interval: "monthly"`, `currency: "USD"`, `status: "active"`, `plan_ending_at`, `payment_method`(읽지 않음). `/subscription`은 405, `/billing`은 404 |

테스트: `ClaudeParsingTests`.

## 깨짐 기록

아직 없음. 생기면 `01_Logs/Incidents`에 남기고 여기에 연결한다.
