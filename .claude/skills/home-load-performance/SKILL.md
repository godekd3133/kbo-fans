---
name: home-load-performance
description: 홈 첫 진입 속도와 초기 로딩 체감을 개선할 때 사용한다. `scoreboard/home` 경량 endpoint, scoreboard 캐시 우선 렌더, secondary section 지연 로딩, 부가 서비스 초기화 지연, 홈 로딩 계측 로그를 수정하거나 검증할 때 이 스킬을 먼저 읽는다.
---

# Home Load Performance

## Goals

- 앱을 열면 흰 화면보다 즉시 다크 런치 화면이 보여야 한다.
- 홈 첫 프레임은 scoreboard 중심으로 최대한 빨리 떠야 한다.
- 브리프/퀵 섹션은 첫 프레임 뒤에 붙어도 된다.

## Current performance strategy

- 네이티브 런치 스크린: 다크 테마
- 홈 loading: 전체 스피너 대신 스켈레톤 카드
- home API: `/scoreboard/home`
- scoreboard: 오늘 결과 캐시 우선 렌더
- refresh timer: interval + scoreboard signature 가 바뀔 때만 재스케줄
- secondary sections:
  - `schedule`
  - `standings`
  - `recordsOverview`
  는 첫 scoreboard 데이터 프레임 뒤에 provider 구독 자체를 지연
- platform services:
  - push
  - widget sync
  - workmanager
  는 앱 첫 프레임 이후 지연 초기화

## Files to check

- `app/lib/features/home/home_screen.dart`
- `app/lib/main.dart`
- `app/lib/data/repositories/api_game_repository.dart`
- `backend/src/kbo_fans_backend/api/routes/scoreboard.py`
- `backend/src/kbo_fans_backend/services/scoreboard.py`

## Logging

- app dev console:
  - `HOME loaded ...ms`
  - `HOME secondary ...ms`
- backend log:
  - `scoreboard schedule ...ms`
  - `scoreboard main list ...ms`
  - `scoreboard enrich ...ms`
  - `scoreboard total ...ms`

## Safe optimization order

1. Payload 경량화
2. Cache-first render
3. Defer non-critical providers
4. Defer platform init

## Avoid

- 홈 첫 화면에서 상세용 highlight/youtube fetch 수행
- 홈 진입 시 전체 API를 한꺼번에 강제 구독
- `_secondarySectionsEnabled`가 false인 상태에서 `homeAggregateProvider`를 watch
- build/rebuild마다 홈 refresh timer를 cancel/restart
- 첫 프레임 전에 무거운 `SharedPreferences`/plugin init 몰아넣기
