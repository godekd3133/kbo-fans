---
name: kbo-relay-integration
description: KBO 공식 로그인 기반 문자중계 relay를 다룰 때 사용한다. `LiveText.aspx`, `LiveTextView1.aspx`, `LiveTextView2.aspx` 경로 추적, 세션 재로그인, final/live fallback 정책, currentAtBat/baseState/play-by-play 파싱, relay UI 데이터 계약을 수정하거나 검증할 때 이 스킬을 먼저 읽는다.
---

# KBO Relay Integration

## When to use

- `/api/game/{gameId}/relay`를 수정할 때
- KBO 로그인 세션, 세션 만료, 재로그인, 에러 페이지 fallback을 다룰 때
- `currentAtBat`, `baseState`, `relayItems` 파싱 규칙을 바꿀 때
- relay가 summary fallback으로 떨어지는 원인을 볼 때

## Current source of truth

- 로그인 후 공식 `문자중계보기`는 `window.open('/Game/LiveText.aspx?...')`로 열린다.
- 실제 play-by-play 본문은 `POST /Game/LiveTextView2.aspx`
- 현재 타석/선수 카드도 `LiveTextView2.aspx`에서 파싱한다.
- `LiveTextView1.aspx`는 scoreboard/other game summary에 가깝고 현재 구현상 핵심 source는 아니다.

## Required env

- `backend/.env`
- `KBO_RELAY_USER_ID`
- `KBO_RELAY_PASSWORD`

자격증명은 코드나 저장소 문서에 하드코딩하지 않는다. 로컬 `.env` 또는 Keychain 같은 secure storage 에만 둔다.

## Parsing rules

- play-by-play: `#numCont1` ~ `#numCont10` 내부 `span`
- 공수 전환: `...회초 ...공격`, `...회말 ...공격`
- 현재 타석:
  - `p.present`
  - `div.playerName`
  - `.playerBox.awayBox .player-info-wrap`
  - `.playerBox.homeBox .player-info-wrap`
- `baseState`: `imgThisGameBase`의 `ground_baseN.png`에서 매핑

## Fallback policy

- 우선 로그인 relay 시도
- 실패 시 세션/쿠키 초기화 후 강제 재로그인 1회 재시도
- 그래도 실패하면 backend summary relay fallback
- final 경기도 로그인 relay가 성공하면 full play-by-play 유지

## Event classification guidance

- `RUNS`: 득점, 홈인, 홈런
- `WALK`: 볼넷
- `STRIKEOUT`: 삼진
- `OUT`: 플라이 아웃, 땅볼 아웃, 일반 아웃
- `SUBSTITUTION`: 교체
- `HIT`: 1루타/2루타/3루타/안타
- 나머지 pitch-by-pitch는 `PLAY`

## Validation

- `backend/tests/test_relay_crawler.py`
- `backend/tests/test_relay_service.py`
- 실호출 확인:
  - `RelayService().get_relay('20260329LTSS0')`

## Notes

- KBO relay는 로그인 상태와 세션 수명에 민감하다.
- `firebase_core dummy.o has no symbols` 같은 iOS 경고와는 무관하다.
