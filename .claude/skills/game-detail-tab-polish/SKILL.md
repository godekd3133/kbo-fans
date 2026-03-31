---
name: game-detail-tab-polish
description: 경기 상세의 relay, lineup, boxscore 탭 UI를 다듬을 때 사용한다. 모바일 카드형 레이아웃, 팀명/로고/컬러 accent, 선발투수 카드, 핵심 선수 카드, relay badge 체계, 이모지 금지 규칙을 수정하거나 검증할 때 이 스킬을 먼저 읽는다.
---

# Game Detail Tab Polish

## UI principles

- 테이블보다 모바일 카드형 레이아웃을 우선
- `AWAY/HOME`만 쓰지 말고 실제 팀명과 로고를 같이 표시
- 팀 컬러 accent는 테두리, 배지, 강조 배경에 사용
- 긴 텍스트는 ellipsis 또는 wrap으로 정리
- 이모지는 쓰지 않는다

## Relay tab

- `currentAtBat` 카드:
  - 이닝
  - 주자 상황
  - 타자/투수
  - 볼/스트라이크/아웃
  - 최근 타석
- `baseState`는 텍스트만 두지 말고 베이스 다이어그램 badge로 렌더
- pitch detail line은 badge형으로 분리
- `교체`, `득점`, `경기 종료`는 스타일을 다르게 준다
- inning chip은 클릭 시 해당 구간으로 이동할 수 있어야 한다

## Lineup tab

- 팀 스위처: `AWAY/HOME + 팀명 + 로고`
- 요약 카드:
  - 팀명
  - 라인업 인원
  - 선발투수
- 선수는 카드형 row
  - 타순 배지
  - 이름
  - 포지션 badge

## Boxscore tab

- 팀 스위처는 lineup과 같은 구조로 통일
- 상단 summary card에 팀 소계 배치
- 핵심 타자 / 핵심 투수 카드 추가 가능
- 타자/투수 리스트는 표보다 카드형 우선

## User feedback captured

- 라인업/박스스코어는 “안 예쁘다”, “비율 대응이 안 된다”는 피드백이 있었다.
- `Away/Home`만 표시하는 것은 불충분했고, 팀명도 함께 보여야 했다.
- 앱 내 텍스트에 이모지를 넣지 않는다.
