# KBO Fans

KBO Fans는 KBO 프로야구 팬을 위한 모바일 앱입니다.  
iOS와 Android를 대상으로 하며, 오늘 경기 스코어보드와 마이팀 중심 경험을 빠르게 보여주는 것을 목표로 합니다.

## Overview

- App: Flutter + Dart
- Backend: Python FastAPI
- State management: Riverpod
- Navigation: go_router
- HTTP: dio
- Infra target: AWS
- Push: Firebase Cloud Messaging

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
 - 홈/잠금화면 위젯 연동 준비

현재 `app/`은 Flutter 프로젝트로 생성되어 있으며, 주요 화면 구조와 라우팅, 다크 테마, 일정/기록실/경기 상세가 포함되어 있습니다.  
`backend/`는 FastAPI 골격과 스코어보드/일정/박스스코어/라인업/순위, 팀 선수 기록 API가 준비되어 있습니다.

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
- Current release: `0.0.18`
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
- `web/` 플랫폼은 추가되어 있으며 기본 웹 실행은 release API health gate를 거치는 `./scripts/codex-run-web.sh` 로 실행합니다.
- Chrome 디버그 세션이 필요하면 `./scripts/codex-run-web-dev.sh` 또는 `flutter run -d chrome` 을 사용합니다.
- `macos/` 프로젝트는 아직 생성되지 않았습니다.
- 데이터 정확성 검증은 release API health gate를 통과한 경로에서만 유효합니다. 백엔드 검증 없이 화면 틀만 확인할 때는 `./scripts/codex-run-web-static.sh` 를 사용합니다.
- 예매 오픈 알림은 앱 로컬 예약 알림으로 동작합니다. 현재 예매처/오픈 시간은 홈팀 기본 정책 기준 추정값입니다.
- 위젯 갱신은 앱 foreground에서는 라이브 30초 / 예정 5분 기준으로 반영되며, 백그라운드 주기는 OS 정책에 따라 제한됩니다.

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

- `./scripts/codex-run-web.sh` 는 local backend 없이 release API health gate를 통과한 URL만 주입해 `flutter build web --release` 후 `http://localhost:7357` 에 정적 서버를 띄웁니다.
- `./scripts/codex-run-web-static.sh` 는 release API health gate 없이 `flutter build web --release` 후 `http://localhost:7357` 에 정적 서버를 띄우는 UI-only 프리뷰 경로입니다.
- `./scripts/codex-run-web-release.sh` 는 `./scripts/codex-run-web.sh` 와 같은 release API health-gated 웹 실행 래퍼입니다.
- `./scripts/codex-run-web-dev.sh` 는 Chrome 디버그 세션을 직접 띄우는 개발용 경로입니다.
- `./scripts/codex-run-ios.sh` 는 연결된 iPhone 실기기에서는 `--profile --dart-define=APP_ENV=local` 로 실행합니다. local backend가 LAN에서 접근 가능해야 하며, 스크립트가 `API_BASE_URL`을 주입합니다.
- `./scripts/codex-run-ios-debug.sh` 는 연결된 iPhone 실기기에서 `--debug` 로 실행합니다. 디버거 연결 상태에서 개발할 때만 쓰는 경로입니다.
- `./scripts/codex-run-ios-profile.sh` 는 위 동작을 명시적으로 호출하는 iPhone local profile 테스트용 래퍼입니다.
- `./scripts/codex-run-ios-local-release.sh` 는 연결된 iPhone 실기기에서 `--release --dart-define=APP_ENV=local --dart-define=PREFER_DIRECT_SCRAPE=true` 로 설치합니다. 아직 API 구현이 비어 있는 영역을 검증하기 위한 임시 direct-primary 경로이며, API 실패 후 fallback으로 전환되는 구조가 아닙니다.
- `./scripts/codex-run-ios-release.sh` 는 연결된 iPhone 실기기에서 `--release --dart-define=APP_ENV=release` 로 실행합니다. 실행 전 release API health gate가 `DNS / TLS / 핵심 API`를 확인하며, 실패하면 설치/실행을 중단합니다.
- `./scripts/codex-run.sh android-release`, `./scripts/codex-run.sh web`, `./scripts/codex-run.sh web-release` 는 local backend 없이 release API health gate를 통과한 URL만 앱에 주입합니다.
- 웹 `APP_ENV=local` 빌드는 명시적 `API_BASE_URL` override가 없으면 local backend 대신 운영 API를 기본값으로 사용합니다.
- 모바일 local native 모드도 기본은 API 경로입니다. backend가 켜져 있으면 iOS 실기기는 Mac LAN IP, iOS Simulator는 `localhost`, Android Emulator는 `10.0.2.2`, Android 실기기는 Mac LAN IP를 `API_BASE_URL`로 주입합니다.
- KBO direct scrape는 일반 fallback이 아니며, `APP_ENV=local` 네이티브 빌드에서 `API_BASE_URL` override 없이 `--dart-define=PREFER_DIRECT_SCRAPE=true` 를 명시한 임시 direct-primary 검증 경로에서만 사용합니다.
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
  - `release_api_base_url`: `APP_ENV=release` 빌드에 주입하고 health-check 할 API base URL. 기본값은 `https://api.kbofans.com/api`

