---
title: "Google 로그인 제약"
project: Tokta
type: research
status: active
created: 2026-10-13
updated: 2026-10-13
tags:
  - tokta/research
---

# Google 로그인 제약

## 무엇이 막히나

Google은 앱 안에 넣은 웹 화면(WKWebView 등)에서의 Google 계정 로그인을 막는다. 2016년부터 단계적으로, 2021년부터 전면 적용. 앱이 입력되는 비밀번호를 가로챌 수 있다는 보안상 이유다. 시도하면 “이 브라우저 또는 앱은 안전하지 않을 수 있습니다”가 뜬다.

## 하지 않는 것

브라우저인 척 앱 신원을 꾸며 통과시키는 방법은 쓰지 않는다. Google 보안 정책을 일부러 피하는 것이고 언제든 다시 막힌다.

## 서비스별 영향

| 서비스 | 영향 | 대응 |
|---|---|---|
| Claude | Google로 가입한 계정이어도 이메일 기준 계정 | 같은 이메일로 “이메일로 계속하기”. 2026-10-13 사용자가 Google 가입 개인 계정을 이 방법으로 로그인 성공. Google 페이지로 가면 경고를 크게 띄운다 → [[2026-10-13 다중 계정 로그인 안내]] |
| Cursor | Google 로그인 막힘 | GitHub·이메일 로그인 |
| ChatGPT | 해당 없음 | Codex가 시스템 브라우저로 로그인 |
| Gemini | **Google 계정 자체가 로그인 수단이라 앱 안 창은 대안이 없음** | Antigravity CLI(agy)가 시스템 브라우저로 로그인 → 계정 하나 연결(개인 Gemini CLI는 2026-06-18 종료). [[Antigravity]] |
