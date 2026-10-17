---
title: "Antigravity"
project: Tokta
type: service
status: active
collection: antigravity-cli
last_verified: 2026-10-14
created: 2026-10-14
updated: 2026-10-14
tags:
  - tokta/service
  - tokta/antigravity
  - tokta/gemini
---

# Antigravity

| 항목 | 내용 |
|---|---|
| 지원 상태 | 지원 — **계정 하나**(이 Mac의 Antigravity CLI `agy` 로그인) |
| 수집 방식 | `agy -p /usage --output-format json` |
| 마지막 확인 | 2026-10-14, 본인 무료 개인 계정, agy 1.3.4 — 실제 응답 확인, Tokta 수집기로 실제 조회(Gemini 주간 100%, Claude·GPT 주간 100%) |
| 코드 | `Tokta/Providers/AntigravityProvider.swift` |

## 무엇을 보여주나

Google Antigravity의 모델 한도. 2026-06-18부터 Google이 개인 계정(무료·AI Pro·AI Ultra)의 Gemini CLI·Code Assist를 끝내고 Antigravity로 옮겨서, **개인이 숫자로 볼 수 있는 Gemini 한도는 이것**이다. gemini.google.com 앱 채팅 한도와는 다르다. → [[Gemini]]

- 그룹마다 한도를 같이 쓴다: **Gemini**(Gemini Flash·Pro), **Claude·GPT**(Claude Opus·Sonnet, GPT-OSS). 토큰 비용에 비례해 줄어든다.
- 구간 이름: “Gemini 주간”, “Claude·GPT 주간”. 5시간 구간(`window: session` 등)이 오면 “Gemini 5시간”처럼 붙인다(유료 등급, 확인 전).

## 로그인과 토큰

- 설치: `curl -fsSL https://antigravity.google/cli | bash` → `~/.local/bin/agy`. 설치 스크립트가 `~/.zshrc`·`~/.zprofile`에 PATH 줄을 넣는다.
- 로그인: 터미널에서 `agy` → Google OAuth → 브라우저. 시스템 브라우저라 [[Google 로그인 제약]]에 안 걸린다.
- 토큰은 agy가 macOS 키체인(서비스 `antigravity`, agy 전용 접근)에 둔다. **Tokta는 토큰을 읽지 않고** agy에 사용량만 묻는다. 갱신도 agy가 한다.
- Tokta 연결: 설정 → 계정 → “이 Mac 로그인 연결” → Antigravity, 또는 첫 화면 “Antigravity 연결”. “Antigravity CLI 열기”는 터미널에서 `agy` 실행.

## 수집 순서

`agy -p /usage --output-format json --print-timeout 30s`(홈 폴더에서, 40초 제한). `/usage`는 모델에 묻지 않는 명령이라 토큰 0, 한도를 쓰지 않는다. 앱 내부 서버(`GetUserStatus`)나 Google OAuth 클라우드 API를 직접 부르는 방법(CodexBar 방식)은 쓰지 않는다 — 포트·CSRF 토큰 찾기, 다른 앱의 OAuth 클라이언트 사용이 필요해서.

## 응답 형식 확인 이력

| 날짜 | 계정·플랜 | 확인 방법 | 내용 |
|---|---|---|---|
| 2026-10-14 | 본인, 무료 개인 | agy 1.3.4 직접 실행 + Tokta 수집기 실제 조회 | 아래 형식. 그룹 2개, 각각 주간 구간 하나 |

```json
{"status": "SUCCESS", "usage": {"total_tokens": 0},
 "command": {"name": "usage", "data": {"groups": [
   {"name": "Gemini Models", "buckets": [{"id": "gemini-weekly", "name": "Weekly Limit Remaining", "window": "weekly", "remaining_fraction": 1, "reset_time": "2026-10-20T16:11:04Z"}]},
   {"name": "Claude and GPT models", "buckets": [{"id": "3p-weekly", "window": "weekly", "remaining_fraction": 1, "reset_time": "..."}]}]}}}
```

같은 응답이 테스트 `AntigravityTests.realResponse`에 들어 있다.

## 알려진 위험

- 외부 보고: 백엔드가 사용량과 상관없이 `remaining_fraction: 1`을 돌려준 적이 있다(antigravity-cli 이슈 #387). 실제로 쓴 뒤 숫자가 줄어드는지 확인 필요.
- 다중 계정 안 함. agy가 계정별 설정 폴더를 지원하는지 확인 전.

## 깨짐 기록

아직 없음.
