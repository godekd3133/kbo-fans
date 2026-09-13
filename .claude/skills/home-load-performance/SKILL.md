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
- API client(Dio): `BackgroundTransformer`로 50KB 이상 JSON을 compute isolate에서 디코드(50KB 미만은 동기 유지). 캐시 eviction 스캔은 canonical `{"cachedAt":...,"data":{...}}` anchored regex로 처리해 쓰기마다 전체 엔트리를 디코드하지 않는다.

## Backend latency levers (2026-09-13 검증)

- scoreboard 계열(`/scoreboard`, `/compact`, `/game/{id}`): 적응형 TTL — LIVE/SUSPENDED 포함 8s, 비라이브 오늘은 다음 예정 시작−10s로 8~120s 클램프, 비당일/종료일 300s. 워커 공유 `_home_scoreboard_cache`·`KboSourceCache`는 푸시/Live Activity 신선도 때문에 8s 유지.
- 시즌/월 집계 캐시(schedule, standings, records overview·leaderboard, team/player stats): 900s TTL. TTL 만료~다음 warm 사이클 gap에 사용자 요청이 업스트림 크롤(수 초)을 지불하지 않도록 warm 주기보다 충분히 크게 잡는다.
- home-section warmer: API 프로세스 lifespan 스레드(`kbo-home-sections-warmer`)가 `get_home(오늘)`을 240s 주기로 호출해 섹션 캐시를 상시 유지. `HOME_SECTIONS_WARM_ENABLED`(release 기본 on), `HOME_SECTIONS_WARM_INTERVAL_SECONDS`.
- `GZipMiddleware`(1KB+) — 36KB 스케줄이 wire ~2KB 수준으로 축소.
- push registry 락 대기 8s — 워커 sync 쓰기와 경합해도 register/start-token이 503으로 떨어지지 않게.

## Files to check

- `app/lib/features/home/home_screen.dart`
- `app/lib/main.dart`
- `app/lib/data/repositories/api_game_repository.dart`
- `app/lib/data/api/api_client.dart`
- `backend/src/kbo_fans_backend/api/routes/scoreboard.py`
- `backend/src/kbo_fans_backend/services/scoreboard.py`
- `backend/src/kbo_fans_backend/services/home.py`
- `backend/src/kbo_fans_backend/main.py` (warmer, GZip, request guard)
- `backend/src/kbo_fans_backend/utils/ttl_cache.py`

## Logging

- app dev console:
  - `HOME loaded ...ms`
  - `HOME secondary ...ms`
- backend log — 주의: uvicorn journal에는 access 라인만 보이고 서비스 로그는 `/var/log/kbo-fans/backend.log`에 간다:
  - `scoreboard schedule/main list/enrich/total ...ms`
  - `home_upstream_timing ... scoreboardMs= scheduleMs= standingsMs= recordsMs=`
  - `home_total_timing ... totalMs=`
  - `records_overview_timing ... pageCount= avgMs= hrMs= eraMs= totalMs=`
  - `home sections warmer started interval=...s` / `home sections warm failed [..]`
  - `Slow request ...ms GET /api/...`

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
