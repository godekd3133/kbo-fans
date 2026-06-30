# KBO Fans

KBO Fans는 KBO 프로야구 팬을 위한 모바일 앱입니다.  
iOS와 Android를 대상으로 하며, 오늘 경기 스코어보드와 마이팀 중심 경험을 빠르게 보여주는 것을 목표로 합니다.

## Overview

- App: Flutter + Dart
- Backend: active Python FastAPI service for API-backed data, snapshots, push, and Live Activity / Dynamic Island sync
- State management: Riverpod
- Navigation: go_router
- HTTP: dio
- Infra target: AWS ECS/Fargate for backend API service and sync worker
- Push: Firebase Cloud Messaging + APNs ActivityKit Live Activity push

## Current Scope

MVP Phase 1 기준 핵심 범위:

- 오늘 경기 스코어보드
- 경기 상세
  - 스코어
  - 문자중계
  - 박스스코어
  - 라인업
  - KBO 공식 + 유튜브 하이라이트 연결
- 기록실
  - 팀 엔트리
  - 엔트리 제외 / 부상 이탈
  - 선수 프로필 / 최근 기록
  - 투수 / 야수 탭 분리
  - 타율 / OPS / ERA / WHIP 정렬
- 마이팀 선택
- 일정
  - 경기별 예매처 / 예매 오픈 시간 표시
  - 경기 상세에서 예매처 바로가기 / 예매 오픈 알림
- 순위
- 푸시 알림
- 홈/잠금화면 위젯, iOS Live Activity / Dynamic Island 연동

현재 `app/`은 Flutter 프로젝트로 생성되어 있으며, 주요 화면 구조와 라우팅, 라이트/다크/시스템 화면 모드, 일정/기록실/경기 상세가 포함되어 있습니다.
`backend/`는 FastAPI API service, KBO crawler/service layer, snapshot tooling, push notification, Live Activity / Dynamic Island sync worker를 포함합니다.

## Repository Structure

```text
kbo_fans/
├── README.md
├── CHANGELOG.md
├── AGENTS.md
├── CLAUDE.md
├── docs/
│   ├── APP_SPEC.md
│   ├── FIGMA_PROMPT.md
│   ├── PLANNING.md
│   ├── TASK_DIVISION.md
│   └── WORKLOG.md
├── app/
└── backend/
```

## Documentation Priority

- Repository working rules: `AGENTS.md`
- High-level product/project context: `CLAUDE.md`
- Product goals and MVP scope: `docs/PLANNING.md`
- Screen behavior and API contracts: `docs/APP_SPEC.md`
- Visual system and Figma composition: `docs/FIGMA_PROMPT.md`
- Latest decisions and work history: `docs/WORKLOG.md`
- External-facing project summary and setup guide: `README.md`
- User-visible release history: `CHANGELOG.md`
- Versioning and release policy: `docs/VERSIONING.md`

문서 간 충돌 시 최신 결정은 `CLAUDE.md`, `docs/WORKLOG.md`, 실제 코드 기준으로 판단합니다.

## Versioning

- App version format: `MAJOR.MINOR.PATCH+BUILD` in `app/pubspec.yaml`
- Release tag format: `MAJOR.MINOR.PATCH`
- Current release line: `0.0.x`
- Current release: `0.0.33`
- Preview suffixes are not used. Do not create `*-preview*` tags or prereleases unless this policy is explicitly changed.
- Every release/version change must update `CHANGELOG.md`, `app/assets/bootstrap/patch_notes.md`, GitHub Release notes, and `docs/WORKLOG.md`.

자세한 정책은 `docs/VERSIONING.md` 를 기준으로 합니다.

## Run The App

Flutter SDK가 설치되어 있다는 전제입니다.

```bash
cd app
flutter pub get
flutter run
```

플랫폼 지정 예시:

```bash
flutter run -d ios
flutter run -d android
```

참고:

