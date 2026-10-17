---
title: "Project Map"
project: Tokta
type: index
status: active
created: 2026-10-13
updated: 2026-10-13
tags:
  - tokta/index
---

# Project Map

번호별 분류를 쓰되 앱 제작에 맞게 영역을 줄였다.

| 폴더 | 역할 | 시작 문서 |
|---|---|---|
| 00_Home | 탐색과 운영 원칙 | [[Tokta Dashboard]] |
| 01_Logs | 결정·깨짐 기록 | [[00 깨짐 기록 목차]] |
| 02_Product | 포지셔닝·기능 범위·로드맵 | [[포지셔닝과 범위]] |
| 03_Technical | 우리 코드: 앱 구조·저장·빌드 | [[00 기술 문서 목차]] |
| 04_Services | 바깥 서비스: 수집 방식·플랜별 한도·응답 확인 이력 | [[00 서비스 목차]] |
| 05_Research | 외부 제약·플랫폼 조사 | [[Google 로그인 제약]] |
| 06_Assets | 스크린샷·첨부 | `06_Assets/Attachments` |
| 90_Templates | 새 문서 양식 | [[결정 기록 템플릿]] · [[깨짐 기록 템플릿]] |

번호는 빈 번호 없이 잇는다. 새 영역은 06 다음 번호로 추가한다. [[2026-10-13 vault 서비스 카탈로그와 폴더 번호 정리]]

## 코드와의 관계

- 앱 코드: `~/Projects/Tokta/Tokta` (Xcode 프로젝트 `Tokta.xcodeproj`)
- 아이콘 원본·생성 스크립트: `~/Projects/Tokta/design/` — [[2026-10-13 앱 아이콘과 메뉴바 아이콘 v1]]
- 이전 Electron 버전: `~/Projects/AI-Tracker`. 서비스 API와 응답 해석의 참고 명세로만 쓴다. [[2026-10-13 Electron 대신 Swift 네이티브로 새로 시작]]
