---
title: "2026-10-13 Cursor 추가와 Grok Bot을 Cursor 계정에서 읽기"
project: Tokta
type: decision
created: 2026-10-13
tags: [tokta/decision, tokta/cursor, tokta/grok]
---

# 2026-10-13 Cursor 추가와 Grok Bot을 Cursor 계정에서 읽기

- 배경: Grok을 붙인 뒤 사용자 “그록 자체랑 그록봇 쿼타도 보여줘야 하는데?”, 이어서 “커서도 추가해줘”.
- 확인한 사실: Grok Bot(`/Applications/Grok Bot.app`)의 번들 ID는 `com.anysphere.sand` — Cursor 회사 앱이고, AI-Tracker도 Grok Bot 주간 한도를 cursor.com API에서 읽었다. xAI의 Grok 구독과 별개.
- 사용자 선택:
  - Grok Bot 로그인 방식: **cursor.com 웹 로그인**(추천안). Cursor 앱의 로그인 저장소를 읽는 방식(AI-Tracker)은 쓰지 않는다.
  - 지금 Grok 숫자(주간 100% 남음)는 grok.com과 맞다 — “이번 주 거의 안 썼어요”. Grok 수집은 그대로.
- 결정:
  - 서비스에 **Cursor** 추가. Cursor 계정 카드 하나에 Cursor 모델·기타 모델·**Grok Bot 주간**을 함께 보여준다. 로그인이 한 번이면 된다.
  - 로그인 창·숨은 브라우저를 Claude 전용에서 사이트 공통(`WebLoginSite`)으로 넓혔다.
- 영향: “지금 쓰기” 추천과 메뉴바 아이콘은 계정의 가장 빠듯한 구간을 보므로, Grok Bot을 다 쓰면 그 Cursor 계정 전체가 빠듯하게 보인다. 불편하면 Grok Bot을 별도 서비스로 나누는 것을 검토.
- 결과: [[Cursor]]. 테스트 통과, 설치(빌드 4). 사용자 로그인·조회 확인.