- 현재 저장소에는 `ios/`와 `android/` 프로젝트가 모두 포함되어 있습니다.
- `web/` 플랫폼은 추가되어 있으며 기본 웹 실행은 direct preview/data mode의 `./scripts/codex-run-web.sh` 로 실행합니다.
- Chrome 디버그 세션이 필요하면 `./scripts/codex-run-web-dev.sh` 또는 `flutter run -d chrome` 을 사용합니다.
- `macos/` 프로젝트는 아직 생성되지 않았습니다.
- 데이터 정확성 검증은 기본적으로 FastAPI API/service/snapshot 경로에서 수행합니다. direct KBO mode는 `USE_BACKEND_API=false`를 명시한 parser/debug 세션에서만 사용합니다.
- 예매 오픈 알림은 앱 로컬 예약 알림으로 동작합니다. 현재 예매처/오픈 시간은 홈팀 기본 정책 기준 추정값입니다.
- 위젯 갱신은 앱 foreground에서는 라이브 8초 / 예정 5분 기준으로 반영되며, 백그라운드 주기는 OS 정책에 따라 제한됩니다.
- 앱이 꺼진 뒤에도 일반 푸시와 iOS Live Activity를 시작/갱신하려면 운영 백엔드가 KBO 상태를 polling하고 FCM/APNs로 발송해야 합니다. Firebase는 일반 푸시 전달 채널이고, Dynamic Island 시작/갱신은 ActivityKit 전용 APNs liveactivity push-to-start/update token을 사용합니다. 같은 scheduler가 경기 시작 10분 전 Live Activity start, 점수판 diff 기반 득점/역전/타석/종료와 relay diff 기반 안타/홈런 FCM topic push도 발행합니다.

Codex 앱에서 바로 실행할 수 있도록 공용 스크립트도 추가했습니다.

```bash
./scripts/codex-run.sh ios
./scripts/codex-run.sh android
./scripts/codex-run.sh android-release
./scripts/codex-run.sh web
./scripts/codex-run.sh web-dev
./scripts/codex-run.sh web-static
./scripts/codex-run.sh web-release
./scripts/codex-run.sh backend
./scripts/codex-run.sh push-live-preflight --app-only
./scripts/codex-run.sh push-readiness
./scripts/codex-run.sh aws-push-secrets
./scripts/codex-run.sh aws-push-task-defs
./scripts/codex-run.sh aws-push-deploy-check --skip-aws
./scripts/codex-run.sh aws-push-image --dry-run
./scripts/codex-run.sh aws-push-cloudformation --dry-run
./scripts/codex-run.sh aws-push-stack-outputs
./scripts/codex-run.sh aws-push-demo-deploy --dry-run
./scripts/codex-run.sh aws-push-tooling
./scripts/codex-run.sh aws-github-oidc-role --dry-run
./scripts/codex-run.sh push-demo-env-bootstrap --repo godekd3133/kbo-fans --force
./scripts/codex-run.sh push-demo-setup-status --env-file /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans
./scripts/codex-run.sh push-demo-audit --env-file /path/to/kbo-fans-aws.env
./scripts/codex-run.sh github-push-secrets --env-file /path/to/kbo-fans-aws.env
./scripts/codex-run.sh github-push-demo-run --dry-run true
./scripts/codex-run.sh doctor
```

권장 등록 방식:

- iOS 실행 액션: `./scripts/codex-run-ios.sh`
- iOS debug 실행 액션: `./scripts/codex-run-ios-debug.sh`
- iOS local profile 실행 액션: `./scripts/codex-run-ios-profile.sh`
- iOS local release-mode 실행 액션: `./scripts/codex-run-ios-local-release.sh`
- iOS production release 실행 액션: `./scripts/codex-run-ios-release.sh`
- Android 실행 액션: `./scripts/codex-run-android.sh`
- Android release 실행 액션: `./scripts/codex-run-android-release.sh`
- Web 실행 액션: `./scripts/codex-run-web.sh`
- 정적 웹 프리뷰 실행 액션: `./scripts/codex-run-web-static.sh`
- Web release 실행 액션: `./scripts/codex-run-web-release.sh`
- 웹 Chrome 디버그 실행 액션: `./scripts/codex-run-web-dev.sh`
- Backend 실행 액션: `./scripts/codex-run.sh backend`
- Push / Live Activity 배포 전 로컬 전제조건 점검 액션: `./scripts/codex-run.sh push-live-preflight --app-only`
- Push readiness 점검 액션: `./scripts/codex-run.sh push-readiness`
- AWS push secret 업로드 액션: `./scripts/codex-run.sh aws-push-secrets`
- AWS push task definition 렌더링 액션: `./scripts/codex-run.sh aws-push-task-defs`
- AWS push 배포 사전점검 액션: `./scripts/codex-run.sh aws-push-deploy-check`
- AWS push backend image ECR push 액션: `./scripts/codex-run.sh aws-push-image --dry-run`
- AWS push CloudFormation dry-run/deploy 액션: `./scripts/codex-run.sh aws-push-cloudformation --dry-run`
- AWS push stack output env 추출 액션: `./scripts/codex-run.sh aws-push-stack-outputs`
- AWS push 통합 배포 dry-run/deploy 액션: `./scripts/codex-run.sh aws-push-demo-deploy --dry-run`
- AWS/Docker 로컬 도구 점검 액션: `./scripts/codex-run.sh aws-push-tooling`
- GitHub Actions push deploy secrets/variables 점검 또는 업로드 액션: `./scripts/codex-run.sh github-push-secrets --env-file /path/to/kbo-fans-aws.env`
- GitHub Actions push deploy workflow 실행 액션: `./scripts/codex-run.sh github-push-demo-run --dry-run true`
- GitHub Actions 원격 테스트 푸시 실행 액션: `./scripts/codex-run.sh github-push-test-notification-run --topic baseball_info_ALL --watch`
- 환경 점검 액션: `./scripts/codex-run.sh doctor`

