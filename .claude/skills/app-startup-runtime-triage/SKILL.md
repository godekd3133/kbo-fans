---
name: app-startup-runtime-triage
description: Use when startup shows a long white screen, Dev Console logs are noisy, local API requests fail by platform, or Firebase local warnings need to be separated from real runtime issues.
---

# App Startup Runtime Triage

## Use this when
- 앱 시작 직후 흰 화면이 길게 보인다.
- local/web/android 환경에서 API 연결 실패와 로그 노이즈가 섞여 보인다.
- Dev Console 로그가 너무 많아 성공/실패 구분이 어렵다.
- Firebase local 경고를 실제 장애와 분리해야 한다.

## Primary files
- `app/lib/main.dart`
- `app/lib/core/config/app_config.dart`
- `app/lib/data/api/api_client.dart`
- `app/lib/core/widgets/dev_console.dart`
- `app/lib/services/push_notification_service.dart`
- `app/web/index.html`

## Workflow
1. `runApp()` 이전 blocking async 초기화가 있는지 확인한다.
2. 필요하면 부트 스플래시를 먼저 보여주고, 설정/온보딩 상태는 첫 프레임 이후에 읽는다.
3. local API base URL을 플랫폼별로 점검한다.
   - Android emulator: `10.0.2.2`
   - iOS simulator / web: `localhost`
4. Dev Console 로그를 `API OK / API FAIL` 로 분리한다.
5. local/test 환경에서는 noisy prefetch와 metrics 전송을 줄인다.
6. Firebase local 미설정은 실제 장애처럼 보이지 않게 `info` 수준으로 낮출지 검토한다.
7. `fvm flutter analyze --no-fatal-infos` 와 관련 widget test로 검증한다.

## Repository-specific insights
- 흰 화면 체감은 실제 네트워크보다 `runApp 이전 대기`와 웹 기본 흰 배경 영향이 더 크다.
- widget test에서 홈 화면을 직접 띄우면 provider 요청 로그가 섞일 수 있다.
- local Android에서는 `localhost` 대신 `10.0.2.2` 를 기본으로 보는 편이 안전하다.
