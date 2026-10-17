---
title: "Gemini"
project: Tokta
type: service
status: superseded
collection: none
created: 2026-10-13
updated: 2026-10-14
tags:
  - tokta/service
  - tokta/gemini
---

# Gemini

> 2026-06-18부터 Google이 개인 계정(무료·AI Pro·AI Ultra)의 Gemini CLI·Code Assist를 끝냈다. 개인 계정의 Gemini 한도는 [[Antigravity]]에서 읽는다. 아래는 Gemini CLI 방식 기록이다.

| 항목 | 내용 |
|---|---|
| 지원 상태 | **Antigravity로 대체** — Gemini CLI 방식은 2026-10-14 만들었다가 뺐다. → [[Antigravity]] |
| 수집 방식 | Gemini CLI 로그인(`~/.gemini/oauth_creds.json`) → `cloudcode-pa.googleapis.com` quota API |
| 마지막 확인 | 2026-10-14 — **무료 개인 계정은 Google이 Gemini CLI 지원을 끝내 한도를 읽을 수 없음**(Antigravity로 이전 안내). 유료(AI Pro 등)·회사 계정은 확인 전 |
| 코드 | `Tokta/Providers/GeminiProvider.swift` |

## 무엇을 보여주나

**Gemini CLI·Code Assist 한도**다. gemini.google.com 앱 채팅 한도는 숫자로 나오지 않는다. ChatGPT 칸이 Codex 한도인 것과 같은 방식이다. 구간 이름은 모델 이름(“2.5 Pro”, “2.5 Flash”).

## 로그인과 토큰

- Gemini CLI가 시스템 브라우저로 Google 로그인을 받으므로 [[Google 로그인 제약]]에 걸리지 않는다.
- 연결: 설정 → 계정 → “이 Mac 로그인 연결” → Gemini, 또는 첫 화면 “Gemini 연결”. 로그인 전이면 “Gemini CLI 열기”가 터미널에서 `gemini`를 실행해 로그인을 받는다.
- 토큰은 한 시간쯤 만에 만료된다. Tokta는 **갱신하거나 파일에 쓰지 않는다**([[2026-10-13 Grok 추가와 토큰 갱신을 CLI에 맡김]]과 같은 원칙). 만료되면 카드에 “터미널에서 gemini를 한 번 실행하면 갱신됩니다”가 뜨고 마지막 값은 남는다.
- 다중 계정은 하지 않는다. Gemini CLI가 계정별 로그인 폴더를 지원하는지 확인 전이다.

## 수집 순서

1. `oauth_creds.json`의 `access_token`, `expiry_date`(밀리초), `id_token`(이메일)
2. `POST v1internal:loadCodeAssist` `{metadata: {ideType: "GEMINI_CLI", pluginType: "GEMINI"}}` → `cloudaicompanionProject`(문자열 또는 `{id}`), `currentTier.name`(요금제로 표시). `currentTier`가 없고 `ineligibleTiers`에 `UNSUPPORTED_CLIENT`면 “이 Google 계정은 Gemini CLI 한도를 제공하지 않습니다”
3. `POST v1internal:retrieveUserQuota` `{project}` → `buckets[]`: `modelId`, `remainingFraction`(0...1), `resetTime`. 같은 모델이 여러 번 오면 가장 빠듯한 것만.

## 응답 형식 확인 이력

| 날짜 | 계정·플랜 | 확인 방법 | 내용 |
|---|---|---|---|
| 2026-10-14 | — | AI-Tracker `electron/providers/local.js` `readGemini` 코드를 옮김 | 실제 응답 확인 전 |
| 2026-10-14 | 본인, **구독 없음(무료 개인)** | Gemini CLI 0.63.0 로그인 후 첫 사용 | **로그인은 되지만 사용 불가.** CLI 메시지: “This client is no longer supported for Gemini Code Assist for individuals. To continue using Gemini, please migrate to the Antigravity suite of products”. Tokta에서도 숫자가 들어오지 않음 |

## 결정할 것

- 토큰이 자주 만료돼 불편하면: 메모리에서만 갱신(파일에 쓰지 않음)할지. Google 갱신 토큰은 쓸 때 바뀌지 않아 CLI 로그인을 깨뜨리지 않지만, Gemini CLI의 공개 OAuth 클라이언트 정보를 Tokta가 써야 한다.
- 웹 Gemini 구독 한도가 꼭 필요한지(Chrome 확장 다리 방식, AI-Tracker에서 쓰던 것).