플랫폼별 실행 환경을 분리한 Codex 액션용 래퍼:

```bash
./scripts/codex-run-ios.sh
./scripts/codex-run-ios-debug.sh
./scripts/codex-run-ios-profile.sh
./scripts/codex-run-ios-local-release.sh
./scripts/codex-run-ios-release.sh
./scripts/codex-run-android.sh
./scripts/codex-run-android-release.sh
./scripts/codex-run-web.sh
./scripts/codex-run-web-static.sh
./scripts/codex-run-web-release.sh
./scripts/codex-run-web-dev.sh
```

참고:

- `./scripts/codex-run-web.sh` 는 backend API mode로 `flutter build web --release` 후 `http://localhost:7357` 에 정적 서버를 띄웁니다.
- `./scripts/codex-run-web-static.sh` 도 backend API mode로 `flutter build web --release` 후 `http://localhost:7357` 에 정적 서버를 띄우는 정적 프리뷰 경로입니다.
- `./scripts/codex-run-web-release.sh` 는 운영 `API_BASE_URL`을 포함한 backend API release 웹 실행 래퍼입니다.
- `./scripts/codex-run-web-dev.sh` 는 Chrome 디버그 세션을 직접 띄우는 개발용 경로입니다.
- `./scripts/codex-run-ios.sh` 는 연결된 iPhone 실기기에서는 LAN 접근 가능한 local backend API를 찾아 `USE_BACKEND_API=true`와 `API_BASE_URL`을 주입합니다.
- `./scripts/codex-run-ios-debug.sh` 는 연결된 iPhone 실기기에서 `--debug` 로 실행합니다. 디버거 연결 상태에서 개발할 때만 쓰는 경로입니다.
- `./scripts/codex-run-ios-profile.sh` 는 위 동작을 명시적으로 호출하는 iPhone local profile 테스트용 래퍼입니다.
- `./scripts/codex-run-ios-local-release.sh` 는 연결된 iPhone 실기기에서 release mode로 local backend API를 사용합니다.
- `./scripts/codex-run-ios-release.sh` 는 연결된 iPhone 실기기에서 운영 backend API를 사용하고, `RELEASE_API_BASE_URL` 또는 기본 `https://api.kbofans.com/api`를 `API_BASE_URL`로 주입합니다.
- `./scripts/codex-run-android-release.sh` 도 운영 backend API와 같은 `API_BASE_URL`을 사용합니다.
- `./scripts/codex-run.sh android-release`, `./scripts/codex-run.sh web`, `./scripts/codex-run.sh web-release` 는 backend API 경로로 실행합니다.
- 웹 `APP_ENV=local` / `APP_ENV=release` 빌드는 backend API를 기본값으로 사용합니다.
- KBO direct scrape는 일반 fallback이나 기본 primary source가 아니라 `USE_BACKEND_API=false`를 명시한 parser/debug 전용 경로입니다.
- `./scripts/codex-run-android.sh` 는 Android Studio JBR(Java 17), Android SDK, AVD 부팅, `APP_ENV=local` 기준까지 포함한 Codex용 안드로이드 실행 경로입니다.
- 안드로이드 실행 환경 메모는 `docs/CODEX_ANDROID_ENV.md` 를 참고합니다.

## GitHub Actions Build Artifacts

GitHub Actions 에서 앱 빌드본을 바로 뽑을 수 있도록 수동 실행 워크플로우를 추가했습니다.

- 워크플로우: `.github/workflows/app-build-artifacts.yml`
- 실행 위치: GitHub `Actions > App Build Artifacts > Run workflow`
- 선택 입력:
  - `platform`: `android`, `ios`, `web`, `all`
  - `app_environment`: `local`, `dev`, `release`, `all`
  - `build_signed_ios_ipa`: iOS 서명 시크릿이 준비된 경우에만 `true`

