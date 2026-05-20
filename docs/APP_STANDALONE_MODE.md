# 앱 단독 모드 전환 현황

> 최종 수정: 2026-05-20

> 현재 정책: 이 문서는 API 미구현 영역을 검증하기 위한 임시 direct-primary 모드를 정리한다. 일반 local/native 운영 기준은 backend API 경로이며, direct KBO는 `PREFER_DIRECT_SCRAPE=true` 를 명시한 임시 검증 빌드에서만 사용한다.

## 목적

이 문서는 KBO Fans 앱이 노트북/로컬 FastAPI 없이도 iOS/Android 기기 단독으로 동작하도록 전환했던 범위와, 현재 API-first 정책으로 대체된 지점을 정리한다.

## 현재 결론

- 모바일(iOS/Android)과 웹 모두 일반 실행의 기본 데이터 경로는 backend API다.
- 로컬 iOS/Android 실행은 `scripts/codex-run.sh` 가 로컬 backend health를 확인하고 `API_BASE_URL` 을 주입한다.
- 로컬 backend가 없으면 direct fallback으로 조용히 내려가지 않고 실행을 중단한다.
- iPhone local release-mode 검증은 `./scripts/codex-run-ios-local-release.sh` 로 분리한다.
- 이 경로는 아직 API 구현이 비어 있는 영역을 검증하기 위한 임시 direct-primary 모드다.
- API 실패 후 direct fallback으로 내려가는 구조가 아니라, 실행 명령에서 direct-primary를 명시한다.

## 완료된 전환 범위

### 경기 데이터

- 일반 빌드에서는 `ApiGameRepository`를 사용한다.
- 명시적 direct-primary 빌드에서만 `ApiGameRepository` 대신 `KboDirectRepository`를 사용한다.
- direct source:
  - scoreboard
  - schedule
  - standings
  - game detail
  - lineup
  - boxscore
  - highlight link / youtube search fallback

### 홈 aggregate

- 일반 빌드에서는 `/api/home` 을 사용한다.
- 명시적 direct-primary 빌드에서만 `/api/home` 의존을 제거하고 앱 내부에서 조합한다.
- 입력 데이터:
  - scoreboard
  - schedule
  - standings
  - records overview

### 기록실 / 팀 기록 / 리더보드

- 일반 빌드에서는 records/player 경로가 API를 먼저 사용하고, 안정 데이터만 generated asset snapshot fallback을 허용한다.
- 명시적 direct-primary 빌드에서는 records/player 경로가 direct KBO를 먼저 시도하고, 실패 시 local asset snapshot repository로 내려간다.
- direct-primary 기록실은 KBO WebForms 세션 cookie와 전체 form field를 유지해 시즌 변경 POST를 수행한다.
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
- 명시적 direct-primary 빌드에서 로그인 relay가 실패하면 앱 direct summary relay fallback으로 내려간다.
- 즉 “완전 빈 화면”은 피하지만, 항상 pitch-by-pitch가 보장되지는 않는다.

### 푸시

- 서버 없는 구조에서는 FCM 원격 push를 쓸 수 없다.
- 앱이 열려 있거나 시스템이 허용하는 범위에서만 local alert / widget update가 가능하다.
- 즉 local-only 알림은 완전한 서버 push가 아니라 앱 refresh 주기 기준 best-effort다.

### 기록실

- 현재 모바일 기록실 기본 경로는 API 기반이며, generated local asset snapshot은 안정 데이터 fallback으로만 사용한다.
- 명시적 direct-primary 빌드에서는 과거 시즌 팀 기록실도 앱 내부 direct crawler가 KBO 기록 테이블에서 가져올 수 있다.
- 다만 production release 기준은 여전히 backend snapshot/API이며, direct-primary는 운영 backend 준비 전 검증용 경로다.

### 웹

- 웹은 CORS 때문에 direct KBO source를 그대로 쓰기 어렵다.
- 따라서 현재 문서의 “앱 단독 모드”는 모바일 기준이다.

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

- 기본 모바일 모드에서 backend를 수정하면 앱 동작이 바뀐다.
- 모바일 문제를 볼 때는 먼저 backend API 응답, `API_BASE_URL`, app repository routing을 확인한다.
- KBO direct path는 request shape correctness가 retry보다 우선이다.
- 하이라이트 / overview 같은 부가 정보는 lazy load가 원칙이다.

## 다음 우선순위

1. 기록실/선수 상세의 API 미구현 영역을 backend API 또는 generated snapshot 으로 승격
2. 임시 direct-primary relay 로그인 세션을 backend 소유 API 흐름으로 이전
3. Android/iOS widget 실기 검증 마무리
4. direct-primary 검증 경로를 제거할 수 있는 production API 준비 범위 결정