Release health gate:

- `APP_ENV=release` 빌드는 빌드 전에 `scripts/release-api-health-check.sh` 를 실행합니다.
- 확인 항목:
  - API host DNS lookup
  - HTTPS TLS certificate validation
  - `GET /api/health`
  - `GET /api/scoreboard/home`
  - `GET /api/home`
  - `GET /api/schedule`
  - `GET /api/standings`
  - `GET /api/records/overview`
- 하나라도 실패하면 Android / iOS / Web release artifact 빌드를 중단합니다.
- production 도메인이 `api.kbofans.com` 이 아니면 workflow 입력 `release_api_base_url`, repo variable `RELEASE_API_BASE_URL`, secret `RELEASE_API_BASE_URL`, 또는 로컬 환경변수 `RELEASE_API_BASE_URL` 중 하나로 실제 API base URL을 명시해야 합니다.
- release API backend 자체 준비 항목은 `docs/RELEASE_API_BACKEND_TODO.md` 에 TODO로 분리했습니다.

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
- `local` 환경 빌드는 CI에서 컴파일은 가능하지만, 런타임 API 기준은 실행 환경별 local API 설정을 따릅니다. 웹은 운영 API, 네이티브는 `localhost`, `10.0.2.2`, 또는 LAN IP가 기본입니다. 단, `ios-local-release` / `codex-run-ios-local-release.sh` 는 API 미구현 영역 검증을 위해 `API_BASE_URL` override 없는 local native direct-primary 모드를 명시합니다.

권장 시크릿:

- Android: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`
- iOS: `IOS_CERTIFICATE_P12_BASE64`, `IOS_CERTIFICATE_PASSWORD`, `IOS_RUNNER_PROFILE_BASE64`, `IOS_WIDGET_PROFILE_BASE64`, `IOS_RUNNER_PROFILE_SPECIFIER`, `IOS_WIDGET_PROFILE_SPECIFIER`, `IOS_TEAM_ID`, 선택 `IOS_EXPORT_METHOD`

## Run The Backend

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
uvicorn kbo_fans_backend.main:app --reload
```

기본 확인 엔드포인트:

- `GET /api/health`

## Operational Notes

- 홈 스코어보드는 날짜 기준 `30초 TTL` 캐시를 사용합니다.
- 홈 스코어보드 로컬 cache는 `savedAt` envelope 기준으로 live 60초, scheduled/empty 5분, terminal 6시간 안의 payload만 먼저 렌더링합니다.
- 기록실 팀 데이터와 팀 스탯은 팀/시즌 기준 `5분 TTL` 캐시를 사용합니다.
- 순위와 기록실 요약/리더보드는 시즌별 번들 스냅샷 fallback을 사용하되, 다른 시즌 데이터를 빌려 보여주지 않는 exact-season-only 정책을 따릅니다. 현재 시즌 순위/기록실 요약 번들은 6시간 이내 생성본만 fallback으로 사용합니다.
- 현재 시즌 팀 선수/팀 스탯은 원천 조회를 우선하고, 원천 실패 시에도 6시간 이내 backend/app/device snapshot만 fallback으로 사용합니다.
- backend 현재 날짜 스코어보드와 현재 시즌/월 일정/순위/기록실 요약/리더보드는 원천 실패 시 6시간 이내 저장 snapshot만 fallback으로 사용합니다. 과거 날짜/시즌/월은 저장 snapshot 우선 정책을 유지합니다.
- 일반 API-backed 앱 모드에서는 현재 시즌 순위/기록실 API 실패를 앱 번들 데이터로 대체하지 않습니다. local backend 없이 원격 API가 죽어 있으면 release health gate 또는 화면 오류로 드러나게 둡니다.
- 지난 경기 결과, 선수 과거 기록, 지난 날짜 순위는 화면 요청 시 원천 크롤링보다 저장된 snapshot/정규화 레코드를 우선 사용합니다.
- 경기 종료 시 박스스코어/라인업/relay summary/시즌 누적 기록을 증분 저장합니다. 앱은 히스토리 데이터만 stale-while-revalidate 로 먼저 보여주고, 현재 날짜/시즌 데이터는 TTL 안의 캐시만 임시 표시합니다.
- 예정 경기는 YouTube 하이라이트 검색을 생략해 첫 로딩 외부 호출을 줄입니다.
- 개발 환경에서는 앱 Dev Console 에 `API`, `HOME loaded`, `RECORDS loaded` 타이밍 로그가 표시됩니다.
- 백엔드는 `backend/logs/backend.log`, `backend/logs/client_metrics.log` 에 느린 요청과 클라이언트 실측 지표를 저장합니다.
- 웹에서 API 실패 시 앱 내 `진단 보기` 화면으로 `health / scoreboard / schedule` 상태를 함께 확인할 수 있습니다.

## Design And Product Principles

- 앱을 열면 바로 야구 정보를 보여준다
- 마이팀 중심 경험을 우선한다
- 다크 테마 기반 스포츠 앱 톤을 유지한다
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