Release artifact data modes:

- Android / iOS / Web artifact는 backend API mode로 빌드합니다.
- `APP_ENV=release` artifact는 화면 provider와 push / Live Activity token 등록 모두를 위해 `release_api_base_url` workflow input, `RELEASE_API_BASE_URL` variable/secret, 또는 기본 `https://api.kbofans.com/api`를 `API_BASE_URL`로 함께 주입합니다.
- backend API 화면 데이터와 push / Live Activity 운영 검증은 backend health/readiness를 함께 확인합니다.

생성 아티팩트:

- Android
  - `android-<env>-apk`
  - `android-<env>-aab`
- iOS
  - `ios-<env>-simulator-app`
  - `ios-<env>-ipa` (`build_signed_ios_ipa=true` 이고 시크릿이 있을 때만)
- Web
  - `web-<env>`

주의:

- Android 는 서명 시크릿이 없으면 현재 Gradle 설정대로 debug signing fallback 으로 release 빌드를 만듭니다.
- iOS 는 기본으로 simulator용 unsigned 앱만 만들고, 실제 IPA 는 인증서/프로비저닝 시크릿이 있어야 합니다.
- `local` / `dev` / `release` 환경 빌드는 CI에서 backend API artifact로 컴파일합니다. backend health/readiness는 화면 데이터, push, Live Activity 운영 검증의 완료 조건입니다.

권장 시크릿:

- Android: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`
- iOS: `IOS_CERTIFICATE_P12_BASE64`, `IOS_CERTIFICATE_PASSWORD`, `IOS_RUNNER_PROFILE_BASE64`, `IOS_WIDGET_PROFILE_BASE64`, `IOS_RUNNER_PROFILE_SPECIFIER`, `IOS_WIDGET_PROFILE_SPECIFIER`, `IOS_TEAM_ID`, 선택 `IOS_EXPORT_METHOD`

## Run The Backend

Codex 실행 액션 기준:

```bash
./scripts/codex-run.sh backend
```

이 명령은 iPhone 실기기에서도 Mac LAN IP로 접근할 수 있도록 기본 `0.0.0.0:8000`에 바인딩합니다. localhost 전용으로만 띄울 때는 `BACKEND_HOST=127.0.0.1 ./scripts/codex-run.sh backend`를 사용합니다.

수동 실행:

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
uvicorn kbo_fans_backend.main:app --host 0.0.0.0 --port 8000 --reload
```

기본 확인 엔드포인트:

- `GET /api/health`

원격 푸시 / Live Activity 운영 설정:

