---
title: "2026-10-13 Electron 대신 Swift 네이티브로 새로 시작"
project: Tokta
type: decision
created: 2026-10-13
tags: [tokta/decision, tokta/technical]
---

# 2026-10-13 Electron 대신 Swift 네이티브로 새로 시작

- 배경: AI-Tracker는 Electron 위젯이었다. 처음 추천은 "Electron으로 먼저 출시해 수요를 확인하고 반응이 오면 Swift로 다시 만들기"였다. 경쟁 Mac 앱이 거의 모두 네이티브이고, Electron 메뉴바 앱은 크기(약 150MB)와 평판에서 불리하다.
- 사용자 결정: “스위프트로 처음부터 다시 만들고 싶은데 가능해? 어차피 나는 내가 쓰려는 용으로 제대로 만들어보고 싶거든”
- 결과:
  - 새 저장소 `~/Projects/Tokta`. AI-Tracker 브랜치에 커밋 안 된 변경이 많아 분리했다.
  - AI-Tracker의 서비스 API·응답 해석은 명세로만 참고한다.
  - 네이티브라서 계정별 쿠키 저장소(`WKWebsiteDataStore(forIdentifier:)`)를 써서 Chrome 확장 없이 다중 계정이 가능해졌다. [[Claude]]
- 이름: 같은 날 **Tokta**(Token + Quota)로 확정. 같은 이름의 앱은 검색에서 찾지 못했다.
