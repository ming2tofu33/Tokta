---
title: "2026-10-13 서비스를 ChatGPT와 Claude 두 개로 정리"
project: Tokta
type: decision
created: 2026-10-13
tags: [tokta/decision, tokta/product]
---

# 2026-10-13 서비스를 ChatGPT와 Claude 두 개로 정리

- 배경: 메뉴에 Claude Code·Codex·Claude·ChatGPT가 따로 있었다. 사용자 “Claude Code 가 따로 필요한 걸까? 그냥 ChatGPT, Claude 이렇게 일단 2개만 두면 안돼?”
- 결정: 서비스는 **ChatGPT**와 **Claude** 두 개.
  - Claude Code는 Claude 계정과 한도를 같이 쓰므로 Claude에 포함된다. Claude Code CLI 수집기는 삭제했다(첫 커밋 전이라 git 기록 없음, 약 80줄).
  - Codex는 ChatGPT 구독의 한도라서 ChatGPT로 묶는다. ChatGPT 웹은 일반 채팅 한도를 숫자로 주지 않아, 숫자로 볼 수 있는 한도는 Codex 한도뿐이다. 오해가 없게 구간 이름 앞에 `Codex`를 붙인다.
- 영향: 저장된 `codex` 계정은 `chatgpt`로, `claudeCode` 계정은 읽을 때 뺀다. [[저장 데이터와 이전]]
- 뒤에 서비스를 늘릴 때는 수집기가 생긴 서비스만 `Service`에 추가한다.