- `FIREBASE_SERVICE_ACCOUNT_JSON` 또는 `FIREBASE_SERVICE_ACCOUNT_PATH`, `FIREBASE_PROJECT_ID`: FCM 일반 푸시 발송
- `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_AUTH_KEY_P8` 또는 `APNS_AUTH_KEY_PATH`, `APNS_BUNDLE_ID`: iOS Live Activity APNs 발송
- `APNS_USE_SANDBOX=false`: TestFlight/운영 배포용 APNs production endpoint 사용
- `PUSH_SYNC_SECRET`: scoreboard 기반 Live Activity sync trigger 보호용 secret
- `KBO_RELAY_USER_ID`, `KBO_RELAY_PASSWORD`: KBO LiveText 문자중계 crawler 로그인용 secret
- `POST /api/push/baseball-info` 또는 `python -m kbo_fans_backend.scheduler.baseball_info --dry-run`: 월요일 주간 체크, 경기일 체크, 비경기일 브리프, 기록실 확인 같은 야구 정보 push의 title/body/topic을 실제 Firebase 발송 전에 미리 확인
- `python -m kbo_fans_backend.scheduler.baseball_info --smart-daily --dry-run`: 해당 날짜 scoreboard를 기준으로 팀별 `game_day` / `records_check` / `rival_watch` / `off_day` 브리프 계획을 자동 생성해 발송 전에 확인
- `python -m kbo_fans_backend.scheduler.baseball_info --smart-daily --now-time 16:00 --dry-run`: 경기 시작 3시간 이내 팀은 `lineup_day`로 자동 전환해 라인업/예매/중계 진입을 유도
- `./scripts/push-live-preflight.sh --env-file /path/to/kbo-fans-aws.env --aws`: 배포 전 앱 Firebase 설정, iOS APNs/Live Activity capability, release `API_BASE_URL` token-registration handoff, backend secret env, AWS env 형태를 secret 값 노출 없이 점검. 필수 배포값이 obvious placeholder로 남아 있으면 실패합니다.
- `GET /api/push/config-status`: Firebase/APNs/registry/scheduler 설정 누락을 secret 값 노출 없이 점검
- `./scripts/push-readiness-check.sh https://api.kbofans.com/api`: 배포 후 `/health`, push config readiness, scheduler heartbeat 최신성을 한 번에 점검. 기본적으로 `scheduler.lastSyncAt`이 180초 이내여야 통과하며, 설정값만 확인할 때는 `PUSH_READINESS_REQUIRE_SCHEDULER=false`로 우회합니다. `PUSH_READINESS_RUN_SYNC=true`로 one-shot sync를 실행하면 sync 후 config-status를 다시 읽어 heartbeat를 확인합니다. 날짜를 생략하면 backend의 `Asia/Seoul` KBO 경기일 기본값을 사용하고, 재현용 날짜가 필요할 때만 `PUSH_READINESS_DATE=YYYY-MM-DD`를 지정합니다.
- `./scripts/aws-push-secrets.sh`: Firebase Admin JSON / APNs `.p8` / sync secret / KBO relay credential을 AWS Secrets Manager에 생성 또는 갱신하고 `SECRET_ARN_*` export를 생성
- `./scripts/aws-push-image.sh`: backend Docker image를 ECR에 build/tag/push하고 `CONTAINER_IMAGE_URI` export를 생성
- `./scripts/aws-push-task-definitions.sh`: AWS secret ARN / role ARN / ECR / EFS 값을 환경변수로 받아 ECS task definition JSON과 execution-role secret-read IAM policy를 `outputs/aws/ecs-fargate/`에 렌더링
- `./scripts/aws-push-deploy-check.sh`: 렌더링 전후 env/JSON과 AWS credential, secret, IAM role, ECR, EFS, CloudWatch log group 존재 여부를 점검
- `./scripts/aws-push-cloudformation.sh`: ALB, ECS Fargate API service, sync worker, EFS, IAM, CloudWatch log group을 CloudFormation stack으로 생성. 도메인/ACM 전 임시 backend smoke는 `ENABLE_HTTPS=false`로 HTTP ALB URL을 출력할 수 있지만, iPhone release token registration은 `ENABLE_HTTPS=true`와 `API_DOMAIN_NAME` / `ACM_CERTIFICATE_ARN` 기준으로 되돌립니다.
- `./scripts/aws-push-stack-outputs.sh`: CloudFormation output의 `ApiBaseUrl`을 `RELEASE_API_BASE_URL` / `API_BASE_URL` env로 추출
- `./scripts/aws-push-demo-deploy.sh`: secret 업로드, ECR image push, CloudFormation deploy, output env 추출, readiness를 순서대로 실행
- `./scripts/aws-push-tooling-check.sh`: 로컬 AWS CLI credential과 Docker daemon 상태를 확인. 로컬 도구가 없으면 GitHub Actions `Push Demo Deploy` workflow로 같은 배포 파이프라인을 실행할 수 있습니다.
- `./scripts/aws-github-oidc-role.sh --env-file /path/to/kbo-fans-aws.env --repo godekd3133/kbo-fans --update-env-file`: GitHub Actions가 장기 AWS access key 없이 배포할 수 있도록 `AWS_ROLE_TO_ASSUME` OIDC role을 만들고 env 파일에 반영합니다.
- `infra/aws/ecs-fargate/deploy.env.example`: preflight, 로컬 AWS 배포, GitHub Actions secrets/variables 업로드에 같이 쓰는 env checklist입니다. 각 값의 발급 위치와 업로드 대상이 주석으로 들어 있습니다. 로컬 untracked 파일로 복사한 뒤 실제 값을 채웁니다.
- `./scripts/push-demo-env-bootstrap.sh --output /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans --force`: 로컬 Firebase client config를 감지해 push demo env 초안을 만들고, Apple/APNs/AWS placeholder와 각 값의 발급 위치/업로드 대상 주석을 남깁니다. 생성 파일은 secret이 들어갈 수 있으므로 커밋하지 않습니다.
- `./scripts/push-demo-setup-status.sh --env-file /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans`: env 초안 생성, OIDC role dry-run, readiness audit, 다음 명령 안내를 한 번에 실행합니다. 배포나 workflow dispatch는 하지 않습니다.
- setup status 출력의 `Required Values` 섹션은 Firebase/Apple/AWS/GitHub에서 가져올 값, env 파일 변수명, GitHub secret/variable 업로드 대상, AWS runtime 주입 위치를 한 번에 보여줍니다.
- `./scripts/push-demo-readiness-audit.sh --env-file /path/to/kbo-fans-aws.env`: 앱 파일, env checklist, 로컬 AWS/Docker tooling, GitHub Actions workflow/secrets/variables 상태를 secret 값 없이 한 번에 점검하고, 누락된 Firebase/APNs/AWS/GitHub 설정을 `next_config[...]`로 안내합니다.
- `./scripts/github-push-secrets.sh --env-file /path/to/kbo-fans-aws.env`: GitHub Actions `Push Demo Deploy`에 필요한 secrets/variables를 dry-run으로 확인. `--apply`를 붙이면 `gh secret set` / `gh variable set`으로 실제 업로드합니다. obvious placeholder 값은 업로드 전에 실패합니다.
- `./scripts/github-push-demo-run.sh --dry-run true`: GitHub Actions `Push Demo Deploy` workflow를 dispatch합니다. workflow 파일이 아직 원격 default branch에 없으면 커밋/푸시 필요 상태를 안내하고, 필수 secrets/variables가 누락되면 workflow run 생성 전에 목록을 출력하고 중단합니다.
- `./scripts/github-push-test-notification-run.sh --topic baseball_info_ALL --watch`: GitHub Actions `Push Test Notification` workflow를 dispatch해 `PUSH_SYNC_SECRET`을 로컬에 두지 않고 원격 테스트 푸시를 보냅니다. FCM token 대상은 `--token <fcm-token>`으로 지정하며, 스크립트는 secret/token 값을 출력하지 않습니다.
- `POST /api/push/live-activity/start-token/register`: iOS 17.2+ 앱이 ActivityKit push-to-start token과 `installationId`를 등록합니다. 운영 scheduler는 같은 설치 id의 push registration을 기준으로 마이팀/선택 경기가 KST `startTime` 10분 전 window에 들어오거나 LIVE가 되면 APNs `event=start`로 앱을 열지 않아도 Live Activity / Dynamic Island를 시작합니다.
- `POST /api/push/live-activity/sync-scoreboard`: 운영 scheduler가 5초 간격으로 호출하는 scoreboard/relay sync trigger. 시작 10분 전 예정 경기에는 APNs start를, 등록된 Live Activity에는 APNs update/end를 보내고, scoreboard diff 기반 시작 임박/득점/역전/타석/종료/이닝 교대와 relay diff 기반 안타/홈런은 FCM topic push로 발행합니다. visible push copy는 짧은 사건명 제목과 `현재 1사 1,2루` 상황, `스코어 4:3` 점수 형식을 사용합니다.
- AWS ECS/Fargate 시연 배포 템플릿은 `infra/aws/ecs-fargate/`와 `infra/aws/cloudformation/`에 있습니다. 권장 구조는 FastAPI API service 1개와 `python -m kbo_fans_backend.scheduler.live_activity_sync_loop` sync worker service 1개입니다.

