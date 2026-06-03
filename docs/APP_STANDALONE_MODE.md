# 앱 단독 모드 전환 현황

> 최종 수정: 2026-06-04

> 현재 정책: 앱 standalone/no-backend 모드가 기본이다. 일반 local/dev/release/web/native 실행은 direct KBO source와 허용된 snapshot을 사용하고, backend API는 `USE_BACKEND_API=true` 명시 opt-in에서만 사용한다.

## 목적

이 문서는 KBO Fans 앱이 노트북/로컬 FastAPI 없이도 iOS/Android/Web에서 동작하도록 유지하는 범위와 한계를 정리한다.

## 현재 결론

- 모바일(iOS/Android)과 웹 모두 일반 실행의 기본 데이터 경로는 no-backend direct mode다.
- 로컬 iOS/Android/Web 실행 스크립트는 backend health를 요구하지 않고 direct KBO + snapshot 경로를 주입한다.
- backend API는 legacy/reference 경로이며, `USE_BACKEND_API=true` 를 명시한 검증 세션에서만 사용한다.
- `API_BASE_URL` 단독 지정은 정상 앱 실행을 API mode로 바꾸지 않는다.
- release build에서는 `API_BASE_URL`을 push / Live Activity token registration endpoint로 함께 주입할 수 있다. 이 값만으로 데이터 provider routing은 backend mode로 바뀌지 않는다.
- API 실패 후 direct fallback으로 내려가는 구조가 아니라, direct 경로가 기본 primary source다.

## 완료된 전환 범위

### 경기 데이터

- 일반 빌드에서는 `KboDirectRepository`를 사용한다.
- 명시적 backend mode에서만 `ApiGameRepository`를 사용한다.
- direct source:
  - scoreboard
  - schedule
  - standings
  - game detail
  - lineup
  - boxscore
  - highlight link / youtube search fallback

### 홈 aggregate

- 일반 빌드에서는 `/api/home` 의존을 제거하고 앱 내부에서 조합한다.
- 명시적 backend mode에서만 `/api/home` 을 사용한다.
- 입력 데이터:
  - scoreboard
  - schedule
  - standings
  - records overview

### 기록실 / 팀 기록 / 리더보드

- 일반 빌드에서는 records/player 경로가 direct KBO를 먼저 시도하고, 실패 시 local asset snapshot repository로 내려간다.
- 명시적 backend mode에서는 records/player 경로가 API를 먼저 사용한다.
- direct 기록실은 KBO WebForms 세션 cookie와 전체 form field를 유지해 시즌 변경 POST를 수행한다.
- 2025/2024 같은 과거 시즌의 리더보드, 팀 타격/투구 스탯, 팀별 야수/투수 기록은 KBO 기록 테이블의 시즌/팀 filter 결과로 구성한다.
- asset source:
  - `app/assets/bootstrap/team_players/*.json`
  - `app/assets/bootstrap/team_stats/*.json`
  - `app/assets/bootstrap/records_overview.json`
  - `app/assets/bootstrap/standings.json`

### 알림

- 경기 이벤트 알림은 로컬 알림 중심으로 동작한다.
- 모바일에서는 push registration / FCM topic sync를 local-only 모드에서 비활성화한다.
- local-only 모드에서도 홈 스코어보드 polling 기준의 로컬 알림은 동작한다.
  - 경기 시작
  - 득점
  - 홈런
  - 역전
  - 경기 종료
  - 이닝 교대
  - 라인업 공개/변경

### 위젯 / Live Activity

- 위젯 데이터는 앱이 직접 저장하고 갱신한다.
- iOS WidgetKit / Live Activity와 Android widget provider가 같은 앱 내부 scoreboard sync 흐름을 사용한다.

## 아직 남아 있는 한계

### 문자중계

- full play-by-play는 KBO 로그인 세션이 필요할 수 있다.
- no-backend 빌드에서 로그인 relay가 실패하면 앱 direct summary relay fallback으로 내려간다.
- 즉 “완전 빈 화면”은 피하지만, 항상 pitch-by-pitch가 보장되지는 않는다.

### 푸시

- 서버 없는 구조에서는 FCM 원격 push를 쓸 수 없다.
- 앱이 열려 있거나 시스템이 허용하는 범위에서만 local alert / widget update가 가능하다.
- 즉 local-only 알림은 완전한 서버 push가 아니라 앱 refresh 주기 기준 best-effort다.

### 기록실

- 현재 기록실 기본 경로는 direct KBO 기반이며, generated local asset snapshot은 안정 데이터 fallback으로만 사용한다.
- 과거 시즌 팀 기록실도 앱 내부 direct crawler가 KBO 기록 테이블에서 가져올 수 있다.
- production release도 backend snapshot/API를 기본 전제로 두지 않는다.

### 웹

- 웹은 CORS 제약이 있으므로 direct repository가 CORS proxy 경로를 사용한다.
- 웹도 no-backend standalone 범위에 포함한다.

## 주요 파일

### 앱 데이터 경로

- `scripts/codex-run.sh`
- `scripts/codex-run-ios-local-release.sh`
- `app/lib/data/providers.dart`
- `app/lib/data/repositories/kbo_direct_repository.dart`
- `app/lib/data/repositories/local_asset_player_repository.dart`
- `app/lib/data/models/home_aggregate.dart`

### 홈 / 기록실 / 상세

- `app/lib/features/home/home_screen.dart`
- `app/lib/features/records/records_screen.dart`
- `app/lib/features/game_detail/game_detail_screen.dart`
- `app/lib/features/game_detail/tabs/relay_tab.dart`
- `app/lib/features/game_detail/tabs/lineup_tab.dart`
- `app/lib/features/game_detail/tabs/boxscore_tab.dart`

### 알림 / 위젯

- `app/lib/services/game_event_alert_service.dart`
- `app/lib/services/ticket_alert_service.dart`
- `app/lib/services/push_notification_service.dart`
- `app/lib/services/widget_sync_service.dart`
- `app/lib/services/live_activity_service.dart`

## 운영 규칙

- 기본 앱 모드에서 backend 수정은 앱 동작을 바꾸지 않아야 한다.
- 모바일/웹 문제를 볼 때는 먼저 app repository routing, direct KBO 응답, snapshot freshness를 확인한다.
- KBO direct path는 request shape correctness가 retry보다 우선이다.
- 하이라이트 / overview 같은 부가 정보는 lazy load가 원칙이다.

## 다음 우선순위

1. 웹 direct KBO CORS proxy 경로의 안정성과 장애 표시를 실사용 기준으로 검증
2. 기록실/선수 상세 direct source 실패 시 generated snapshot 범위와 freshness 정책 보강
3. Android/iOS widget 실기 검증 마무리
4. backend API reference 코드를 앱 완성 blocker와 분리해 유지할 범위 결정
