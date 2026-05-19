# Local Native API Failure Analysis - 2026-05-20

## 증상

- iOS local debug 실행에서 홈/일정/순위/기록실이 로딩 또는 에러 화면에 머물렀다.
- Dev Console에는 `Failed host lookup: 'dev-api.kbofans.com'` 와 함께 `/scoreboard/home`, `/schedule`, `/standings`, `/records/overview`, `/home` 실패가 반복됐다.
- 홈 초기 화면은 여러 카드가 각각 `CircularProgressIndicator`를 보여 같은 화면에 spinner가 여러 개 떠 보였다.

## 직접 원인

`dev-api.kbofans.com` DNS가 해석되지 않았다. 로컬 확인에서도 `curl -I https://dev-api.kbofans.com/api/health` 는 `Could not resolve host` 로 실패했다.

하지만 앱이 local native 실행 중 이 도메인을 반복 호출한 것이 더 큰 문제다.

## 구조 원인

1. `APP_ENV=local` + iOS native + `API_BASE_URL` 미지정 상태에서 `AppConfig`의 API 기본값이 `https://dev-api.kbofans.com/api` 였다.
2. `gameRepositoryProvider`가 local native no-override 상황에서도 API repository를 반환해 홈/일정/순위가 dev API로 갔다.
3. `homeAggregateProvider`가 local native에서도 먼저 `/home` API를 시도했다.
4. 기록실 repository도 local native no-override에서 API를 먼저 호출해 `/records/overview` DNS 실패를 만들었다.
5. 앱 루트와 홈 화면 resume path가 모두 scoreboard를 invalidate할 수 있어 실패 로그가 빠르게 반복될 수 있었다.
6. 홈 loading shell은 placeholder 카드마다 spinner를 넣어 네트워크 실패/지연 시 사용자에게 중복 로딩처럼 보였다.

## 수정 방향

- `API_BASE_URL` override가 없는 local native는 dev API를 치지 않고 direct KBO / bundled asset / device snapshot 경로를 우선 사용한다.
- local native에 `API_BASE_URL`이 명시된 경우에는 해당 backend를 먼저 쓰되 실패 시 direct KBO fallback을 허용한다.
- web/dev/release는 backend API 중심을 유지한다.
- 위젯/백그라운드 scoreboard fetch도 같은 local native routing 정책을 따른다.
- resume sync는 앱 루트 한 곳에서 throttle을 적용해 중복 invalidation을 줄인다.
- 홈 loading shell은 spinner를 한 개만 남기고 나머지는 skeleton placeholder로 보여준다.

## 적용 파일

- `app/lib/core/config/app_config.dart`
- `app/lib/data/providers.dart`
- `app/lib/main.dart`
- `app/lib/services/widget_sync_service.dart`
- `app/lib/features/home/home_screen.dart`

## 검증 기준

- local native no-override에서 `/scoreboard/home`, `/schedule`, `/standings`, `/records/overview`, `/home` 이 `dev-api.kbofans.com` 으로 반복 호출되지 않는다.
- 앱 재개 시 `Resume sync failed` 로그가 연속으로 쌓이지 않는다.
- 홈 초기 로딩 화면에서 spinner가 여러 카드에 중복 표시되지 않는다.
- `fvm flutter analyze` 와 `fvm flutter test` 가 통과해야 한다.

## 남은 확인

- 실제 iOS simulator/device에서 `APP_ENV=local` no-override 실행 로그를 확인해야 최종 확정이다.
- dev/release backend 도메인은 DNS/배포 상태가 별도 운영 이슈이므로, 앱 fallback 수정과 별개로 배포 DNS를 점검해야 한다.