GitHub Actions 배포:

- Workflow: `.github/workflows/push-demo-deploy.yml` (`Push Demo Deploy`)
- Required secrets/vars: `AWS_ROLE_TO_ASSUME` 또는 `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `IOS_GOOGLE_SERVICE_INFO_PLIST`, `ANDROID_GOOGLE_SERVICES_JSON`, `FIREBASE_PROJECT_ID`, `FIREBASE_SERVICE_ACCOUNT_JSON`, `APNS_AUTH_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `PUSH_SYNC_SECRET`, `KBO_RELAY_USER_ID`, `KBO_RELAY_PASSWORD`, `ECR_REPOSITORY_URI`, `VPC_ID`, `PUBLIC_SUBNET_A_ID`, `PUBLIC_SUBNET_B_ID`. `ENABLE_HTTPS`는 기본 `true`이며, `ACM_CERTIFICATE_ARN`은 `ENABLE_HTTPS=true`일 때 필수입니다. `API_DOMAIN_NAME`은 ACM 인증서와 일치하는 커스텀 도메인이 있을 때 설정합니다.
- `dry_run=true`는 AWS/Docker deploy call 없이 repo script와 secret/env 형태를 검증합니다.
- `dry_run=false`는 secret 업로드, ECR image push, CloudFormation deploy, stack output export, readiness를 실행합니다.
- AWS 인증은 `AWS_ROLE_TO_ASSUME` OIDC role을 우선 사용합니다. `./scripts/aws-github-oidc-role.sh --env-file /path/to/kbo-fans-aws.env --repo godekd3133/kbo-fans --update-env-file`는 GitHub OIDC provider와 main branch trust policy를 준비하고 env 파일에 role ARN을 씁니다.
- 전체 흐름이 헷갈릴 때는 먼저 `./scripts/push-demo-setup-status.sh --env-file /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans`를 실행합니다. 이 명령은 배포하지 않고 현재 막힌 설정 항목과 다음 명령만 보여줍니다.
- 같은 출력의 `Required Values` 섹션에서 Firebase client 파일, Firebase Admin JSON, Apple APNs `.p8`, AWS ECR/VPC/Subnet/HTTPS mode, GitHub OIDC role, release `API_BASE_URL`을 어디서 가져와 어디에 넣는지 확인합니다.
- 로컬 env 파일에서 GitHub 입력값을 올릴 때는 먼저 `./scripts/github-push-secrets.sh --env-file /path/to/kbo-fans-aws.env`로 dry-run을 보고, 이름이 맞으면 `--apply`를 붙입니다.
- 로컬 env 파일을 처음 만들 때는 `./scripts/push-demo-env-bootstrap.sh --output /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans --force`로 Firebase project id와 client config 경로가 채워진 초안을 만든 뒤, 파일 안 주석을 따라 Apple/AWS placeholder를 바꿉니다.
- 전체 준비 상태는 `./scripts/push-demo-readiness-audit.sh --env-file /path/to/kbo-fans-aws.env --repo godekd3133/kbo-fans`로 점검합니다. 이 명령은 배포나 workflow dispatch를 실행하지 않습니다.
- workflow 파일을 커밋/푸시한 뒤 `./scripts/github-push-demo-run.sh --dry-run true --watch`로 dry-run을 실행하고, 통과하면 `./scripts/github-push-demo-run.sh --dry-run false --watch`로 실제 배포를 실행합니다. 이 CLI는 dispatch 전 GitHub secrets/variables 존재를 확인합니다. 이미 별도 확인을 끝낸 경우에만 `--skip-config-check`로 우회합니다.

## Operational Notes

- 앱 API cache는 성공 응답 저장과 히스토리 cached-first 조회용입니다. `allowCacheOnFailure` 기본값은 false 이며, 현재 날짜/월/시즌 경로는 API 실패 시 이 cache를 정상 데이터처럼 읽지 않습니다.
- 홈 스코어보드는 오늘 데이터 로딩 중 별도 로컬 cache를 먼저 렌더링하지 않습니다. 최신 API 응답 또는 명시적 오류 상태를 기준으로 화면을 갱신합니다.
- 홈 secondary aggregate는 scoreboard 첫 데이터 프레임 이후에만 구독해 첫 화면 렌더 전에 `/home` 부가 API가 시작되지 않도록 합니다.
- 홈 마이팀 브리프의 팀 타율/ERA는 scoreboard 첫 데이터 프레임 뒤 팀 지표 provider(`/api/team/{teamId}/stats`)로 먼저 보강하고, 팀 홈런 1위와 뜨는 선수는 선수 provider(`/api/team/{teamId}/players`)가 도착하면 채웁니다. `/home` aggregate에 전 팀 선수 기록을 싣지 않습니다.
- 홈 자동 refresh timer는 현재 scoreboard signature가 바뀔 때만 재스케줄해 unrelated rebuild가 live polling을 뒤로 밀지 않도록 합니다.
- backend `/scoreboard/home`과 `/scoreboard/compact`는 홈/위젯 표면용 schedule + main list 요약 경로입니다. 경기별 상세 스코어보드 크롤링은 full scoreboard 또는 game detail 진입 때만 수행합니다.
- backend current data routes는 `api/runtime_services.py`의 공용 service singleton을 공유해 `/scoreboard/home`, `/home`, game detail 계열이 같은 TTL cache를 재사용합니다.
- LIVE 요약 스코어보드는 KBO main list의 유효한 득점을 schedule/detail fallback의 0점보다 우선합니다. 진행 중 경기의 최신 score를 fallback 0:0이 덮지 않아야 합니다.
- 앱은 요약 스코어보드의 미수집 H/E/B `null` 값을 실제 0 기록처럼 표시하지 않습니다.
- 기록실 팀 데이터와 팀 스탯도 현재 시즌에서는 fresh-first/fail-visible 기준을 따르고, 과거 시즌 조회에서만 cached-first 성격을 유지합니다.
- 순위와 기록실 요약/리더보드 번들 스냅샷은 exact-season-only 정책을 따릅니다. 명시적 API-backed current 경로에서는 현재 시즌 API 실패를 번들 snapshot으로 정상 처리하지 않습니다.
- 기록실 요약/리더보드 API cache와 기기 snapshot은 핵심 리더보드가 1위부터 시작하는 payload만 재사용하거나 저장합니다.
- backend 기록실 요약/리더보드는 KBO 응답 row 순서가 흔들려도 API 응답 전에 rank 오름차순으로 정규화합니다.
- 현재 시즌 팀 선수/팀 스탯/선수 상세는 원천 조회를 우선하고, 원천 실패 시 backend/app/device snapshot으로 정상 상태를 만들지 않습니다.
- backend 현재 스코어보드, 일정, 순위, 기록실 요약, 리더보드는 원천 실패 시 저장 snapshot으로 정상 상태를 만들지 않습니다. 과거 날짜/시즌/월은 저장 snapshot 우선 정책을 유지합니다.
- backend `/home` aggregate는 현재/미래 날짜에서 schedule/standings/records overview 하위 호출 실패를 빈 섹션으로 숨기지 않습니다. 과거 날짜만 부분 fallback을 허용합니다.
- 현재/진행 예정 경기 상세의 박스스코어, 라인업, LIVE 문자중계는 원천 실패를 과거 snapshot이나 요약 payload로 숨기지 않습니다. 박스스코어의 adjacent game id fallback도 과거 경기에서만 허용하고, current/live 경기는 비어 있으면 `officialAvailable=false` 상태로 노출합니다.
- 명시적 API-backed 앱 모드에서는 현재 시즌 순위/기록실 API 실패를 앱 번들 데이터로 대체하지 않습니다.
- 현재 날짜/월/시즌 원천 요청은 실패 시 TTL 안의 로컬 cache도 정상 데이터처럼 재사용하지 않습니다. 과거 날짜/시즌/월 조회만 cached-first 또는 snapshot fallback을 유지합니다.
- 앱 전역 Provider retry는 비활성화되어 원천 실패가 반복 재시도 뒤에 숨지 않고 화면 오류 상태와 Dev Console에 드러나야 합니다.
- 지난 경기 결과, 선수 과거 기록, 지난 날짜 순위는 화면 요청 시 원천 크롤링보다 저장된 snapshot/정규화 레코드를 우선 사용합니다.
- 경기 종료 시 박스스코어/라인업/relay summary/시즌 누적 기록을 증분 저장합니다. 앱은 히스토리 데이터만 stale-while-revalidate 로 먼저 보여주고, 현재 날짜/시즌 데이터는 direct source 최신 응답을 우선하며 실패 시 로컬 cache로 정상 상태를 만들지 않습니다.
- 예정 경기는 YouTube 하이라이트 검색을 생략해 첫 로딩 외부 호출을 줄입니다.
- 개발 환경에서는 앱 Dev Console 에 `API`, `HOME loaded`, `RECORDS loaded` 타이밍 로그가 표시됩니다.
- backend-backed mode에서는 `backend/logs/backend.log`, `backend/logs/client_metrics.log` 에 느린 요청과 클라이언트 실측 지표를 저장합니다.
- 웹에서 API 실패 시 앱 내 `진단 보기` 화면으로 `health / scoreboard / schedule / push` 상태를 함께 확인할 수 있습니다.

## Design And Product Principles

- 앱을 열면 바로 야구 정보를 보여준다
- 마이팀 중심 경험을 우선한다
- 다크 테마 기반 스포츠 앱 톤을 유지하되, 설정에서 라이트/다크/시스템 화면 모드를 선택할 수 있게 한다
- 과도한 포털형 정보 나열보다 빠른 확인 경험을 우선한다

## Notes

- KBO 공식 소스 크롤링에 의존하므로 파서와 수집 경로는 변경에 취약할 수 있습니다.
- 라이브 경기 데이터는 적응형 폴링 전략을 전제로 설계합니다.
- 상세 설계와 상태 코드는 `docs/APP_SPEC.md`를 우선 참고합니다.

## Maintenance Rule

이 저장소에서 의미 있는 기능 변경, 문서 기준 변경, 실행 방법 변경이 발생하면 아래 문서들을 함께 갱신합니다.

- `README.md`
- `CHANGELOG.md`
- `docs/WORKLOG.md`
- 필요 시 `AGENTS.md`, `CLAUDE.md`, `docs/APP_SPEC.md`, `docs/FIGMA_PROMPT.md`
