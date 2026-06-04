# 작업 이력 (Work Log)

---

## 2026-06-04: Push setup 보관 메모 현재성 보정

### 완료
- [x] `docs/PUSH_SETUP_TODO.md`가 2026-03-31 기준 Firebase 파일 부재 상태를 현재 blocker처럼 보이게 하던 문서 충돌을 정리
- [x] 최신 기준은 `docs/PUSH_LIVE_ACTIVITY_BACKEND_SETUP.md`, setup status, readiness audit, push/live preflight라고 명시
- [x] 2026-06-04 기준 앱 Firebase/APNs/Live Activity 파일은 app-only preflight를 통과했고, 남은 blocker는 Firebase Admin JSON, Apple APNs `.p8`, AWS deploy target, GitHub Actions secrets/variables 같은 운영 입력값이라고 분리

### 검증
- [x] `./scripts/push-live-preflight.sh --app-only` (`checks=29`, `warnings=1`, `failures=0`; warning은 backend secret check skip)
- [x] `./scripts/push-live-preflight.sh --env-file /tmp/kbo-fans-aws.env --aws` (`failures=9`; Firebase Admin/APNs/AWS placeholder 운영값 미설정 확인)
- [x] `./scripts/push-demo-readiness-audit.sh --env-file /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans` (`failures=16`; GitHub Actions secrets/variables 미설정 확인)

---

## 2026-06-04: App Build Artifacts workflow heredoc 안정화

### 완료
- [x] GitHub Actions runner에서 `run: |` 들여쓰기 때문에 bash heredoc 종료 토큰이 깨질 수 있는 Android signing, iOS signing/export, platform metadata 생성 경로를 점검
- [x] `.github/workflows/app-build-artifacts.yml`의 heredoc 기반 파일 생성을 `python3 -c`와 `printf` 기반 생성으로 교체해 YAML 들여쓰기와 무관하게 동작하도록 보강
- [x] Android key.properties, Android/Web/iOS metadata, iOS ExportOptions.plist 생성 경로를 임시 디렉터리에서 실행 검증
- [x] release artifact metadata의 `push_api_base_url` 출력은 유지해, release 빌드가 어떤 token-registration backend URL을 품었는지 artifact에서 확인할 수 있게 유지
- [x] GitHub Actions 원격 `web/release` artifact run을 성공시켜 backend test, release web build, metadata, artifact upload 경로까지 확인
- [x] Android release signing, iOS simulator, signed IPA 원격 실행은 Firebase/APNs/AWS/GitHub secrets 준비 이후 남은 수동 검증 항목으로 유지

### 검증
- [x] `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/app-build-artifacts.yml"); puts "workflow yaml ok"'`
- [x] `rg -n "<<|EOF|PY" .github/workflows/app-build-artifacts.yml .github/workflows/push-demo-deploy.yml || true` (match 없음)
- [x] 임시 디렉터리에서 workflow `Create export options` run script 실행 및 `plistlib` load 확인
- [x] 임시 디렉터리에서 workflow `Configure Android signing` run script 실행 및 keystore/key.properties/GITHUB_ENV 결과 확인
- [x] 임시 디렉터리에서 workflow metadata 생성 run script를 `matrix.app_environment=release` 치환 후 실행해 각 metadata 파일 주요 필드 확인
- [x] GitHub Actions `App Build Artifacts` run `26931917852` (`headSha=bf343a9`, `platform=web`, `app_environment=release`) success: `backend_tests`, `prepare`, `web (release)` 통과
- [x] `gh run download 26931917852 --repo godekd3133/kbo-fans -n web-release` 후 `web-build-metadata-release.txt`의 `data_mode=no-backend-direct`, `push_api_base_url=https://api.kbofans.com/api`, `archive=build/kbo-fans-web-release.zip` 확인
- [x] 다운로드한 `kbo-fans-web-release.zip` 내부 `index.html`, `flutter_bootstrap.js`, `main.dart.js` 존재 확인

---

## 2026-06-04: Push preflight release URL handoff 검증 보강

### 완료
- [x] `push-live-preflight.sh --app-only`가 앱 Firebase/APNs/Live Activity 파일뿐 아니라 release no-backend build의 push / Live Activity token registration용 `API_BASE_URL` handoff도 확인하도록 보강
- [x] preflight가 `scripts/codex-run.sh`의 release `API_BASE_URL` dart define, `.github/workflows/app-build-artifacts.yml`의 `release_api_base_url` input, CI `API_BASE_URL` dart define, `PUSH_API_BASE_URL` artifact metadata를 구조적으로 점검하도록 추가
- [x] README, Push / Live Activity setup 문서, AGENTS, CLAUDE, repo skill, changelog에 preflight의 release URL handoff 검증 범위 반영

### 검증
- [x] `bash -n scripts/push-live-preflight.sh scripts/codex-run.sh`
- [x] `./scripts/push-live-preflight.sh --app-only` (`checks=29`, `warnings=1`, `failures=0`; warning은 backend secret check skip)

---

## 2026-06-04: backend 전체 ruff debt 정리

### 완료
- [x] backend 전체 ruff check를 막던 crawler/main/html import 정리와 line-length debt 제거
- [x] `player_stats.py`, `team_stats.py`, `scoreboard.py`의 긴 KBO form field / parser 표현을 동작 변경 없이 줄바꿈 또는 local field 변수로 정리
- [x] `main.py`, `utils/html.py` import formatting을 ruff 기준에 맞춤

### 검증
- [x] `backend/.venv/bin/pytest -q` (117 passed)
- [x] `backend/.venv/bin/ruff check --select E,F,I,B backend/src backend/tests` (`All checks passed`)
- [x] `python3 -m compileall backend/src`

---

## 2026-06-04: no-backend 앱 본체 검증 refresh

### 완료
- [x] 현재 앱 본체가 backend API를 기본 전제로 하지 않는 no-backend direct data 방향을 유지하는지 재검증
- [x] `USE_BACKEND_API=true` 명시 opt-in에서도 provider routing 계약이 깨지지 않는지 별도 확인
- [x] release web artifact가 backend health gate 없이 direct KBO + snapshot 경로로 컴파일되는지 확인

### 검증
- [x] `cd app && fvm flutter analyze` (`No issues found`)
- [x] `cd app && fvm flutter test` (76 tests passed)
- [x] `cd app && fvm flutter test --dart-define=USE_BACKEND_API=true test/data/providers_routing_test.dart` (1 test passed)
- [x] `cd app && fvm flutter build web --release --dart-define=APP_ENV=release --dart-define=PREFER_DIRECT_SCRAPE=true` (`✓ Built build/web`; wasm dry-run warning은 `flutter_timezone_web.dart` JS interop warning으로 일반 web release build는 성공)
- [x] `cd app && GRADLE_OPTS='-Djdk.lang.Process.launchMechanism=FORK' fvm flutter build apk --release --dart-define=APP_ENV=release --dart-define=PREFER_DIRECT_SCRAPE=true` (`✓ Built build/app/outputs/flutter-apk/app-release.apk`, 62.1MB)
- [x] `cd app && fvm flutter build ios --debug --no-codesign --dart-define=APP_ENV=local --dart-define=PREFER_DIRECT_SCRAPE=true` (`✓ Built build/ios/iphoneos/Runner.app`)

---

## 2026-06-04: Push demo 설정값 안내 보강

### 완료
- [x] 앱 종료 후 push / Dynamic Island 시연을 위해 사장님이 직접 준비해야 하는 Firebase client config, Firebase Admin JSON, Apple APNs key, AWS deploy target, GitHub OIDC role, release API base URL의 출처와 입력 위치를 `push-demo-setup-status.sh` 출력에 `Required Values` 섹션으로 추가
- [x] Required Values는 secret 값을 출력하지 않고 `get_from`, `put_in_env`, `github_target`, `aws_runtime_target` 형태로만 안내하도록 구성
- [x] README, Push / Live Activity setup 문서, repo skill, changelog에 setup status의 Required Values 기준 기록

### 검증
- [x] `bash -n scripts/push-demo-setup-status.sh scripts/codex-run.sh`
- [x] `./scripts/codex-run.sh push-demo-setup-status --env-file /tmp/kbo-fans-required-values.env --repo godekd3133/kbo-fans --skip-tooling` 실행: expected attention, `Required Values` 섹션이 secret 값 없이 Firebase / APNs / AWS / GitHub / release API base URL 입력 위치를 출력

---

## 2026-06-04: Push registry 공유 저장 안정화

### 완료
- [x] 앱 종료 후 push / Dynamic Island 갱신을 위해 API service가 저장한 FCM / ActivityKit token과 sync worker heartbeat / scoreboard state가 같은 registry 파일에서 보존되도록 `PushRegistry` 저장 경로 보강
- [x] `PUSH_REGISTRY_PATH` JSON registry에 sibling lock file과 atomic replace를 적용해 별도 프로세스의 API task / scheduler task 동시 쓰기 중 token, heartbeat, scoreboard state가 유실될 수 있는 경로 차단
- [x] 여러 프로세스와 같은 프로세스의 여러 registry 인스턴스가 같은 registry 파일에 device token을 동시에 저장해도 최종 token 수가 보존되는 regression test 추가
- [x] backend README, Push / Live Activity setup 문서, repo skill, changelog에 공유 registry 파일락/atomic write 기준 기록

### 검증
- [x] `backend/.venv/bin/pytest -q backend/tests/test_push_service.py::test_push_registry_serializes_writes_across_processes` (1 passed)
- [x] `backend/.venv/bin/pytest -q backend/tests/test_push_service.py` (18 passed)
- [x] `backend/.venv/bin/ruff check --select E,F,I,B backend/src/kbo_fans_backend/services/push_registry.py backend/tests/test_push_service.py`
- [x] `python3 -m compileall backend/src/kbo_fans_backend`

---

## 2026-06-04: Live Activity sync KBO 경기일 기준 보정

### 완료
- [x] 앱 종료 후 Live Activity scoreboard sync endpoint의 기본 날짜가 AWS host UTC date를 따르지 않고 KBO 경기일(`Asia/Seoul`)을 사용하도록 보정
- [x] `date` query가 없을 때 `current_kbo_date()`를 호출하는 regression test 추가
- [x] `scripts/push-readiness-check.sh`의 one-shot sync 기본 날짜도 shell `date` 대신 backend KBO 경기일 기본값에 위임하도록 보정
- [x] 특정 날짜 재현이 필요할 때만 `PUSH_READINESS_DATE=YYYY-MM-DD`를 사용하도록 README/backend setup 문서에 기록
- [x] `scripts/push-readiness-check.sh`가 기본적으로 `scheduler.lastSyncAt` 180초 이내 heartbeat를 요구하도록 보강해 sync worker가 멈춘 배포를 통과시키지 않도록 변경
- [x] 설정값만 확인하는 초기 점검을 위해 `PUSH_READINESS_REQUIRE_SCHEDULER=false` 우회 옵션을 문서화

### 검증
- [x] `backend/.venv/bin/pytest -q backend/tests/test_push_service.py` (16 passed)
- [x] `backend/.venv/bin/ruff check --select E,F,I,B backend/src/kbo_fans_backend/api/routes/push.py backend/tests/test_push_service.py`
- [x] `python3 -m compileall backend/src/kbo_fans_backend`
- [x] `bash -n scripts/push-readiness-check.sh scripts/codex-run.sh`
- [x] ephemeral localhost mock server로 scheduler heartbeat 없음 실패, `PUSH_READINESS_REQUIRE_SCHEDULER=false` 우회, `PUSH_READINESS_RUN_SYNC=true` one-shot sync 후 heartbeat 재조회 통과 확인
- [x] one-shot sync 기본 요청은 query 없이 `/api/push/live-activity/sync-scoreboard`, `PUSH_READINESS_DATE=2026-06-04` 지정 시에만 `/api/push/live-activity/sync-scoreboard?date=2026-06-04` 확인
- [x] fresh scheduler heartbeat mock에서 `scheduler=status=ok` 통과 확인
- [x] stale scheduler heartbeat mock에서 `scheduler=status=fail reason=stale` 실패 확인
- [x] `PUSH_READINESS_REQUIRE_SCHEDULER=false` mock에서 heartbeat 없이도 설정-only 점검 통과 확인
- [x] `PUSH_READINESS_RUN_SYNC=true` mock에서 health → config defer → sync → config heartbeat 재확인 4단계 통과 확인
- [x] `PUSH_READINESS_RUN_SYNC=true PUSH_READINESS_DATE=2026-06-04` mock에서 명시 날짜 query와 sync 후 heartbeat 재확인 통과 확인
- [x] `./scripts/codex-run.sh push-demo-setup-status --env-file /tmp/kbo-fans-goal-status.env --repo godekd3133/kbo-fans --skip-tooling` 실행: env bootstrap/OIDC dry-run은 통과, readiness audit은 Firebase Admin JSON, APNs `.p8`, AWS OIDC/ECR/VPC/Subnet/ACM 등 외부 설정 누락으로 expected attention
- [x] `./scripts/codex-run.sh github-push-demo-run --repo godekd3133/kbo-fans --dry-run true` 실행: 필수 GitHub Actions secret/variable 누락을 dispatch 전에 차단
- [x] `gh run list --repo godekd3133/kbo-fans --workflow push-demo-deploy.yml --limit 1 --json databaseId,status,conclusion,url` 확인: 최신 run은 기존 `26915430732` 그대로이며 새 workflow dispatch 없음

---

## 2026-06-04: KBO Fans 8분 발표 자료 제작

### 완료
- [x] `CLAUDE.md`, `docs/PLANNING.md`, `docs/APP_SPEC.md`, `docs/FIGMA_PROMPT.md`, `docs/WORKLOG.md`, `README.md`, `CHANGELOG.md` 기준으로 8분 발표 흐름 정리
- [x] 발표 원고를 `기능명` + `기획한 내용` / `개발한 내용` 구조로 재작성
- [x] 슬라이드 제목을 기능명만 남기는 방식으로 정리
  - 마이팀 / 홈 / 경기 상세 스코어 / 문자중계 / 박스스코어 / 라인업 / 일정 / 예매 알림 / 순위 / 기록실 / 알림 / 데이터 처리 / 구현 현황
- [x] 본문은 기능별 기획 의도와 실제 구현 범위만 설명하도록 재구성
- [x] 실제 앱 화면 중심으로 14장 PPTX 재생성
- [x] 최종 PPTX 생성: `outputs/019e8edf-f74f-7c13-9da8-b88d32e0a45c/presentations/kbo-fans-8min/output/kbo-fans-8min-plan-dev-presentation.pptx`

### 검증
- [x] 기존 Playwright 검증 artifact의 실제 앱 화면을 발표 자료용 화면 근거로 선별
- [x] artifact-tool PPTX export 성공: 14 slides, 3.4MB
- [x] rendered contact sheet 시각 검수: 기능명 제목과 두 개 본문 블록 구성 확인
- [x] `check_layout_quality.mjs --layout ... --warn-only`: 14개 layout 파일 기준 error 0개, warning 0개
- [x] 발표 원고와 PPT source에서 이전 메타식 문구 잔존 여부 검색: match 없음

---

## 2026-06-04: no-backend 기본 런타임 전환

### 완료
- [x] Director의 “backend/API 연결이 없어도 앱/웹이 기본으로 동작해야 한다”는 기준을 현재 런타임 정책으로 반영
- [x] `AppConfig`에 `USE_BACKEND_API=true` 명시 opt-in을 추가하고, 기본 provider routing을 direct KBO + snapshot 경로로 전환
- [x] 웹 기록실/선수 direct 조회가 KBO source를 CORS proxy 경로로 접근하도록 `KboDirectPlayerRepository` 보강
- [x] widget background scoreboard와 Codex iOS/Android/Web 실행 스크립트를 backend health/API URL 주입 없이 no-backend direct mode로 전환
- [x] GitHub Actions app artifact workflow를 no-backend direct data mode로 빌드하도록 전환
- [x] `home_widget 0.9.0`의 `androidx.glance:glance-appwidget:1.+` 동적 의존성이 `1.3.0-alpha01`을 잡아 `compileSdk 37 / AGP 9.1`을 요구하던 Android metadata 실패를 확인하고, repo Gradle에서 Glance `1.0.0`으로 고정
- [x] macOS JDK spawn helper 실패(`Failed to exec spawn helper`)를 확인하고, Codex Android 실행 스크립트가 `GRADLE_OPTS=-Djdk.lang.Process.launchMechanism=FORK`를 주입하도록 보강
- [x] 로컬 CocoaPods/Ruby 설치가 깨져 iOS pod install 전 단계에서 실패하던 상태를 Homebrew 재설치로 복구
- [x] README, AGENTS, CLAUDE, APP_SPEC, ENGINEERING_NOTES, APP_STANDALONE_MODE, DISTRIBUTION_GUIDE, VERSIONING, repo skills 문서 동기화

### 검증
- [x] `bash -n scripts/codex-run.sh scripts/codex-run-web.sh scripts/codex-run-web-release.sh scripts/codex-run-ios-release.sh scripts/codex-run-android-release.sh`
- [x] `cd app && fvm dart format lib/core/config/app_config.dart lib/data/providers.dart lib/data/repositories/kbo_direct_player_repository.dart lib/services/widget_sync_service.dart test/data/providers_routing_test.dart`
- [x] `cd app && fvm flutter test test/data/providers_routing_test.dart`
- [x] `cd app && fvm flutter test --dart-define=USE_BACKEND_API=true test/data/providers_routing_test.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test`
- [x] `cd app && fvm flutter build web --release --dart-define=APP_ENV=release --dart-define=PREFER_DIRECT_SCRAPE=true`
- [x] `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/app-build-artifacts.yml"); puts "workflow yaml ok"'`
- [x] `cd app/android && ./gradlew :app:dependencies --configuration debugRuntimeClasspath | rg -n "androidx.glance:glance-appwidget|remote-creation" -C 2` (`glance-appwidget:1.+ -> 1.0.0`, `remote-creation` alpha 제거 확인)
- [x] `cd app/android && GRADLE_OPTS='-Djdk.lang.Process.launchMechanism=FORK' ./gradlew :app:assembleDebug --no-daemon --stacktrace -Ptarget-platform=android-arm,android-arm64,android-x64 -Ptarget=lib/main.dart -Pbase-application-name=android.app.Application -Pdart-defines=QVBQX0VOVj1sb2NhbA==,UFJFRkVSX0RJUkVDVF9TQ1JBUEU9dHJ1ZQ== -Pdart-obfuscation=false -Ptrack-widget-creation=true -Ptree-shake-icons=false` (`BUILD SUCCESSFUL in 4m 25s`)
- [x] `cd app && GRADLE_OPTS='-Djdk.lang.Process.launchMechanism=FORK' fvm flutter build apk --debug --dart-define=APP_ENV=local --dart-define=PREFER_DIRECT_SCRAPE=true` (`✓ Built build/app/outputs/flutter-apk/app-debug.apk`)
- [x] `cd app && GRADLE_OPTS='-Djdk.lang.Process.launchMechanism=FORK' fvm flutter build apk --release --dart-define=APP_ENV=release --dart-define=PREFER_DIRECT_SCRAPE=true` (`✓ Built build/app/outputs/flutter-apk/app-release.apk`)
- [x] `cd app/ios && pod install`
- [x] `cd app && fvm flutter build ios --debug --no-codesign --dart-define=APP_ENV=local --dart-define=PREFER_DIRECT_SCRAPE=true` (`✓ Built build/ios/iphoneos/Runner.app`)
- [x] Playwright 390x844 정적 로드: `http://localhost:7357` 앱 title 확인, `#/home` route 진입 확인
- [x] `git diff --check`

### Android 빌드 진단 기록
- 1차 실패: `home_widget` Glance 동적 의존성이 `1.3.0-alpha01`을 잡아 Android API 37 / AGP 9.1 요구
- 2차 지연: Flutter wrapper의 quiet Gradle 실행에서는 진행 지점이 보이지 않아 중단
- 원인 분리: 직접 Gradle 실행에서 macOS JDK spawn helper 실패 확인
- 보정 후 직접 Gradle `assembleDebug`, Flutter wrapper 기반 debug APK, release APK 모두 성공.

### iOS 빌드 진단 기록
- 1차 실패: CocoaPods 설치 상태가 깨져 Flutter가 pod install을 건너뛰고 iOS build를 중단
- 보정: `brew reinstall ruby cocoapods` 후 `pod --version` `1.16.2`, `cd app/ios && pod install` 성공
- 2차 실패: Xcode AssetCatalog 처리 중 `Failed to launch AssetCatalogSimulatorAgent via CoreSimulator spawn`
- 보정: CoreSimulator service 재시작 후 같은 no-backend dart-define로 `flutter build ios --debug --no-codesign` 성공.

---

## 2026-06-04: 앱 종료 후 푸시 / Dynamic Island 실시간 갱신 기반

### 완료
- [x] Firebase/FCM은 일반 푸시 전달 채널이고, 앱 종료 후 iOS Live Activity / Dynamic Island 갱신은 backend + APNs ActivityKit push가 필요하다는 구조로 정리
- [x] FCM background handler를 앱 시작 초기에 등록하고, iOS FCM token sync 전에 APNs token 준비를 기다리도록 보강
- [x] iOS Live Activity를 `pushType: .token`으로 시작하고 ActivityKit push token을 Flutter channel과 native URLSession 양쪽에서 backend에 등록하도록 연결
- [x] Runner entitlement에 `aps-environment`를 추가하고 Debug/Profile은 development, Release는 production으로 분리
- [x] backend에 FCM device token / ActivityKit push token registry를 추가하고, 실제 token 저장 경로를 `backend/data/runtime/` gitignore 영역으로 분리
- [x] backend에 APNs `liveactivity` provider sender, Live Activity register/unregister/update API, scoreboard 기반 sync trigger를 추가
- [x] 같은 scoreboard sync에서 이전 scoreboard state와 비교해 `game_start`, `scoring`, `reversal`, `game_end`, `inning_change` FCM topic push를 발행하도록 보강
- [x] iOS Runner/Widget plist에 `NSSupportsLiveActivitiesFrequentUpdates`를 추가해 잦은 Live Activity 갱신 의도를 명시
- [x] AWS 배포 후 Firebase/APNs/registry/scheduler secret 누락을 확인할 수 있도록 `GET /api/push/config-status`와 `python -m kbo_fans_backend.scheduler.push_config_status`를 추가
- [x] 외부에서 `/health`와 push readiness를 한 번에 검증하는 `scripts/push-readiness-check.sh`와 `./scripts/codex-run.sh push-readiness` entrypoint를 추가
- [x] AWS 배포 시작점을 위해 `backend/Dockerfile`, `backend/.dockerignore`, `python -m kbo_fans_backend.scheduler.live_activity_sync` scheduler CLI를 추가
- [x] 노트북이 꺼진 시연을 위해 AWS/운영 backend, Firebase, APNs, EventBridge/cron 설정 절차를 `docs/PUSH_LIVE_ACTIVITY_BACKEND_SETUP.md`에 문서화
- [x] AWS ECS/Fargate에서 파일 mount 없이 Secrets Manager env로 Firebase Admin JSON / APNs `.p8`를 주입할 수 있도록 `FIREBASE_SERVICE_ACCOUNT_JSON`, `APNS_AUTH_KEY_P8`를 backend 설정에 추가
- [x] AWS UTC 기준 날짜 오판을 피하도록 Live Activity scoreboard sync worker와 `/push/live-activity/sync-scoreboard` 기본 날짜를 `Asia/Seoul` KBO 경기일로 계산
- [x] 30~60초 시연용 long-running sync worker CLI `python -m kbo_fans_backend.scheduler.live_activity_sync_loop`를 추가
- [x] ECS/Fargate API service + sync worker service 템플릿을 `infra/aws/ecs-fargate/`에 추가
- [x] worker가 실제로 실행됐는지 확인할 수 있도록 scoreboard sync heartbeat를 registry에 기록하고 `GET /api/push/config-status`의 `scheduler.lastSyncAt`으로 노출
- [x] Firebase Admin JSON / APNs `.p8` / sync secret을 AWS Secrets Manager에 생성 또는 갱신하고 renderer용 `SECRET_ARN_*` export를 출력하는 `scripts/aws-push-secrets.sh`, `./scripts/codex-run.sh aws-push-secrets` entrypoint를 추가
- [x] AWS ECS task definition placeholder를 환경변수로 렌더링/검증하는 `infra/aws/ecs-fargate/render_task_definitions.py`, `scripts/aws-push-task-definitions.sh`, `./scripts/codex-run.sh aws-push-task-defs` entrypoint를 추가
- [x] ECS task execution role trust policy와 Firebase/APNs/sync secret read inline policy 템플릿을 추가하고, task definition renderer가 IAM policy도 함께 렌더링하도록 보강
- [x] AWS push 배포 env checklist `infra/aws/ecs-fargate/deploy.env.example`와 env/rendered JSON/AWS 리소스를 확인하는 `scripts/aws-push-deploy-check.sh`, `./scripts/codex-run.sh aws-push-deploy-check` entrypoint를 추가
- [x] AWS 배포 문서 순서를 secret 생성, IAM role 생성, ECR/EFS/log group 준비, template 렌더링, secret-read policy 부착, deploy preflight 순서로 정리
- [x] ALB, ECS Fargate API service, scoreboard sync worker, EFS registry, IAM role, CloudWatch log group을 한 stack으로 만드는 `infra/aws/cloudformation/push-demo-stack.json`와 `scripts/aws-push-cloudformation.sh`, `./scripts/codex-run.sh aws-push-cloudformation` entrypoint를 추가
- [x] backend Docker image를 ECR에 build/tag/push하고 `CONTAINER_IMAGE_URI` env를 남기는 `scripts/aws-push-image.sh`, `./scripts/codex-run.sh aws-push-image` entrypoint를 추가
- [x] CloudFormation stack output `ApiBaseUrl`을 release build용 `RELEASE_API_BASE_URL` / `API_BASE_URL`로 추출하는 `scripts/aws-push-stack-outputs.sh`, `./scripts/codex-run.sh aws-push-stack-outputs` entrypoint를 추가
- [x] secret upload, ECR image push, CloudFormation deploy, stack output export, readiness를 순서대로 실행하는 `scripts/aws-push-demo-deploy.sh`, `./scripts/codex-run.sh aws-push-demo-deploy` 통합 entrypoint를 추가
- [x] 배포 전 앱 Firebase 파일, APNs/Live Activity capability, backend secret env, AWS env 형태를 secret 출력 없이 확인하는 `scripts/push-live-preflight.sh`, `./scripts/codex-run.sh push-live-preflight` entrypoint를 추가
- [x] 로컬 AWS CLI credential과 Docker daemon 상태를 확인하는 `scripts/aws-push-tooling-check.sh`, `./scripts/codex-run.sh aws-push-tooling` entrypoint를 추가
- [x] 로컬 AWS CLI/Docker 상태에 의존하지 않고 GitHub Actions runner에서 같은 push demo deploy pipeline을 실행할 수 있도록 `.github/workflows/push-demo-deploy.yml` 수동 workflow를 추가
- [x] 로컬 env 파일, Firebase client config, Firebase Admin JSON, APNs 파일을 기준으로 GitHub Actions secrets/variables를 dry-run 또는 `--apply` 업로드할 수 있는 `scripts/github-push-secrets.sh`, `./scripts/codex-run.sh github-push-secrets` entrypoint를 추가
- [x] GitHub Actions app artifact workflow에서 ignored Firebase client config 파일을 `IOS_GOOGLE_SERVICE_INFO_PLIST`, `ANDROID_GOOGLE_SERVICES_JSON` secrets에서 복원하도록 보강
- [x] GitHub Actions `Push Demo Deploy` workflow를 CLI에서 dispatch하고, 원격 workflow 미등록 시 커밋/푸시 필요 상태를 안내하는 `scripts/github-push-demo-run.sh`, `./scripts/codex-run.sh github-push-demo-run` entrypoint를 추가
- [x] GitHub Actions `Push Demo Deploy` dispatch 전에 필수 secrets/variables 존재를 확인하고, 누락 상태에서는 workflow run을 만들기 전에 중단하도록 `scripts/github-push-demo-run.sh`를 보강
- [x] `infra/aws/ecs-fargate/deploy.env.example`를 push preflight, 로컬 AWS 배포, GitHub Actions secrets/variables 업로드에 함께 쓰는 단일 checklist로 보강
- [x] `scripts/github-push-secrets.sh`가 obvious placeholder 값을 GitHub Actions secrets/variables로 업로드하기 전에 실패하도록 보강
- [x] 앱 파일, env checklist, 로컬 AWS/Docker tooling, GitHub Actions workflow/secrets/variables, 최신 deploy run을 배포 없이 점검하는 `scripts/push-demo-readiness-audit.sh`, `./scripts/codex-run.sh push-demo-audit` entrypoint를 추가
- [x] `push-demo-readiness-audit.sh`가 누락된 Firebase client config, Firebase Admin, APNs, AWS auth/network/HTTPS 입력값을 `next_config[...]`로 분류해 다음 설정 작업을 바로 안내하도록 보강
- [x] Firebase client config 경로와 project id를 감지해 `/tmp/kbo-fans-aws.env` 같은 로컬 untracked env 초안을 만드는 `scripts/push-demo-env-bootstrap.sh`, `./scripts/codex-run.sh push-demo-env-bootstrap` entrypoint를 추가
- [x] env bootstrap이 `--repo`를 받아 후속 OIDC/audit next command에 실제 repo를 표시하도록 보강
- [x] env bootstrap과 `infra/aws/ecs-fargate/deploy.env.example`에 Firebase client, Firebase Admin, APNs, AWS OIDC/ECR/VPC/ACM 값의 발급 위치와 업로드 대상 주석을 추가
- [x] `push-live-preflight.sh --aws`가 첫 누락 파일에서 조기 종료되지 않고 Firebase Admin, APNs, AWS placeholder를 한 번에 모으도록 보정하고, 배포 필수값의 obvious placeholder는 failure로 처리하도록 강화
- [x] GitHub Actions가 장기 AWS access key 없이 배포할 수 있도록 `AWS_ROLE_TO_ASSUME` OIDC role CloudFormation 템플릿과 `scripts/aws-github-oidc-role.sh`, `./scripts/codex-run.sh aws-github-oidc-role` entrypoint를 추가
- [x] env 초안 생성, OIDC role dry-run, readiness audit, 다음 명령 안내를 하나로 묶는 `scripts/push-demo-setup-status.sh`, `./scripts/codex-run.sh push-demo-setup-status` entrypoint를 추가
- [x] backend APNs `liveactivity` payload의 `content-state`가 iOS `KboFansScoreAttributes.ContentState` 계약과 맞는지 고정하는 regression test 추가
- [x] 수동 ECS 템플릿 경로와 CloudFormation full-stack 경로의 역할 차이를 `docs/PUSH_LIVE_ACTIVITY_BACKEND_SETUP.md`, `README.md`, `backend/README.md`, `infra/aws/cloudformation/README.md`에 기록
- [x] release no-backend direct 실행/CI artifact도 push / Live Activity token 등록을 위해 운영 `API_BASE_URL`을 주입하도록 `scripts/codex-run.sh`와 `.github/workflows/app-build-artifacts.yml`을 보강
- [x] `API_BASE_URL` override가 provider routing을 backend mode로 바꾸지 않고 push registration base URL만 바꿀 수 있음을 `providers_routing_test.dart`에 추가 확인

### 운영 조건
- [ ] 시연용 iPhone만 켜 둔 상태에서 동작하려면 FastAPI backend가 AWS ECS/Fargate 또는 EC2 같은 상시 서버에 떠 있어야 한다.
- [ ] 운영 backend에는 `FIREBASE_SERVICE_ACCOUNT_JSON` 또는 `FIREBASE_SERVICE_ACCOUNT_PATH`, `FIREBASE_PROJECT_ID`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_AUTH_KEY_P8` 또는 `APNS_AUTH_KEY_PATH`, `APNS_BUNDLE_ID`, `APNS_USE_SANDBOX=false`, `PUSH_SYNC_SECRET`를 secret/env로 넣어야 한다.
- [ ] ECS task execution role에는 AWS managed `AmazonECSTaskExecutionRolePolicy`와 rendered `iam-task-execution-secrets-policy.rendered.json` inline policy를 붙여야 한다.
- [ ] ECS task definition 등록 또는 service 생성 전 `./scripts/aws-push-deploy-check.sh`가 AWS credential, secret, IAM role, ECR, EFS, CloudWatch log group을 모두 확인해야 한다.
- [ ] CloudFormation 경로를 쓸 경우 ECR image, ACM certificate, VPC/subnet, Firebase/APNs secret ARN을 먼저 준비하고, stack output `ApiBaseUrl`을 release `API_BASE_URL`로 주입해야 한다.
- [ ] backend image는 `./scripts/aws-push-image.sh`로 ECR에 push되어 있어야 ECS service가 정상 기동할 수 있다.
- [ ] 전체 시연 배포는 `./scripts/aws-push-demo-deploy.sh`로 secret/image/stack/output/readiness 순서가 끊기지 않는지 확인해야 한다.
- [ ] 전체 시연 배포 전 `./scripts/push-live-preflight.sh --env-file /path/to/kbo-fans-aws.env --aws`가 failures 0개로 통과해야 한다.
- [ ] 로컬 배포는 `./scripts/aws-push-tooling-check.sh`가 failures 0개여야 가능하다. 로컬 tooling이 안 되면 GitHub Actions `Push Demo Deploy` workflow를 사용한다.
- [ ] GitHub Actions 배포 전 `./scripts/github-push-secrets.sh --env-file /path/to/kbo-fans-aws.env` dry-run으로 업로드 대상 이름을 확인하고, 값이 맞으면 `--apply`로 secrets/variables를 등록해야 한다.
- [ ] GitHub Actions workflow 파일을 커밋/푸시한 뒤 `./scripts/github-push-demo-run.sh --dry-run true --watch`와 `--dry-run false --watch` 순서로 실행해야 한다. 이 CLI의 config check는 필수 secrets/variables 누락 시 dispatch 전에 실패해야 한다.
- [ ] release TestFlight/Android artifact에는 운영 `API_BASE_URL`이 push / Live Activity token registration endpoint로 주입되어야 한다.
- [ ] API task와 scheduler task가 분리되면 `PUSH_REGISTRY_PATH`는 EFS/EBS/DynamoDB 등 공유 영속 저장소를 바라봐야 한다.
- [ ] ECS sync worker, EventBridge Scheduler, 또는 cron이 live 경기 중 30~60초 간격으로 scoreboard sync를 실행해야 한다.
- [ ] 운영 확인 시 `GET /api/push/config-status`의 `scheduler.lastSyncAt`이 최근 시각으로 갱신되어야 한다.
- [ ] 실기기 TestFlight/release 검증에는 Firebase plist, Push Notifications capability, APNs production profile이 필요하다.

### 검증
- [x] `backend/.venv/bin/ruff check --select E,F,I,B infra/aws/ecs-fargate/render_task_definitions.py backend/src/kbo_fans_backend/core/config.py backend/src/kbo_fans_backend/schemas/push.py backend/src/kbo_fans_backend/services/push.py backend/src/kbo_fans_backend/services/push_registry.py backend/src/kbo_fans_backend/services/apns_live_activity.py backend/src/kbo_fans_backend/services/live_activity_scoreboard.py backend/src/kbo_fans_backend/services/push_diagnostics.py backend/src/kbo_fans_backend/api/routes/push.py backend/src/kbo_fans_backend/scheduler/live_activity_sync.py backend/src/kbo_fans_backend/scheduler/live_activity_sync_loop.py backend/src/kbo_fans_backend/scheduler/push_config_status.py backend/tests/test_push_service.py`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_push_service.py` (14 passed, Live Activity update + FCM scoreboard moment diff + config-status guard + AWS secret-env diagnostics 포함)
- [x] `python3 -m compileall backend/src/kbo_fans_backend`
- [x] `python3 -m json.tool infra/aws/ecs-fargate/task-definition-api.json >/dev/null && python3 -m json.tool infra/aws/ecs-fargate/task-definition-sync-worker.json >/dev/null`
- [x] `python3 -m json.tool infra/aws/ecs-fargate/ecs-task-assume-role-policy.json`
- [x] `python3 -m json.tool infra/aws/ecs-fargate/iam-task-execution-secrets-policy.json`
- [x] `python3 -m json.tool infra/aws/cloudformation/push-demo-stack.json`
- [x] `bash -n infra/aws/ecs-fargate/deploy.env.example scripts/aws-push-cloudformation.sh scripts/aws-push-demo-deploy.sh scripts/aws-push-deploy-check.sh scripts/aws-push-image.sh scripts/aws-push-stack-outputs.sh scripts/aws-push-task-definitions.sh scripts/codex-run.sh`
- [x] `backend/.venv/bin/ruff check --select E,F,I,B infra/aws/ecs-fargate/render_task_definitions.py`
- [x] `python3 -m py_compile infra/aws/ecs-fargate/render_task_definitions.py`
- [x] `bash -n scripts/aws-push-secrets.sh scripts/aws-push-task-definitions.sh scripts/codex-run.sh`
- [x] invalid Firebase JSON / invalid APNs `.p8` dry-run failure path 확인
- [x] mock Firebase JSON / APNs `.p8`로 `./scripts/aws-push-secrets.sh --dry-run` 성공 및 `outputs/aws/ecs-fargate/secrets.env` 생성 확인
- [x] `python3 infra/aws/ecs-fargate/render_task_definitions.py --validate-only` missing env failure path 확인
- [x] mock AWS env로 `./scripts/aws-push-task-definitions.sh --validate-only` 성공 확인 (`aws_ecs_templates=status=ok mode=validate-only`)
- [x] mock AWS env로 `./scripts/codex-run.sh aws-push-task-defs`가 `outputs/aws/ecs-fargate/*.rendered.json`를 생성하고 rendered JSON 검증 통과
- [x] mock AWS env로 rendered IAM policy / API task definition / sync-worker task definition 3개 JSON 파싱과 placeholder 잔존 없음 확인
- [x] mock AWS env로 `./scripts/aws-push-deploy-check.sh --skip-aws`와 `./scripts/codex-run.sh aws-push-deploy-check --skip-aws` 통과
- [x] mock AWS env로 `./scripts/aws-push-image.sh --dry-run --tag 0.0.29`와 `./scripts/codex-run.sh aws-push-image --dry-run --tag 0.0.29` 통과
- [x] mock AWS env로 `./scripts/aws-push-cloudformation.sh --dry-run`와 `./scripts/codex-run.sh aws-push-cloudformation --dry-run` 통과
- [x] mock CloudFormation `describe-stacks` JSON으로 `./scripts/aws-push-stack-outputs.sh --input-json ...`와 `./scripts/codex-run.sh aws-push-stack-outputs --input-json ...` 통과
- [x] mock Firebase JSON / APNs `.p8` / AWS env로 `./scripts/aws-push-demo-deploy.sh --dry-run --tag 0.0.29`와 `./scripts/codex-run.sh aws-push-demo-deploy --dry-run --tag 0.0.29` 통과
- [x] `bash -n scripts/push-live-preflight.sh scripts/codex-run.sh infra/aws/ecs-fargate/deploy.env.example`
- [x] `./scripts/push-live-preflight.sh --app-only` 통과 (`checks=25`, `warnings=1`, `failures=0`; warning은 backend secret check skip)
- [x] mock Firebase JSON / APNs `.p8` / AWS env로 `./scripts/push-live-preflight.sh --env-file ... --aws` 통과 (`checks=42`, `warnings=5`, `failures=0`; warnings는 mock placeholder ARN/account 및 secret ARN 생성 전 상태)
- [x] `./scripts/codex-run.sh push-live-preflight --app-only` 통과
- [x] 현재 머신 외부 배포 가능 상태 확인: `aws sts get-caller-identity`는 `command not found: aws`, `docker info`는 Docker CLI 존재 / daemon 미실행(`Cannot connect to the Docker daemon`)으로 확인
- [x] `bash -n scripts/aws-push-tooling-check.sh scripts/codex-run.sh scripts/aws-push-demo-deploy.sh scripts/push-live-preflight.sh`
- [x] `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/push-demo-deploy.yml")'` workflow YAML parse 통과
- [x] `./scripts/aws-push-tooling-check.sh` 현재 머신 상태 확인: Homebrew ok, AWS CLI missing, Docker CLI ok, Docker daemon not running
- [x] `bash -n scripts/github-push-secrets.sh scripts/codex-run.sh`
- [x] mock Firebase client config / Firebase Admin JSON / APNs `.p8` / AWS OIDC role env로 `./scripts/github-push-secrets.sh --env-file ... --repo godekd3133/kbo-fans` dry-run 통과. 출력은 secret/variable 이름만 포함하고 secret 값은 출력하지 않음
- [x] `bash -n scripts/github-push-demo-run.sh scripts/codex-run.sh`
- [x] `./scripts/codex-run.sh github-push-demo-run --repo godekd3133/kbo-fans --dry-run true` 현재 원격 상태에서 expected failure 확인: `push-demo-deploy.yml`가 default branch에 없어 커밋/푸시 필요 안내
- [x] `git commit -m "푸시 데모 배포 자동화 추가"` 생성 (`235e931`)
- [x] 기본 `origin` push는 `Repository not found`로 실패해 AGENTS 규칙의 `git@github-personal:godekd3133/kbo-fans.git` alias로 `main` push 성공
- [x] GitHub 원격에서 `Push Demo Deploy - push-demo-deploy.yml` workflow 노출 확인 (`workflow id 288871566`)
- [x] `gh secret list` / `gh variable list` 결과 현재 repo에 Actions secrets/variables가 아직 비어 있음을 확인
- [x] `./scripts/codex-run.sh github-push-demo-run --repo godekd3133/kbo-fans --dry-run true --watch` dispatch 성공 후 expected failure 확인 (`run 26915430732`): `Prepare push secrets` 단계에서 `Missing GitHub secret: FIREBASE_SERVICE_ACCOUNT_JSON`
- [x] `bash -n scripts/github-push-demo-run.sh scripts/codex-run.sh`
- [x] `./scripts/codex-run.sh github-push-demo-run --repo godekd3133/kbo-fans --dry-run true` 현재 원격 상태에서 expected failure 확인: 필수 secrets/variables 누락 목록을 출력하고 workflow dispatch 전 중단
- [x] `github-push-demo-run.sh`의 누락 설정 복구 안내가 `github-push-secrets.sh --repo <repo>`를 포함하도록 보강
- [x] 사전검사 실패 후 `gh run list --workflow push-demo-deploy.yml` 최신 run이 기존 `26915430732` 그대로임을 확인해 새 workflow run이 생성되지 않았음을 검증
- [x] mock env에서 `./scripts/github-push-secrets.sh --env-file ... --repo godekd3133/kbo-fans` placeholder failure path 확인: `FIREBASE_PROJECT_ID still looks like a placeholder`와 exit 2
- [x] placeholder가 아닌 mock env에서 `./scripts/github-push-secrets.sh --env-file ... --repo godekd3133/kbo-fans` dry-run 통과. secret 값 없이 `would_set_secret` / `would_set_variable` 이름만 출력
- [x] mock env에서 `./scripts/push-live-preflight.sh --env-file ... --aws` 통과 (`checks=41`, `warnings=4`, `failures=0`; warnings는 배포 후 생성될 stack output/secret ARN)
- [x] `bash -n scripts/push-demo-readiness-audit.sh scripts/codex-run.sh`
- [x] `./scripts/codex-run.sh push-demo-audit --repo godekd3133/kbo-fans --skip-tooling` 현재 상태 audit 확인: app project preflight 통과, env file 미지정 warning, local tooling audit skip, GitHub secrets/variables 14개 누락, 최신 workflow run `26915430732` 확인
- [x] mock env와 `--skip-gh --skip-tooling`으로 `./scripts/codex-run.sh push-demo-audit --env-file ... --repo godekd3133/kbo-fans` 실행: app project preflight와 env preflight 통과, 배포/workflow dispatch 없이 success path 확인
- [x] `bash -n scripts/push-demo-readiness-audit.sh scripts/codex-run.sh`
- [x] `./scripts/codex-run.sh push-demo-audit --repo godekd3133/kbo-fans --skip-tooling` 현재 상태 audit 확인: `next_config[...]`가 Firebase client config, Firebase Admin JSON, APNs `.p8`, AWS auth/region/network/HTTPS 누락 설정을 분류해 출력하고 expected failure 종료
- [x] mock env와 `--skip-gh --skip-tooling`으로 `./scripts/codex-run.sh push-demo-audit --env-file ... --repo godekd3133/kbo-fans` 실행: app project preflight와 env preflight 통과, 배포/workflow dispatch 없이 `next_command` success path 확인
- [x] `bash -n scripts/push-demo-env-bootstrap.sh scripts/codex-run.sh`
- [x] `./scripts/codex-run.sh push-demo-env-bootstrap --output /tmp/kbo-fans-aws-codex.env --force` 실행: 로컬 Firebase client config 감지, `PUSH_SYNC_SECRET` 생성, env file mode `600` 확인
- [x] `./scripts/codex-run.sh push-demo-env-bootstrap --output /tmp/kbo-fans-aws-codex-repo.env --repo godekd3133/kbo-fans --force` 실행: next command에 실제 repo 표시 확인
- [x] `./scripts/codex-run.sh push-demo-setup-status --env-file /tmp/kbo-fans-setup-status-repo.env --repo godekd3133/kbo-fans --skip-tooling --skip-gh` 실행: 하위 bootstrap next command의 repo 전달 확인, AWS placeholder로 expected attention
- [x] `./scripts/codex-run.sh push-demo-env-bootstrap --output /tmp/kbo-fans-aws-codex-commented.env --repo godekd3133/kbo-fans --force` 실행: 생성 env에 값 출처/업로드 대상 주석 포함 확인
- [x] bootstrap으로 생성한 env에서 `./scripts/push-live-preflight.sh --env-file /tmp/kbo-fans-aws-codex.env --aws` 실행: 외부에서 채워야 하는 Firebase Admin JSON / APNs key / AWS placeholder 누락을 `failures=9` expected failure로 확인
- [x] non-placeholder mock env에서 `./scripts/push-live-preflight.sh --env-file ... --aws` 실행: `checks=39`, `warnings=4`, `failures=0` 통과 확인
- [x] `python3 -m json.tool infra/aws/cloudformation/github-actions-oidc-role.json`
- [x] `bash -n scripts/aws-github-oidc-role.sh scripts/codex-run.sh`
- [x] `./scripts/codex-run.sh aws-github-oidc-role --env-file /tmp/kbo-fans-aws-oidc-check.env --repo godekd3133/kbo-fans --dry-run --update-env-file` 실행: AWS 호출 없이 OIDC provider / role stack 계획 출력 확인
- [x] `bash -n scripts/push-demo-setup-status.sh scripts/push-demo-readiness-audit.sh scripts/codex-run.sh`
- [x] `./scripts/codex-run.sh push-demo-setup-status --env-file /tmp/kbo-fans-setup-status.env --repo godekd3133/kbo-fans --skip-tooling` 실행: env 생성, OIDC dry-run, readiness audit expected attention, 다음 명령 출력 확인
- [x] `./scripts/push-demo-readiness-audit.sh --env-file /tmp/kbo-fans-setup-status.env --repo godekd3133/kbo-fans --skip-tooling --skip-gh` 실행: placeholder AWS 값으로 expected attention, 다음 명령 repo hint 확인
- [x] `backend/.venv/bin/pytest -q backend/tests/test_push_service.py` (16 passed; APNs Live Activity payload contract test와 KBO 경기일 default test 포함)
- [x] `backend/.venv/bin/ruff check --select E,F,I,B backend/src/kbo_fans_backend/api/routes/push.py backend/tests/test_push_service.py`
- [x] `backend/.venv/bin/ruff check --select E,F,I,B backend/tests/test_push_service.py backend/src/kbo_fans_backend/services/apns_live_activity.py backend/src/kbo_fans_backend/schemas/push.py`
- [x] `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/app-build-artifacts.yml")'` workflow YAML parse 통과
- [x] `cd app && fvm flutter test --dart-define=APP_ENV=release --dart-define=PREFER_DIRECT_SCRAPE=true --dart-define=API_BASE_URL=https://demo-api.kbofans.example/api test/data/providers_routing_test.dart` (`API_BASE_URL` override + direct provider routing 유지 확인)
- [x] `plutil -lint app/ios/Runner/Info.plist app/ios/KboFansWidget/Info.plist app/ios/Runner/Runner.entitlements app/ios/KboFansWidgetExtension.entitlements`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter analyze lib/main.dart lib/services/push_notification_service.dart lib/services/live_activity_service.dart test/services/push_notification_service_test.dart test/services/live_activity_service_test.dart`
- [x] `cd app && fvm flutter test test/services/push_notification_service_test.dart test/services/live_activity_service_test.dart`
- [x] `PYTHONPATH=backend/src backend/.venv/bin/python -m kbo_fans_backend.scheduler.push_config_status` (현재 로컬 missing config JSON 출력 확인)
- [x] `bash -n scripts/push-readiness-check.sh scripts/codex-run.sh`
- [x] `ALLOW_INSECURE_PUSH_READINESS=true PUSH_SYNC_SECRET=secret ./scripts/push-readiness-check.sh http://127.0.0.1:8765/api` mock success path 통과
- [x] mock `readyForIphoneOnlyDemo=false` path에서 `push_config=status=fail ... missing=['APNS_USE_SANDBOX=false']`로 실패 확인
- [x] `ALLOW_INSECURE_PUSH_READINESS=true PUSH_SYNC_SECRET=secret API_BASE_URL=http://127.0.0.1:8767/api bash ./scripts/codex-run.sh push-readiness` mock success path 통과
- [x] `PYTHONPATH=backend/src PUSH_REGISTRY_PATH=/tmp/kbo-empty-push-registry.json backend/.venv/bin/python -m kbo_fans_backend.scheduler.live_activity_sync` (`checkedGames: 0`, `updatedGames: []`, `pushedMoments: []`, 빈 registry 안전 종료 확인)
- [x] `git diff --check`
- [ ] `docker build -t kbo-fans-backend:codex-check backend`는 로컬 Docker daemon 미실행으로 검증 불가
- [ ] `./scripts/aws-push-deploy-check.sh` 전체 AWS 리소스 조회는 현재 로컬에 AWS CLI/credential이 없어 미수행. `--skip-aws` 경로로 env/rendered JSON 검증만 확인
- [ ] `cd app && fvm flutter build ios --simulator --debug`는 로컬 CocoaPods 설치 상태가 깨져 pod install 전 단계에서 실패
- [ ] XcodeBuildMCP `build_sim({ extraArgs: ["CODE_SIGNING_ALLOWED=NO"] })`는 120초 제한 초과. 프로세스 확인 결과 `KboFansWidget` asset catalog 처리(`actool`/`ibtoold`)에서 멈춰 수동 종료

---

## 2026-06-04: 0.0.29 릴리즈 문서화와 무결성 감사

### 완료
- [x] 현재 dirty diff가 일정 상태 유지, 우천취소 라벨, 문자중계 포일 분류, 롯데 로고, direct-primary 선수 이미지/한글명 매칭처럼 사용자 동작과 API 계약을 바꾸는 범위임을 확인
- [x] `0.0.29+29` 새 앱 버전으로 판단하고 `app/pubspec.yaml`, `CHANGELOG.md`, 앱 내 `patch_notes.md`, `README.md`, `docs/VERSIONING.md`를 동기화
- [x] 전체 Flutter test 실패 원인을 `LocalAssetPlayerRepository`의 clock injection이 내부 `BootstrapRepository`로 전달되지 않던 문제로 확인하고 동일 clock을 공유하도록 보정
- [x] 변경 backend 파일의 ruff hygiene를 맞춰 현재 변경 범위 lint debt를 제거
- [x] Director가 앞으로도 API를 사용하지 않는 방향으로 진행한다고 결정했으므로, release API health gate / backend API 배포 준비는 현재 앱 완성 판단의 blocker에서 제외

### 검증
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test`
- [x] `backend/.venv/bin/pytest -q backend/tests`
- [x] `python3 -m compileall backend/src`
- [x] `backend/.venv/bin/ruff check --select E,F,I,B backend/src/kbo_fans_backend/crawlers/schedule.py backend/src/kbo_fans_backend/crawlers/relay.py backend/src/kbo_fans_backend/services/schedule.py backend/src/kbo_fans_backend/services/scoreboard.py backend/tests/test_schedule.py backend/tests/test_scoreboard_service.py backend/tests/test_relay_crawler.py`
- [x] `git diff --check`

### 남은 릴리즈 작업
- [ ] Git commit / tag `0.0.29` / GitHub Release 생성은 아직 수행하지 않았다.
- [x] backend 전체 ruff debt는 2026-06-04 `backend 전체 ruff debt 정리`에서 해소되어 `backend/.venv/bin/ruff check --select E,F,I,B backend/src backend/tests` 통과 상태로 갱신됨.

---

## 2026-05-21: 일정 탭 월 이동 상태 초기화 방지

### 완료
- [x] 일정 화면에서 다음 달로 이동한 뒤 선택된 하단 `일정` 탭을 다시 누르면 `ScheduleScreen`이 재생성되어 현재 달로 돌아갈 수 있는 경로 확인
- [x] 월 데이터 로딩/실패 상태에서 전체 일정 본문을 교체하던 구조를 바꿔 캘린더와 월 이동 컨트롤은 유지되도록 수정
- [x] 월 이동 버튼은 `PageView` 전환 완료 시점에 선택 월을 확정하도록 정리해 기존 페이지가 상태를 되돌리는 경로 차단
- [x] 이미 선택된 하단 탭은 다시 `context.go()`를 호출하지 않도록 변경
- [x] no-op이던 헤더 우측 버튼을 오늘 복귀 버튼으로 연결

### 원인
- 선택된 하단 탭도 매번 `context.go('/schedule')`를 호출해 화면 state가 초기값으로 돌아갈 수 있었다.
- 일정 데이터가 실패하면 `PageView`가 사라지는 구조라 월 이동 버튼이 캘린더 상태와 분리될 수 있었다.

### 검증
- [x] `cd app && fvm flutter test test/features/schedule/schedule_screen_test.dart`
- [x] `bash scripts/codex-run-web-static.sh` 후 Playwright 390x844에서 `MAY 2026 → JUN 2026 → 하단 일정 재탭` 시 `JUN 2026` 유지 확인

---

## 2026-05-21: 우천취소 상태 라벨 표시

### 완료
- [x] KBO `Main.asmx/GetKboGameList`가 취소 경기에서 `CANCEL_SC_NM: "우천취소"`를 내려주고, `Schedule.asmx/GetScheduleList` 표 마지막 셀도 `우천취소`를 포함하는 것을 확인
- [x] 백엔드 schedule/scoreboard 경로와 direct-primary schedule/scoreboard 경로에 `statusLabel`을 보존하도록 보강
- [x] Flutter `Game` / `ScheduleGame` 모델, 상태 배지, 홈/상세/일정/위젯 표시에서 `statusLabel`이 있으면 `우천취소`를 우선 표시하도록 정리
- [x] 우천취소 경기에서는 direct schedule enrich가 main list의 `0:0`을 점수처럼 주입하지 않도록 차단
- [x] 기존 `backend/data/snapshots/schedule/2026-05.json`의 2026-05-20 취소 4경기에 `statusLabel: "우천취소"`를 보강해 historical schedule 조회도 같은 라벨을 표시하도록 정리

### 검증
- [x] `backend/.venv/bin/pytest -q backend/tests/test_schedule.py backend/tests/test_scoreboard_service.py`
- [x] `cd app && fvm flutter test test/core/utils/game_status_label_test.dart test/features/schedule/widgets/schedule_game_card_test.dart test/data/kbo_direct_repository_test.dart`
- [x] `cd app && fvm flutter analyze lib/core/utils/game_status_label.dart lib/core/widgets/game_status_badge.dart lib/data/models/game.dart lib/data/models/schedule.dart lib/data/repositories/api_game_repository.dart lib/data/repositories/api_home_repository.dart lib/data/repositories/kbo_direct_repository.dart lib/features/home/widgets/game_card.dart lib/features/home/widgets/my_team_game_card.dart lib/features/schedule/widgets/schedule_game_card.dart lib/features/game_detail/game_detail_screen.dart lib/features/home/home_screen.dart lib/services/live_activity_service.dart lib/services/widget_sync_service.dart test/core/utils/game_status_label_test.dart test/features/schedule/widgets/schedule_game_card_test.dart test/data/kbo_direct_repository_test.dart`
- [x] `python3 -m compileall backend/src/kbo_fans_backend/crawlers/schedule.py backend/src/kbo_fans_backend/services/schedule.py backend/src/kbo_fans_backend/services/scoreboard.py`
- [x] `python3 -m json.tool backend/data/snapshots/schedule/2026-05.json`
- [x] `PYTHONPATH=backend/src backend/.venv/bin/python - <<'PY' ... ScheduleService().get_month_schedule('2026-05') ... PY`
- [x] `git diff --check`

---

## 2026-05-21: 문자중계 포일 표기 보정

### 완료
- [x] backend relay와 direct-primary relay가 `포일` 포함 문구를 별도 이벤트로 분류하지 않아 UI 배지가 `플레이`로 표시되는 경로 확인
- [x] `포일` 문구를 `PASSED_BALL` 이벤트로 분류하고, `득점` / `홈인` 포함 시 득점 장면 상태를 유지하도록 보정
- [x] 문자중계 카드가 득점 장면에서도 `포일` 이벤트 배지를 함께 표시하도록 보정

### 검증
- [x] `cd backend && .venv/bin/python -m pytest tests/test_relay_crawler.py`
- [x] `cd app && fvm dart format lib/data/repositories/kbo_direct_repository.dart lib/features/game_detail/tabs/relay_tab.dart test/data/kbo_direct_repository_test.dart`
- [x] `cd app && fvm flutter analyze lib/data/repositories/kbo_direct_repository.dart lib/features/game_detail/tabs/relay_tab.dart test/data/kbo_direct_repository_test.dart`
- [x] `cd app && fvm flutter test test/data/kbo_direct_repository_test.dart`

---

## 2026-05-21: 롯데 팀 로고 흰 배경 제거

### 완료
- [x] 현재 공통 팀 로고 URL이 `fixed/emblem_${id}_L.png`를 사용하고, 롯데 `emblem_LT_L.png`만 모서리까지 opaque white인 PNG임을 확인
- [x] 같은 CDN의 `fixed/emblem_LT.png`가 투명 배경 PNG임을 확인
- [x] 공통 팀 로고 URL을 `fixed/emblem_$id.png`로 변경해 롯데 흰 배경을 제거하고 다른 팀도 같은 transparent fixed emblem 계열을 사용하도록 정리
- [x] 팀 로고 URL이 `_L.png`로 회귀하지 않도록 테스트 추가

### 검증
- [x] `file /tmp/kbo-logo-check/emblem_LT_L.png /tmp/kbo-logo-check/initial_LT_s.png app/ios/Runner/Assets.xcassets/TeamLogo_LT.imageset/logo.png`
- [x] PNG alpha 분석: `emblem_LT_L.png` corners alpha `255`, `emblem_LT.png` corners alpha `0`
- [x] CDN 확인: `fixed/emblem_{LG,KT,SK,SS,NC,HH,LT,HT,OB,WO}.png` 모두 200 응답
- [x] `cd app && fvm dart format lib/core/constants/team_data.dart test/core/constants/team_data_test.dart`
- [x] `cd app && fvm flutter test test/core/constants/team_data_test.dart`
- [x] `cd app && fvm flutter analyze lib/core/constants/team_data.dart test/core/constants/team_data_test.dart`
- [x] `git diff --check`

---

## 2026-05-21: direct 문자중계 현재 타석 선수 이미지 보정

### 완료
- [x] API를 쓰지 않는 direct-primary 빌드 기준으로 문자중계 현재 타석 이미지가 `LiveTextView2` HTML 이미지 또는 양 팀 선수목록 fallback에만 의존하는 경로 확인
- [x] `Main.asmx/GetKboGameList`의 live current player id(`T_P_ID` / `B_P_ID`)로 현재 타자/상대투수 이미지 URL을 즉시 구성하도록 보강
- [x] `LiveTextView2` 이미지가 비어 있거나 no-image placeholder일 때 main game player id 기반 이미지로 보정
- [x] direct relay summary fallback의 `currentAtBat`도 선수 이름뿐 아니라 `person/middle/{season}/{playerId}.jpg` 이미지 URL을 함께 채우도록 보정
- [x] direct 선수목록이 영문 이름으로 내려와 박스스코어/라인업의 한글 선수명과 매칭되지 않는 경로 확인
- [x] direct 현재 시즌 팀 선수목록 표시 이름을 KBO 한글 엔트리/기록실 이름으로 보정해 박스스코어/라인업 이미지 맵이 한글 경기 원본과 맞도록 보강

### 원인
- direct relay fallback `_currentAtBatFromMainGame()`가 current player id를 쓰지 않고 `batterImageUrl` / `pitcherImageUrl`을 빈 문자열로 반환해, 선수목록 로딩 지연/실패 또는 이름 표기 차이가 있으면 글자 fallback으로 보일 수 있었다.
- direct 팀 선수목록은 `eng.koreabaseball.com` 기반이라 `CHOI Won Jun` 같은 영문명이 key가 됐고, 박스스코어/라인업은 `최원준` 같은 한글명을 key로 찾아 이미지 URL 매칭이 실패했다.

### 검증
- [x] `python3 - <<'PY' ... Main.asmx/GetKboGameList ... PY`
- [x] `python3 - <<'PY' ... eng.koreabaseball.com/Teams/PlayerSearch.aspx ... PY`
- [x] `cd app && fvm dart format lib/data/repositories/kbo_direct_repository.dart lib/data/repositories/kbo_direct_player_repository.dart test/data/kbo_direct_repository_test.dart test/data/kbo_direct_player_repository_test.dart`
- [x] `cd app && fvm flutter analyze lib/data/repositories/kbo_direct_repository.dart lib/data/repositories/kbo_direct_player_repository.dart test/data/kbo_direct_repository_test.dart test/data/kbo_direct_player_repository_test.dart`
- [x] `cd app && fvm flutter test test/data/kbo_direct_repository_test.dart test/data/kbo_direct_player_repository_test.dart`

---

## 2026-05-21: direct KBO source validation and relay fallback guard

### 완료
- [x] 백엔드 API를 쓰지 않는 direct KBO 기준으로 `GetScheduleList` 원본 ASMX 호출을 실측해 2026-05-21 일정 5경기 응답 확인
- [x] `APP_ENV=local`, native, `PREFER_DIRECT_SCRAPE=true`, `API_BASE_URL` 없음 조건에서 앱 provider가 direct repository를 선택하는지 확인
- [x] direct repository smoke로 2026-05-21 5경기 전체 schedule/scoreboard/boxscore/relay/lineup shape를 확인
- [x] 예정 경기에서 direct relay summary fallback이 실제 중계 없이 `1회초/1회말` skeleton 24개를 만들던 문제 확인
- [x] 예정/취소/서스펜디드 경기에서는 direct relay fallback을 빈 상태로 반환하고, 라인스코어가 있는 경기에서만 요약 fallback을 만들도록 보정
- [x] direct records overview, avg/hr/ops/opsPlus/era leaderboard, KT 팀 기록, 리더 선수 상세가 KBO 원본 기준으로 응답되는지 확인

### 검증
- [x] `python3 - <<'PY' ... https://www.koreabaseball.com/ws/Schedule.asmx/GetScheduleList ... PY`
- [x] `cd app && fvm flutter test test/data/providers_routing_test.dart --dart-define=APP_ENV=local --dart-define=PREFER_DIRECT_SCRAPE=true`
- [x] 임시 direct smoke: `cd app && fvm flutter test test/data/direct_kbo_source_smoke_test.dart --dart-define=APP_ENV=local --dart-define=PREFER_DIRECT_SCRAPE=true --reporter expanded`
- [x] direct smoke 확인값: 오늘 5경기 `scheduled`, boxscore `official=false 0/0`, relay `0`, lineup `0/0`
- [x] direct records 확인값: AVG `박성한 0.382`, HR `김도영 13`, OPS `오스틴 1.073`, OPS+ `오스틴 121`, ERA `최민석 2.17`
- [x] direct team/player 확인값: KT 팀 타율 `0.287`, 팀 ERA `4.50`, 박성한 선수상세 `타율 0.382`
- [x] `cd app && fvm dart format lib/data/repositories/kbo_direct_repository.dart test/data/kbo_direct_repository_test.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/data/kbo_direct_repository_test.dart`
- [x] `git diff --check`

---

## 2026-05-20: 0.0.28 current boxscore adjacent fallback guard

### 완료
- [x] `GET /api/game/20260520SKWO0/boxscore`가 요청한 오늘 경기 대신 `20260519SKWO0` 박스스코어를 반환하는 현상 재현
- [x] 원인 확인: boxscore payload가 비어 있으면 같은 팀 조합의 인접 날짜 경기 ID를 재시도하는 fallback이 current/live 경기에도 적용됨
- [x] 오늘/미래 경기에서는 adjacent canonical game id fallback을 타지 않도록 차단
- [x] historical adjacent fallback은 유지하되, 응답 `gameId`는 요청한 game id로 보정하고 `sourceGameId`로 원천 대체 ID를 남기도록 정리
- [x] current game에서는 adjacent fallback을 호출하지 않는 회귀 테스트 추가
- [x] 7357 웹에서 `#/game/20260520SKWO0?tab=boxscore` 확인: 어제 선수 기록 대신 `공식 박스스코어 업데이트 전입니다` 표시
- [x] 기록실 fresh load에서 `records/overview`가 rank 29/30을 rank 1 앞에 내려 앱 validator가 오류 화면을 띄우는 현상 재현
- [x] records overview/leaderboard 서버 응답을 rank 오름차순으로 normalize하고 featured 카드도 정렬 후 1위 기준으로 생성하도록 보정
- [x] records cache 제거 후 7357 웹 `#/records` fresh load 재확인: `박성한 0.379`, `오스틴 0.356`, `최형우 0.354`, `이우성 0.353`, `최원준 0.351` 순으로 표시
- [x] 현재 변경은 LIVE/당일 박스스코어 표시 동작 변경이라 `0.0.28+28` 새 릴리즈로 판단

### 검증
- [x] `backend/.venv/bin/pytest -q backend/tests`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_boxscore_service.py backend/tests/test_games.py`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_records_overview.py backend/tests/test_boxscore_service.py backend/tests/test_games.py`
- [x] `backend/.venv/bin/ruff check --select E,F,I,B backend/src/kbo_fans_backend/services/boxscore.py backend/tests/test_boxscore_service.py`
- [x] `backend/.venv/bin/ruff check --select E,F,I,B backend/src/kbo_fans_backend/services/records_overview.py backend/tests/test_records_overview.py backend/src/kbo_fans_backend/services/boxscore.py backend/tests/test_boxscore_service.py`
- [x] `python3 -m compileall backend/src/kbo_fans_backend/services/records_overview.py backend/src/kbo_fans_backend/services/boxscore.py`
- [x] `cd app && fvm flutter analyze`
- [x] `git diff --check`
- [x] `backend/.venv/bin/python - <<'PY' ... /api/game/20260520SKWO0/boxscore ... PY`
- [x] `backend/.venv/bin/python - <<'PY' ... /api/records/overview?season=2026 ... PY`

---

## 2026-05-20: 0.0.27 live scoreboard score freshness guard

### 완료
- [x] 라이브 상태와 이닝은 KBO main list에서 갱신되지만, schedule/detail fallback의 `0` 점수가 이미 있으면 main list 실제 점수로 덮이지 않는 구조 확인
- [x] `ScoreboardService._merge_main_game_scores`가 KBO main list의 유효한 점수를 schedule fallback 점수보다 우선하도록 보정
- [x] `/scoreboard/home` 경량 경로에서 detail crawler/View1이 실패하고 schedule 점수가 0:0이어도 LIVE main score를 표시하는 회귀 테스트 추가
- [x] 실제 2026-05-20 홈 경량 스코어보드 호출을 수행해 현재 취소/예정 경기의 0점은 정상 상태임을 분리 확인
- [x] 현재 변경은 LIVE 홈/위젯 score API 동작 변경이라 `0.0.27+27` 새 릴리즈로 판단

### 검증
- [x] `backend/.venv/bin/pytest -q backend/tests/test_scoreboard_service_live_fallback.py backend/tests/test_scoreboard_service_cache.py`
- [x] `backend/.venv/bin/ruff check --select E,F,I,B backend/src/kbo_fans_backend/services/scoreboard.py backend/tests/test_scoreboard_service_live_fallback.py`
- [x] `backend/.venv/bin/python - <<'PY' ... ScoreboardService().get_home_scoreboard(date.today().isoformat()) ... PY`
- [x] `cd app && fvm flutter analyze`
- [x] `backend/.venv/bin/pytest -q backend/tests`
- [x] `python3 -m compileall backend/src`
- [x] `git diff --check`

### 릴리즈 주의
- [ ] `RELEASE_API_HEALTH_TIMEOUT_SECONDS=3 ./scripts/codex-run.sh release-api-health` 실패: 현재 로컬 DNS가 `api.kbofans.com`을 해석하지 못함
- [x] 기존 `push.py` / `test_push_service.py` import sort 이슈 포함 backend ruff debt는 2026-06-04 `backend 전체 ruff debt 정리`에서 해소됨.

---

## 2026-05-20: 0.0.26 home first paint cache sharing

### 완료
- [x] `/scoreboard/home`과 `/home`이 별도 `ScoreboardService` 인스턴스를 써 같은 날짜 schedule/main list 조회를 중복 수행할 수 있던 route-level 구조 확인
- [x] `api/runtime_services.py`에 current data route 공용 singleton을 만들고 scoreboard/home/schedule/standings/records/game routes가 이를 공유하도록 정리
- [x] `/home`은 `/scoreboard/home`과 같은 `ScoreboardService` TTL cache를 재사용하고, game detail relay도 같은 scoreboard service를 사용
- [x] route service 공유 관계 회귀 테스트 추가
- [x] 홈 화면이 scoreboard 첫 데이터 프레임 전부터 `homeAggregateProvider`를 watch하던 구조를 확인하고, secondary section 활성화 이후에만 `/home` aggregate provider를 구독하도록 변경
- [x] 홈 로딩 스켈레톤의 82px 카드 내부 간격이 모바일/테스트 뷰포트에서 overflow 되던 문제 보정
- [x] secondary `/home` provider가 scoreboard paint 이후에 시작되는 widget test 추가
- [x] 홈 자동 refresh timer가 build마다 cancel/restart 되던 구조를 확인하고, refresh interval + scoreboard signature가 바뀔 때만 재스케줄하도록 안정화
- [x] 현재 변경은 앱 첫 화면 동작과 backend current data route cache 재사용 정책 변경이라 `0.0.26+26` 새 릴리즈로 판단

### 검증
- [x] `cd app && fvm dart format lib/features/home/home_screen.dart test/features/home/home_screen_test.dart`
- [x] `cd app && fvm flutter test test/features/home/home_screen_test.dart -r expanded`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_home.py backend/tests/test_scoreboard_service_cache.py backend/tests/test_scoreboard_service_live_fallback.py`
- [x] `backend/.venv/bin/ruff check --select E,F,I,B backend/src/kbo_fans_backend/api/runtime_services.py backend/src/kbo_fans_backend/api/routes/home.py backend/src/kbo_fans_backend/api/routes/scoreboard.py backend/src/kbo_fans_backend/api/routes/schedule.py backend/src/kbo_fans_backend/api/routes/standings.py backend/src/kbo_fans_backend/api/routes/records.py backend/src/kbo_fans_backend/api/routes/games.py backend/tests/test_home.py`
- [x] `python3 -m compileall backend/src/kbo_fans_backend/api`
- [x] `backend/.venv/bin/pytest -q backend/tests`
- [x] `backend/.venv/bin/ruff check --select E,F,I,B backend/src/kbo_fans_backend/api backend/tests/test_home.py`
- [x] `python3 -m compileall backend/src`
- [x] `git diff --check`

### 릴리즈 주의
- [ ] `RELEASE_API_HEALTH_TIMEOUT_SECONDS=3 ./scripts/codex-run.sh release-api-health` 실패: 현재 로컬 DNS가 `api.kbofans.com`을 해석하지 못함

---

## 2026-05-20: 0.0.25 missing team totals display guard

### 완료
- [x] 현재 변경은 앱 스코어/중계/홈 카드 표시 동작 변경이라 `0.0.25+25` 새 릴리즈로 판단
- [x] `TeamScore`에 H/E/B 통계 존재 여부를 나타내는 `hasStats` 플래그 추가
- [x] API parser가 `hits`, `errors`, `balls`가 실제 int로 내려온 경우에만 팀 통계가 있다고 판단하도록 보정
- [x] 스코어 탭과 문자중계 요약은 통계가 없으면 `0` 대신 `-`를 표시
- [x] 홈 마이팀 경기 카드는 양 팀 H/E/B 통계가 없으면 안타/실책/볼넷 요약 행을 숨김
- [x] KBO 브리프의 `안타 공방` 후보는 통계가 확인된 경기만 사용하도록 보정
- [x] API parser, 홈 마이팀 카드, local KBO brief 회귀 테스트 추가
- [x] `CHANGELOG.md`, 앱 내 patch notes, `docs/VERSIONING.md`, `docs/APP_SPEC.md`, `README.md` 갱신

### 검증
- [x] `cd app && fvm dart format lib/data/models/game.dart lib/data/models/home_aggregate.dart lib/data/repositories/api_game_repository.dart lib/features/game_detail/tabs/relay_tab.dart lib/features/game_detail/tabs/score_tab.dart lib/features/home/widgets/my_team_game_card.dart test/data/api_client_test.dart test/data/models/home_aggregate_test.dart test/features/home/widgets/my_team_game_card_test.dart`
- [x] `cd app && fvm flutter test test/data/api_client_test.dart test/data/models/home_aggregate_test.dart -r expanded`
- [x] `cd app && fvm flutter test test/data/api_client_test.dart test/features/home/widgets/my_team_game_card_test.dart test/data/models/home_aggregate_test.dart`
- [x] `cd app && fvm flutter test test/widget_test.dart test/data/api_client_test.dart test/data/models/home_aggregate_test.dart test/data/bootstrap_repository_test.dart -r expanded`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test`
- [x] `git diff --check`
- [x] `RELEASE_API_HEALTH_TIMEOUT_SECONDS=3 ./scripts/codex-run.sh release-api-health` 실패 확인: `DNS lookup failed for api.kbofans.com`

---

## 2026-05-20: 0.0.24 home scoreboard lightweight API split

### 완료
- [x] 현재 변경은 홈/위젯 스코어보드 API fan-out 감소와 동작 범위 분리라 `0.0.24+24` 새 릴리즈로 판단
- [x] backend `/scoreboard/home`이 전체 `/scoreboard`를 호출해 경기별 상세 스코어보드 크롤러를 타던 구조를 분리
- [x] 홈 스코어보드는 schedule + main list 기반 요약 payload만 만들고, full scoreboard/detail 경로만 경기 상세 크롤러를 유지
- [x] `/scoreboard/compact`도 선택 경기 하나의 요약 payload만 만들도록 변경하고 partial game snapshot 저장은 하지 않게 정리
- [x] 과거 날짜 홈/compact 조회는 기존 scoreboard snapshot 우선 정책 유지
- [x] current 홈 스코어보드 원천 실패가 fresh snapshot으로 정상 응답을 만들지 않는 회귀 테스트 추가
- [x] 홈/compact 경로가 per-game detail crawler를 호출하지 않는 회귀 테스트 추가
- [x] runtime data 정책 문서, README, APP_SPEC, CHANGELOG, 앱 내 patch notes, `docs/VERSIONING.md`를 lightweight scoreboard 기준으로 동기화

### 검증
- [x] `backend/.venv/bin/pytest -q backend/tests/test_scoreboard_service_cache.py backend/tests/test_scoreboard_service_live_fallback.py`
- [x] `backend/.venv/bin/pytest -q backend/tests`
- [x] `backend/.venv/bin/ruff check --select E,F,I,B backend/src/kbo_fans_backend/services/scoreboard.py backend/tests/test_scoreboard_service_cache.py backend/tests/test_scoreboard_service_live_fallback.py`
- [x] `cd app && fvm flutter test test/data/bootstrap_repository_test.dart -r expanded`
- [x] `python3 -m compileall backend/src/kbo_fans_backend/services/scoreboard.py`
- [x] `git diff --check`
- [x] `RELEASE_API_HEALTH_TIMEOUT_SECONDS=3 ./scripts/codex-run.sh release-api-health` 실패 확인: `DNS lookup failed for api.kbofans.com`

---

## 2026-05-20: scoreboard snapshot fallback dead-code cleanup

### 완료
- [x] `ScoreboardService` current snapshot fallback 차단 이후 남은 `snapshot_record` 전달 인자와 미사용 terminal snapshot helper 제거
- [x] scoreboard snapshot payload 조회를 `JsonSnapshotStore.load_payload`로 단순화
- [x] 동작 변경 없는 내부 정리라 새 버전은 만들지 않고 main cleanup 커밋으로 처리

### 검증
- [x] `backend/.venv/bin/pytest -q backend/tests/test_scoreboard_service_cache.py backend/tests/test_snapshot_services.py`
- [x] `backend/.venv/bin/ruff check --select E,F,I,B backend/src/kbo_fans_backend/services/scoreboard.py backend/tests/test_scoreboard_service_cache.py backend/tests/test_snapshot_services.py`
- [x] `git diff --check`

---

## 2026-05-20: 0.0.23 backend current team/player snapshot failure guard

### 완료
- [x] 현재 변경은 backend 현재 시즌 팀/선수 기록 실패 masking 정책 변경이라 `0.0.23+23` 새 릴리즈로 판단
- [x] backend `PlayerStatsService` 현재 시즌 팀 선수와 선수 상세이 crawler 실패 시 stale cache 또는 저장 snapshot으로 정상 응답을 만들 수 있던 경로 차단
- [x] backend `TeamStatsService` 현재 시즌 팀 스탯이 crawler 실패 시 stale cache 또는 저장 snapshot으로 정상 응답을 만들 수 있던 경로 차단
- [x] 과거 시즌 팀 선수/팀 스탯/선수 상세 snapshot 우선 및 실패 fallback 정책은 유지
- [x] 현재 시즌 fresh snapshot까지 거부하는 회귀 테스트 추가
- [x] runtime data 정책 문서, README, APP_SPEC, AGENTS, CLAUDE, repo skill, CHANGELOG, 앱 내 patch notes, `docs/VERSIONING.md`를 현재 fail-visible 기준으로 동기화

### 검증
- [x] `backend/.venv/bin/pytest -q backend/tests/test_snapshot_services.py`
- [x] `backend/.venv/bin/pytest -q backend/tests`
- [x] `backend/.venv/bin/ruff check --select E,F,I,B backend/src/kbo_fans_backend/services/player_stats.py backend/src/kbo_fans_backend/services/team_stats.py backend/tests/test_snapshot_services.py`
- [x] `cd app && fvm flutter test test/data/bootstrap_repository_test.dart -r expanded`
- [x] `git diff --check`
- [x] `RELEASE_API_HEALTH_TIMEOUT_SECONDS=3 ./scripts/codex-run.sh release-api-health` 실패 확인: `DNS lookup failed for api.kbofans.com`

---

## 2026-05-20: 0.0.22 current data API cache failure guard

### 완료
- [x] 현재 변경은 현재 날짜/월/시즌 데이터의 API cache 실패 fallback 정책 변경이라 `0.0.22+22` 새 릴리즈로 판단
- [x] `ApiClient.getCached`에 `allowCacheOnFailure` 옵션을 추가해 fresh local API cache reuse를 호출부별로 분리
- [x] `allowCacheOnFailure` 기본값을 false 로 두고 historical 호출부만 명시적으로 true 가 되게 해 새 API 호출부의 기본 동작이 fail-visible 이 되도록 보정
- [x] 현재 날짜 스코어보드, compact scoreboard, 홈 aggregate, 경기 상세, 하이라이트, 문자중계, 박스스코어, 라인업, 현재 월 일정, 현재 시즌 순위/기록실/팀 기록은 API 실패 시 local API cache를 정상 데이터처럼 반환하지 않도록 보정
- [x] backend 현재 스코어보드, 일정, 순위, 기록실 요약, 리더보드도 crawler 실패 시 fresh snapshot fallback을 반환하지 않도록 보정하고 회귀 테스트 갱신
- [x] 홈 화면의 `home_scoreboard_cache_*` 로딩 중 선표시 경로를 제거해 오늘 스코어보드가 stale 로컬 cache로 먼저 보이지 않도록 정리
- [x] 과거 날짜/시즌/월 조회는 기존 cached-first 또는 snapshot fallback 정책을 유지
- [x] 2026-05-20 취소 경기 4건과 현재 순위/기록실 snapshot 저장 시각을 최신 수집본 기준으로 갱신
- [x] fresh API cache가 있어도 현재 스코어보드/순위/기록실/리더보드 API 실패를 가리지 않는 회귀 테스트 추가
- [x] `README.md`, `CHANGELOG.md`, 앱 내 `patch_notes.md`, `docs/VERSIONING.md`, `docs/APP_SPEC.md`, `AGENTS.md`, `CLAUDE.md`, `.claude/skills/kbo-runtime-data/SKILL.md` 갱신

### 검증
- [x] `cd app && fvm dart format lib/data/api/api_client.dart lib/data/repositories/api_game_repository.dart lib/data/repositories/api_home_repository.dart lib/data/repositories/api_player_repository.dart lib/features/home/home_screen.dart test/data/api_client_test.dart`
- [x] `cd app && fvm flutter test test/data/api_client_test.dart -r expanded`
- [x] `cd app && fvm flutter test test/data/api_client_test.dart test/widget_test.dart -r expanded`
- [x] `cd app && fvm flutter test test/widget_test.dart test/data/api_client_test.dart test/data/device_snapshot_player_repository_test.dart test/data/models/records_overview_test.dart test/data/bootstrap_repository_test.dart -r expanded`
- [x] `cd app && fvm flutter analyze`
- [x] `backend/.venv/bin/pytest -q backend/tests`
- [x] `backend/.venv/bin/ruff check --select E,F,I,B backend/src/kbo_fans_backend/services/records_overview.py backend/src/kbo_fans_backend/services/schedule.py backend/src/kbo_fans_backend/services/scoreboard.py backend/src/kbo_fans_backend/services/standings.py backend/tests/test_records_overview.py backend/tests/test_schedule.py backend/tests/test_scoreboard_service_cache.py backend/tests/test_snapshot_services.py`
- [x] `python3 -m json.tool backend/data/snapshots/schedule/2026-05.json >/dev/null`
- [x] `python3 -m json.tool backend/data/snapshots/standings_latest/2026.json >/dev/null`
- [x] `python3 -m json.tool backend/data/snapshots/records_overview/2026.json >/dev/null`
- [x] `git diff --check`
- [x] `RELEASE_API_HEALTH_TIMEOUT_SECONDS=3 ./scripts/codex-run.sh release-api-health` 실패 확인: `DNS lookup failed for api.kbofans.com`
- [x] `rg -n "home_scoreboard_cache|home-cache|_cachedToday" app/lib docs README.md AGENTS.md CLAUDE.md .claude/skills/kbo-runtime-data/SKILL.md CHANGELOG.md app/assets/bootstrap/patch_notes.md`
- [x] `./scripts/codex-run.sh web-static` 로 새 web release build를 `http://localhost:7357`에 재기동
- [x] seeded fake current cache + production API DNS 실패 조건에서 records/home/schedule/standings/game detail 화면이 fake cache를 표시하지 않고 오류 상태를 노출하는지 Chrome headless screenshot으로 확인
  - `artifacts/current-data-cache-guard/records-seeded-cache-dns-fail-reload.png`
  - `artifacts/current-data-cache-guard/home-seeded-cache-dns-fail-reload.png`
  - `artifacts/current-data-cache-guard/schedule-seeded-cache-dns-fail.png`
  - `artifacts/current-data-cache-guard/standings-seeded-cache-dns-fail.png`
  - `artifacts/current-data-cache-guard/game-seeded-cache-dns-fail.png`

---

## 2026-05-20: GitHub Actions backend test gate

### 완료
- [x] `app-build-artifacts` workflow에 `backend_tests` job 추가
- [x] backend job에서 Python 3.11, pip cache, `python -m pip install -e ".[dev]"`, `python -m pytest -q` 순서로 backend 테스트 실행
- [x] `prepare` job이 `backend_tests`를 `needs`로 기다리게 해 backend 테스트 실패 시 Android/Web/iOS 빌드 job이 시작되지 않도록 변경

### 검증
- [x] `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/app-build-artifacts.yml"); puts "yaml ok"'`
- [x] `backend/.venv/bin/pytest -q backend/tests`

---

## 2026-05-20: 0.0.21 records API cache and error surface

### 완료
- [x] 현재 변경은 앱 API cache reuse 정책, 기록실 오류 UI, 전역 provider retry 정책 변경이라 `0.0.21+21` 새 릴리즈로 판단
- [x] 웹 화면 QA에서 2013 시즌 기록실이 백엔드 정상 응답에도 구형 브라우저 캐시 때문에 `2, 9, 13...` 순위로 재노출되는 문제 확인
- [x] `ApiPlayerRepository` records overview cache key를 `v4`, leaderboard cache key를 `v3`로 올려 웹 `api_cache` 오염 캐시를 강제 무효화
- [x] `ApiClient.getCached`에 validator를 추가해 invalid cache read, invalid fresh write, invalid silent refresh write를 차단
- [x] records overview / leaderboard API cache는 핵심 리더보드 첫 항목이 1위일 때만 저장/재사용하도록 보강
- [x] 2013 타율 리더보드 backend snapshot을 추가하고 records overview featured 카드를 시즌 공식 리더 기준으로 보강
- [x] 기록실 리그 요약 실패가 빈 공간으로 숨겨지지 않고 오류 카드와 다시 시도 버튼으로 보이도록 보강
- [x] 팀 기록실 오류 상태에 사용자용 실패 문구를 표시하고 refresh 실패는 Dev Console에 기록하도록 정리
- [x] 앱 전역 Provider retry를 비활성화해 API 실패가 자동 재시도 뒤에 숨지 않도록 변경
- [x] invalid API cache, historical rank gap, records screen error card 회귀 테스트 추가

### 검증
- [x] `cd app && fvm dart format lib/main.dart lib/data/api/api_client.dart lib/data/repositories/api_player_repository.dart lib/features/records/records_screen.dart test/data/api_client_test.dart test/widget_test.dart`
- [x] `cd app && fvm flutter test test/data/api_client_test.dart test/widget_test.dart -r expanded`
- [x] `cd app && fvm flutter analyze`
- [x] `python3 -m json.tool backend/data/snapshots/leaderboard/2013_avg.json >/dev/null`
- [x] `python3 -m json.tool backend/data/snapshots/records_overview/2013.json >/dev/null`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_records_overview.py`
- [x] `RELEASE_API_HEALTH_TIMEOUT_SECONDS=3 ./scripts/release-api-health-check.sh` 실패 확인: `DNS lookup failed for api.kbofans.com`

---

## 2026-05-20: 0.0.20 home aggregate failure guard

### 완료
- [x] 현재 변경은 backend `/home` API의 current/future failure masking 정책 변경이라 `0.0.20+20` 새 릴리즈로 판단
- [x] 현재/미래 날짜 `/home` aggregate 에서 schedule / standings / records overview 하위 호출 실패를 빈 섹션/placeholder 로 대체하지 않고 실패를 전파하도록 변경
- [x] 과거 날짜 `/home` aggregate 는 기존 partial fallback 을 유지해 히스토리 조회 안정성은 보존
- [x] 실패 masking 회귀 테스트 추가: current/future schedule, standings, records overview 실패 각각 검증
- [x] historical home partial fallback 유지 테스트 추가
- [x] records overview crawler 와 2011 snapshot 의 featured 카드가 canonical 시즌 리더를 보도록 정리하고 회귀 테스트 추가
- [x] records overview / leaderboard device snapshot 이 1위부터 시작하는 리더보드일 때만 저장/재사용되도록 보정하고 snapshot version 을 `v3`로 갱신
- [x] `README.md`, `CHANGELOG.md`, 앱 내 `patch_notes.md`, `docs/VERSIONING.md`, `docs/APP_SPEC.md`, `AGENTS.md`, `CLAUDE.md`, `.claude/skills/kbo-runtime-data/SKILL.md` 갱신

### 검증
- [x] `backend/.venv/bin/pytest -q backend/tests/test_home.py`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_records_overview.py`
- [x] `python3 -m compileall backend/src/kbo_fans_backend/services/home.py backend/src/kbo_fans_backend/crawlers/records_overview.py`
- [x] `python3 -m json.tool backend/data/snapshots/records_overview/2011.json >/dev/null`
- [x] `cd app && fvm dart format lib/data/repositories/device_snapshot_player_repository.dart test/data/device_snapshot_player_repository_test.dart`
- [x] `cd app && fvm flutter test test/data/device_snapshot_player_repository_test.dart -r expanded`
- [x] `backend/.venv/bin/pytest -q backend/tests`
- [x] `backend/.venv/bin/ruff check --select E,F,I,B backend/src/kbo_fans_backend/services/home.py backend/src/kbo_fans_backend/crawlers/records_overview.py backend/tests/test_home.py backend/tests/test_records_overview.py`
- [x] `python3 -m compileall backend/src/kbo_fans_backend`
- [x] `cd app && fvm flutter analyze`
- [x] `RELEASE_API_HEALTH_TIMEOUT_SECONDS=3 ./scripts/codex-run.sh web` 실패 확인: `DNS lookup failed for api.kbofans.com`

---

## 2026-05-20: 0.0.19 release web command guard

### 완료
- [x] 현재 변경은 backend current/live 데이터 실패 masking 차단과 release-facing 실행 명령의 실제 동작 변경이라 `0.0.19+19` 새 릴리즈로 판단
- [x] 현재/진행 예정 경기의 박스스코어와 라인업은 과거 snapshot을 실패 fallback으로 쓰지 않도록 제한
- [x] LIVE 경기 문자중계는 crawler 실패 시 요약/과거 snapshot으로 정상처럼 보이지 않고 실패를 전파하도록 제한
- [x] 팀 기록 API는 선수 목록/팀 스탯 중 한쪽 실패를 빈 payload로 숨기지 않고 실패를 전파하도록 정리
- [x] `./scripts/codex-run.sh web` 기본 실행을 release API health gate를 통과한 static web release 경로로 변경
- [x] Chrome debug 세션은 `./scripts/codex-run.sh web-dev`와 `scripts/codex-run-web-dev.sh`로 분리
- [x] `README.md`, `CHANGELOG.md`, 앱 내 `patch_notes.md`, `docs/VERSIONING.md`, `docs/APP_SPEC.md`를 current/live failure masking guard와 web 기본 실행/web-dev 분리 기준으로 갱신

### 검증
- [x] `backend/.venv/bin/pytest -q backend/tests/test_boxscore_service.py backend/tests/test_lineup.py backend/tests/test_relay_service.py backend/tests/test_teams.py`
- [x] `python3 -m compileall backend/src/kbo_fans_backend`
- [x] `bash -n scripts/codex-run.sh scripts/codex-run-web-dev.sh scripts/codex-run-web.sh scripts/codex-run-web-release.sh`
- [x] `./scripts/codex-run.sh web` 실패 확인: `DNS lookup failed for api.kbofans.com`
- [x] `./scripts/codex-run.sh web-dev`는 명령 라우팅 문법 검증 대상으로 분리

---

## 2026-05-20: 0.0.18 historical leaderboard snapshot 보강

### 완료
- [x] 현재 변경은 backend historical leaderboard fallback 데이터가 추가되는 사용자 영향 변경이라 `0.0.18+18` 새 릴리즈로 판단
- [x] `backend/data/snapshots/leaderboard/2011_era.json` 추가: 2011 ERA 리더보드가 `윤석민 2.45`부터 은퇴 선수 포함 순위로 복구
- [x] `backend/data/snapshots/leaderboard/2013_hr.json` 추가: 2013 홈런 리더보드가 `박병호 37`부터 은퇴 선수 포함 순위로 복구
- [x] backend 회귀 테스트로 두 snapshot의 1위 선수/값/은퇴 플래그를 고정
- [x] `scripts/codex-run-web.sh`를 release API health gate 경로로 맞춤
- [x] `scripts/codex-run-web-release.sh`, `scripts/codex-run-android-release.sh` wrapper 추가
- [x] `0.0.18` 기준 `pubspec.yaml`, `CHANGELOG.md`, 앱 내 `patch_notes.md`, `docs/VERSIONING.md`, `README.md`, `docs/DISTRIBUTION_GUIDE.md`, `docs/CODEX_ANDROID_ENV.md` 갱신

### 검증
- [x] `python3 -m json.tool backend/data/snapshots/leaderboard/2011_era.json >/dev/null`
- [x] `python3 -m json.tool backend/data/snapshots/leaderboard/2013_hr.json >/dev/null`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_records_overview.py`
- [x] `bash -n scripts/codex-run-web.sh scripts/codex-run-web-release.sh scripts/codex-run-android-release.sh`
- [x] `./scripts/codex-run.sh web-release` 실패 확인: `DNS lookup failed for api.kbofans.com`
- [x] `./scripts/codex-run-web.sh` 실패 확인: `DNS lookup failed for api.kbofans.com`
- [x] `./scripts/codex-run-android-release.sh` 실패 확인: `DNS lookup failed for api.kbofans.com`

---

## 2026-05-20: 0.0.17 direct KBO routing guard

### 완료
- [x] 현재 변경은 앱 provider/widget background 라우팅 동작이 바뀌는 규모라 `0.0.17+17` 새 릴리즈로 판단
- [x] `gameRepositoryProvider`, `homeAggregateProvider`, `playerRepositoryProvider`, `WidgetSyncService`가 `preferDirectScrape` 원시 flag 대신 `shouldPreferLocalNativeData` gate를 사용하도록 통일
- [x] direct KBO는 `APP_ENV=local`, native runtime, `API_BASE_URL` override 없음, `PREFER_DIRECT_SCRAPE=true` 조건이 모두 맞을 때만 허용
- [x] records overview device snapshot은 AVG/HR/OPS/ERA가 모두 있는 완성본만 저장/재사용하도록 보정
- [x] normal API-backed 앱 모드에서는 현재 시즌 standings / records overview / leaderboard API 실패를 앱 번들 bootstrap fallback으로 가리지 않도록 보정
- [x] `android-release`, `web-release` 실행 경로를 추가해 local backend 없이 release API health gate를 통과한 URL만 주입하도록 보강
- [x] 현재 기본 운영 API `https://api.kbofans.com/api`는 이 머신에서 DNS 해석 실패를 확인했고, release health gate가 실행/빌드를 시작하기 전에 실패 처리하는 것을 확인
- [x] 일반 API-backed 앱 모드에서 현재 시즌 standings / records overview / leaderboard API 실패를 앱 번들 bootstrap으로 대체하지 않도록 차단
- [x] native 일반 API 모드의 player repository를 API-only로 정리해 local asset fallback이 current 기록실을 조용히 채우지 않도록 보정
- [x] provider routing 테스트를 갱신해 direct-primary가 일반 API override/web/release 경로로 새지 않도록 검증
- [x] `0.0.17` 기준 `pubspec.yaml`, `CHANGELOG.md`, 앱 내 `patch_notes.md`, `docs/VERSIONING.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `.claude/skills/kbo-runtime-data/SKILL.md` 갱신

### 검증
- [x] `cd app && fvm dart format lib/data/providers.dart lib/services/widget_sync_service.dart test/data/providers_routing_test.dart`
- [x] `cd app && fvm dart format lib/data/repositories/device_snapshot_player_repository.dart test/data/device_snapshot_player_repository_test.dart lib/data/providers.dart lib/services/widget_sync_service.dart test/data/providers_routing_test.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/data/device_snapshot_player_repository_test.dart test/data/providers_routing_test.dart -r expanded`
- [x] `cd app && fvm flutter test test/data/api_client_test.dart test/data/providers_routing_test.dart -r expanded`
- [x] `cd app && fvm flutter test test/data/providers_routing_test.dart -r expanded`
- [x] `cd app && fvm flutter test --dart-define=PREFER_DIRECT_SCRAPE=true test/data/providers_routing_test.dart -r expanded`
- [x] `cd app && fvm flutter test --dart-define=APP_ENV=release --dart-define=PREFER_DIRECT_SCRAPE=true test/data/providers_routing_test.dart -r expanded`
- [x] `cd app && fvm flutter test test/data/api_client_test.dart test/data/providers_routing_test.dart -r expanded`
- [x] `bash -n scripts/codex-run.sh scripts/release-api-health-check.sh`
- [x] `./scripts/codex-run.sh release-api-health` 실패 확인: `DNS lookup failed for api.kbofans.com`
- [x] `./scripts/codex-run.sh web-release` 도 build 전에 release API health gate DNS 실패로 중단 확인

---

## 2026-05-20: 0.0.16 backend current-season snapshot 신선도 보강

### 완료
- [x] 현재 변경은 backend fallback 동작이 바뀌는 규모라 `0.0.16+16` 새 릴리즈로 판단
- [x] `ScoreboardService`가 current-date crawler 실패 시 6시간 이내 terminal scoreboard snapshot만 fallback으로 사용하도록 보정
- [x] `StandingsService`가 current-season crawler 실패 시 6시간 이내 `standings_latest` snapshot만 fallback으로 사용하도록 보정
- [x] `ScheduleService`가 current-month crawler 실패 시 6시간 이내 schedule snapshot만 fallback으로 사용하도록 보정
- [x] `RecordsOverviewService`가 current-season overview/leaderboard crawler 실패 시 6시간 이내 snapshot만 fallback으로 사용하도록 보정
- [x] `ScoreboardService`가 current-day scoreboard/compact crawler 실패 시 fresh + terminal snapshot만 fallback으로 사용하고, 오래된 non-terminal snapshot은 거부하도록 보정
- [x] historical date/season/month stale cache와 저장 snapshot fallback은 기존처럼 유지
- [x] 앱 기록실 선수/리더 모델과 API/local/device snapshot 직렬화에서 `isRetired` 플래그 보존
- [x] 앱 API cache 분기에서 cached-first historical 경로와 fresh-first current 경로를 분리하고, fresh-first 원격 실패 시 TTL이 지난 cache를 반환하지 않도록 보정
- [x] 현재 시즌 records overview 번들 fallback도 `generatedAt` 6시간 신선도 기준으로 제한
- [x] 홈 오늘 스코어보드 임시 cache를 `savedAt` envelope 로 저장하고 live/scheduled/terminal 상태별 TTL 안에서만 로딩 대체 UI로 표시
- [x] 현재 시즌 팀 선수 API 요청은 historical season과 달리 오래된 cache 우선 표시를 하지 않고 원격 최신값을 먼저 시도하도록 보정
- [x] `AGENTS.md`, `CLAUDE.md`, `.claude/skills/kbo-runtime-data/SKILL.md`, `docs/APP_SPEC.md`, `README.md`, `docs/VERSIONING.md`, `CHANGELOG.md`, 앱 내 `patch_notes.md`를 `0.0.16` 기준으로 갱신

### 검증
- [x] `python3 -m compileall backend/src`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_records_overview.py backend/tests/test_snapshot_services.py backend/tests/test_schedule.py backend/tests/test_scoreboard_service_cache.py`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_scoreboard_service_cache.py backend/tests/test_scoreboard_service_live_fallback.py backend/tests/test_records_overview.py backend/tests/test_snapshot_services.py backend/tests/test_schedule.py`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_records_overview.py`
- [x] local API 실측: `/api/scoreboard/home` 0.306s, `/api/schedule?month=2026-05` 0.263s, `/api/standings?season=2026` 0.065s, `/api/records/overview?season=2026` 0.652s
- [x] local API 값 확인: 2026-05-20 현재 18:30 예정 5경기는 점수 `None`, 순위 상위 `SS/KT 25-17-1 .595`, 기록 리더 `박성한 .379`, `김도영 13`
- [x] `cd app && fvm dart format lib/data/models/player.dart lib/data/models/records_overview.dart lib/data/repositories/api_player_repository.dart lib/data/repositories/device_snapshot_player_repository.dart lib/data/repositories/local_asset_player_repository.dart`
- [x] `cd app && fvm dart format lib/data/api/api_client.dart lib/data/repositories/api_player_repository.dart lib/data/bootstrap/bootstrap_repository.dart lib/features/home/home_screen.dart test/data/api_client_test.dart test/data/bootstrap_repository_test.dart`
- [x] `cd app && fvm flutter test test/data/api_client_test.dart test/data/bootstrap_repository_test.dart -r expanded`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/data/local_asset_player_repository_test.dart test/data/device_snapshot_player_repository_test.dart -r expanded`
- [x] `cd app && fvm flutter test test/data/models/records_overview_test.dart -r expanded`
- [x] `python3 -m py_compile scripts/generate_bootstrap_snapshots.py`
- [x] `cd app && fvm flutter test test/data/api_client_test.dart test/data/bootstrap_repository_test.dart test/data/local_asset_player_repository_test.dart test/data/device_snapshot_player_repository_test.dart test/data/models/records_overview_test.dart -r expanded`

---

## 2026-05-20: 0.0.15 순위 bootstrap 및 웹 local API 기본값 정리

### 완료
- [x] 현재 변경은 순위 fallback, 웹 API 기본값, 앱 번들 데이터가 바뀌는 규모라 `0.0.15+15` 새 릴리즈로 판단
- [x] `BootstrapRepository.loadStandings`를 exact-season-only + current-season `generatedAt` 6시간 신선도 정책으로 보정
- [x] `app/assets/bootstrap/standings.json`을 backend 2026 최신 snapshot 기준으로 재생성하고, 검증되지 않은 2001~2025 순위는 빈 exact snapshot 으로 정리
- [x] `scripts/generate_bootstrap_snapshots.py`가 live API를 시즌별 반복 호출하지 않고 backend snapshot에서 standings/records bootstrap을 생성하도록 변경
- [x] 웹 `APP_ENV=local` 빌드가 명시적 `API_BASE_URL` 없이 `localhost:8000`을 기본 API로 보지 않도록 `AppConfig`의 local API 기본값을 platform-specific 파일로 분리
- [x] 웹 local 기본값은 운영 API(`https://api.kbofans.com/api`)로 고정하고, 네이티브 local 기본값은 기존 `localhost` / Android emulator `10.0.2.2` 정책 유지
- [x] 2009~2013, 2020 기록실 요약 backend snapshot을 실제 시즌 리더 데이터로 보강
- [x] KT 2026 팀 선수/팀 스탯 번들 snapshot을 최신 backend snapshot 기준으로 갱신
- [x] `AGENTS.md`, `CLAUDE.md`, `.claude/skills/`, `docs/APP_SPEC.md`, `README.md`, `docs/VERSIONING.md`, `CHANGELOG.md`, 앱 내 `patch_notes.md`를 `0.0.15` 기준으로 갱신

### 검증
- [x] `python3 -m py_compile scripts/generate_bootstrap_snapshots.py`
- [x] `python3 -m json.tool app/assets/bootstrap/standings.json >/dev/null`
- [x] `python3 -m json.tool app/assets/bootstrap/records_overview.json >/dev/null`
- [x] `python3 -m json.tool app/assets/bootstrap/team_players/KT-2026.json >/dev/null`
- [x] `python3 -m json.tool app/assets/bootstrap/team_stats/KT-2026.json >/dev/null`
- [x] `python3 -m json.tool backend/data/snapshots/records_overview/{2009,2010,2011,2012,2013,2020}.json >/dev/null`
- [x] `cd app && fvm dart format lib/core/config/app_config.dart lib/core/config/local_api_base_url_io.dart lib/core/config/local_api_base_url_web.dart lib/data/bootstrap/bootstrap_repository.dart test/data/bootstrap_repository_test.dart test/data/local_asset_player_repository_test.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/data/bootstrap_repository_test.dart test/data/local_asset_player_repository_test.dart test/data/device_snapshot_player_repository_test.dart -r expanded`
- [x] `cd app && fvm flutter build web --release --dart-define=APP_ENV=local`
- [x] `rg -n "localhost:8000|127\\.0\\.0\\.1:8000|10\\.0\\.2\\.2:8000" app/build/web` 미검출, `rg -n "api\\.kbofans\\.com" app/build/web` 검출 확인

---

## 2026-05-20: 0.0.14 앱 기록실 snapshot 신선도 보강

### 완료
- [x] 현재 변경은 앱 기록실 fallback 동작이 바뀌는 규모라 `0.0.14+14` 새 릴리즈로 판단
- [x] `DeviceSnapshotPlayerRepository` 기기 snapshot 저장 형식을 `savedAt` + `payload` envelope로 변경
- [x] 현재 시즌 기기 snapshot은 `savedAt` 기준 6시간 이내일 때만 팀 선수/선수 상세/팀 스탯/팀 기록/리더보드 fallback 으로 사용
- [x] `savedAt`이 없는 legacy device snapshot은 현재 시즌 기록실에서 무시
- [x] `LocalAssetPlayerRepository`도 현재 시즌 팀 선수/팀 스탯 번들 asset을 6시간 이내 snapshot일 때만 사용하도록 보정
- [x] `docs/APP_SPEC.md`, `README.md`, `docs/VERSIONING.md`, `CHANGELOG.md`, 앱 내 `patch_notes.md`를 `0.0.14` 기준으로 갱신

### 검증
- [x] `cd app && fvm dart format app/lib/data/repositories/device_snapshot_player_repository.dart app/lib/data/repositories/local_asset_player_repository.dart app/test/data/local_asset_player_repository_test.dart app/test/data/device_snapshot_player_repository_test.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/data/local_asset_player_repository_test.dart test/data/device_snapshot_player_repository_test.dart -r expanded`
- [x] `cd app && fvm flutter test test/data/device_snapshot_player_repository_test.dart -r expanded`

---

## 2026-05-20: 0.0.13 기록실 번들 snapshot 및 구단 로고 보정

### 완료
- [x] 현재 추가 변경은 앱 표시 데이터와 fallback 정책이 바뀌는 규모라 `0.0.12` 보강이 아니라 `0.0.13+13` 새 릴리즈로 판단
- [x] 앱 공통 구단 로고 URL을 KBO 모바일 구단소개에서 쓰는 `fixed/emblem_*_L.png`로 교체해 온보딩/홈/상세/일정/순위 로고 원본 해상도 개선
- [x] 번들 `records_overview.json`에 남아 있던 2026-03-31 기준 허경민/함덕주 기록 데이터를 제거하고 backend 2026 snapshot 값으로 교체
- [x] 기록실 번들 fallback 이 다른 시즌 데이터를 빌려 표시하지 않도록 `BootstrapRepository.loadRecordsOverview`를 exact-season-only 정책으로 보정
- [x] 현재 시즌 팀 선수/팀 스탯 snapshot은 원천 조회 전 선사용하지 않고, 실패 fallback도 6시간 이내 snapshot으로 제한
- [x] backend 2026 홈런 리더보드 snapshot을 추가해 `/records/leaderboard?metric=hr`의 snapshot fallback 보강
- [x] KT 2026 팀 선수/팀 스탯 snapshot을 최신 원천 기준으로 갱신
- [x] `app/pubspec.yaml`, `docs/VERSIONING.md`, `README.md`, `CHANGELOG.md`, 앱 내 `patch_notes.md`를 `0.0.13` 기준으로 갱신

### 검증
- [x] `python3 -m json.tool app/assets/bootstrap/records_overview.json >/dev/null`
- [x] `python3 -m json.tool backend/data/snapshots/leaderboard/2026_hr.json >/dev/null`
- [x] 번들 records overview 검증: `허경민`/`함덕주` 문자열 제거, 2026 top 리더 `박성한 .379`, `김도영 13`, `최민석 2.17` 확인, 2001/2025는 빈 exact snapshot 으로 유지
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/data/local_asset_player_repository_test.dart test/data/models/records_overview_test.dart -r expanded`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_records_overview.py`
- [x] `python3 -m compileall backend/src`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_snapshot_services.py backend/tests/test_records_overview.py`

---

## 2026-05-20: 0.0.12 릴리즈 및 이어서 해 운영 규칙 반영

### 완료
- [x] 현재 남은 변경은 사용자 표면과 backend 데이터 정책이 바뀌는 규모라 `0.0.11` 보강이 아니라 `0.0.12+12` 새 릴리즈로 판단
- [x] `app/pubspec.yaml`, `docs/VERSIONING.md`, `README.md`, `CHANGELOG.md`, 앱 내 `patch_notes.md`를 `0.0.12` 기준으로 갱신
- [x] Director가 "이어서 해"라고 하면 이후에는 변경 규모에 따라 새 버전 생성 또는 기존 GitHub Release notes 보강을 Codex가 자율 판단하도록 `kbo-version-release` / `kbo-release-flow`에 기록
- [x] 종료/과거 경기 상세의 박스스코어, 라인업, 문자중계는 완성된 snapshot을 우선 반환하도록 backend 서비스 정책 보강
- [x] 경기 전 홈/일정 표기는 점수 대신 `vs`로 처리하고, 최근 경기 흐름은 종료 경기만 집계하도록 보정
- [x] 홈 마이팀 브리프 아래에 `KBO 브리프`를 실제 API/model/UI로 연결해 리그 전체 관전 포인트, 기록 레이더, 순위 흐름을 3개 카드로 노출

### 검증
- [x] `python3 -m compileall backend/src`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_home.py backend/tests/test_records_overview.py backend/tests/test_player_stats_crawler.py`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_boxscore_service.py backend/tests/test_lineup.py backend/tests/test_relay_service.py backend/tests/test_home.py backend/tests/test_records_overview.py backend/tests/test_player_stats_crawler.py`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_schedule.py backend/tests/test_home.py`
- [x] 완료 경기 `20260519KTSS0` 상세 API 실측: `/relay` 0.014s, `/boxscore` 0.014s, `/lineup` 0.005s, 이후 재측정 `/boxscore` 0.006s, `/lineup` 0.003s
- [x] 완료 경기 상세 탭 웹 네트워크 실측: relay 탭은 `/game` + `/relay` + 양 팀 `/players`, boxscore 탭은 `/game` + `/boxscore` + 필요 팀 `/players`, lineup 탭은 `/game` + `/lineup` + 양 팀 `/players`
- [x] 완료 경기 상세 재진입/탭 전환 웹 네트워크 실측: 첫 중계 진입은 `/game` + `/relay` + 양 팀 `/players`, 박스 탭은 `/boxscore` 1건, 라인업 탭은 `/lineup` 1건, 다시 중계 탭은 API 0건
- [x] records/schedule/standings/home 웹 화면 직접 확인: records는 `/records/overview?season=2026`, schedule은 `/schedule?month=2026-05`, standings는 `/standings?season=2026`, home은 `/scoreboard/home` + `/home`만 호출
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/widget_test.dart test/core/router/app_router_test.dart test/data/models/home_aggregate_test.dart test/data/models/records_overview_test.dart -r expanded`
- [x] `cd app && fvm flutter test test/data/models/home_aggregate_test.dart test/widget_test.dart -r expanded`
- [x] `cd app && fvm flutter test test/widget_test.dart test/data/models/home_aggregate_test.dart test/features/schedule/widgets/schedule_game_card_test.dart -r expanded`
- [x] `backend/.venv/bin/pytest -q`
- [x] `cd app && fvm flutter test`
- [x] `GET /api/home?date=2026-05-20&myTeam=LG` 응답에 `kboBrief.items`가 오늘 일정/선두권/기록 레이더 3개 카드로 포함되는지 확인
- [x] `cd app && fvm flutter build web --release --dart-define=APP_ENV=local --dart-define=API_BASE_URL=http://127.0.0.1:8000/api`
- [x] 로컬 web release `http://127.0.0.1:7358/#/home` 390x844 캡처에서 마이팀 브리프 아래 `KBO 브리프` 카드 렌더링 확인 (`/tmp/kbo-brief-home-release.png`)

---

## 2026-05-20: 기록실 wRC+ 카드 및 과거 시즌 선수 이미지 보정

### 완료
- [x] 기록실 첫 화면의 미지원 `WAR` 카드 노출을 제거하고 기존 상대 타격 리더 지표 카드 표시를 `wRC+`로 교체
- [x] 2013년 리더 선수 이미지 URL이 `.../middle/2013/{playerId}.jpg`로 생성되어 CDN 404가 나는 원인 확인
- [x] 기록실/선수 상세/홈 quick item에서 과거 시즌 선수 이미지는 CDN에서 확인 가능한 최소 폴더인 `2022`를 사용하도록 공통 helper 적용

### 검증 메모
- `curl -I .../middle/2013/76232.jpg`는 `HTTP 404`, `.../middle/2026/76232.jpg`는 `HTTP 200`으로 확인
- 2013 리더 예시 `77532`, `75847`, `72443`, `60263`, `73211`, `73117`은 `2022` 이미지 경로에서 `HTTP 200` 확인

---

## 2026-05-20: preview 없는 0.0.x 릴리즈 체계 재정렬

### 완료
- [x] Director 지시에 따라 `preview` / `prerelease` 표기를 릴리즈 정책에서 제거
- [x] 현재 앱 버전을 `0.0.11+11`로 변경하고 최신 릴리즈 태그 기준을 `0.0.11`로 결정
- [x] `docs/VERSIONING.md`를 plain numeric tag 정책으로 재작성하고 `0.0.1~0.0.11` release map 정리
- [x] `CHANGELOG.md`와 앱 내 `patch_notes.md`를 `0.0.1`부터 이어지는 숫자 릴리즈 기준으로 재작성
- [x] `.claude/skills/kbo-version-release`와 `.claude/skills/kbo-release-flow`에 no-preview 정책 반영
- [x] `README.md`, `AGENTS.md`, `CLAUDE.md`, `.claude/SKILL_REFERENCE.md`의 릴리즈 태그 표현 동기화

### 릴리즈 재작성 계획
- [x] 기존 `0.1.0-preview.1~4`, `0.0.1-preview`, `0.0.1-preview.1`, `0.0.2-preview` GitHub 릴리즈/태그 삭제 대상 확정
- [x] 기존 충돌 숫자 태그 `0.0.2~0.0.5`는 Director 승인 범위 안에서 새 numeric release map에 맞춰 재생성 대상 확정
- [x] 새 릴리즈는 `0.0.1`부터 `0.0.11`까지 모두 일반 GitHub Release로 생성하고, `0.0.11`만 Latest로 표시 예정

---

## 2026-05-20: 경기/마이팀 선수 기록 인사이트 기획 정리

### 완료
- [x] 구현 시도 코드는 되돌리고, 구현 전 기획/검증안만 `docs/PLAYER_RECORD_INSIGHTS_PLAN_2026-05-20.md`로 분리
- [x] 현재 snapshot 기준 데이터 가능 범위를 확인: boxscore는 멀티히트/타점/탈삼진/QS 류, relay는 같은 경기 안의 타석 흐름 판정에 적합
- [x] 선수별 최근 경기 snapshot의 `recentGames`는 2026 auto snapshot 623개가 모두 비어 있어 `몇 경기 연속 안타`는 별도 game-log 적재 없이는 확정 불가로 분류
- [x] KBO 통산/개인 통산/KBO 최초/최연소/최단 경기 같은 역사적 기록 레이어를 P3로 추가하고, `record_catalog` 기준선 없이는 자동 노출하지 않는 원칙을 반영
- [x] 경기 예정일 때 `오늘 달성 가능`, 경기 종료/다음날 `오늘/어제 달성`을 보여주는 `기록 레이더` 피드 기획을 추가
- [x] `daily_record_candidates` / `daily_record_achievements` snapshot 개념과 예정/진행/종료/다음날 상태별 UX 문구 원칙을 정리
- [x] 마이팀 브리프 아래에 리그 전체 강한 정보를 요약하는 `KBO 브리프` 영역을 추가 기획
- [x] `KBO 브리프`를 경기 전/중/종료/다음날/경기 없음 상태별로 나누고, 빅매치/경기 흐름/선수 활약/기록 레이더/순위 변동 카드 타입을 정리

### 검증 메모
- `backend/data/snapshots/boxscore/20260519LGHT0.json`: 타자별 `atBats/hits/rbi/runs`, 투수별 `innings/strikeouts/earnedRuns` 확인
- `backend/data/snapshots/relay/20260519LGHT0.json`: `N번타자`와 결과 텍스트(`홈런`, `안타`)가 순서대로 있어 같은 경기 내 연속 타석 분석 가능
- `backend/data/snapshots/player_detail/*-2026-auto.json`: `recentGames` non-empty 0개 확인
- 역사적 기록은 개인 career total, all-time leaderboard, 공식/검수 record catalog가 있어야 안정적으로 판정 가능
- 오늘 가능 후보는 경기 전에는 confidence가 낮고, 라인업 발표 후/경기 종료 후에만 확정성이 올라가므로 상태별 문구를 분리해야 함
- `KBO 브리프`는 마이팀 브리프와 역할이 겹치지 않게 리그 전체 맥락을 담당하고, 같은 경기에서 여러 이슈가 나오면 가장 강한 하나만 홈에 올리는 원칙으로 정리

---

## 2026-05-20: 문자중계 선수 이미지 경로 확인 및 라인업 투수 사진 비율 조정

### 완료
- [x] 문자중계 현재 타석 카드가 `batterImageUrl` / `pitcherImageUrl`을 우선 사용하고, 없을 때 선수 이미지 맵을 fallback으로 쓰는 구조인지 확인
- [x] 라인업 탭 선발투수 hero 카드의 이미지 표시 영역을 카드 전체 폭/높이에서 제한해 얼굴이 과도하게 커 보이지 않도록 조정
- [x] 선발투수 이미지 대비 카드 박스가 과하게 커 보이는 피드백 반영: 카드 높이와 radius를 줄이고 내부 사진 비율을 재조정

### 검증
- [x] `app/lib/features/game_detail/tabs/relay_tab.dart` 코드 경로 확인
- [x] `app/lib/features/game_detail/tabs/lineup_tab.dart` 표시 비율 패치 확인
- [x] `cd app && fvm flutter analyze lib/features/game_detail/tabs/lineup_tab.dart lib/features/game_detail/tabs/relay_tab.dart lib/data/models/home_aggregate.dart`
- [x] `cd app && fvm flutter analyze lib/features/game_detail/tabs/lineup_tab.dart`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_home.py`

### 메모
- 문자중계는 홈 quick item처럼 aggregate payload에서 `imageUrl`이 빠지는 경로가 아니라, 경기 상세 payload의 현재 타석 선수 이미지 URL을 직접 우선 사용한다.
- 현재 변경은 선발투수 카드의 시각 비율만 조정하며 선수 이미지 조회 로직은 바꾸지 않았다.

---

## 2026-05-20: 홈 quick item 선수 얼굴 fallback 원인 확인 및 보정

### 완료
- [x] 웹 preview에서 김도영 선수 상세(`/records/player/52605?season=2026`)는 CDN 사진이 정상 표시되는지 확인
- [x] `/api/home` aggregate의 `홈런왕` quick item이 `imageUrl` 없이 내려와 홈 카드가 `fallbackLabel` 첫 글자인 `김`으로 표시되는 원인 확인
- [x] backend 홈 aggregate의 홈런왕 quick item에 선수 상세 route와 KBO 선수 이미지 URL을 포함하도록 보정
- [x] app local aggregate fallback도 backend와 같은 선수 상세 route / 이미지 URL 규칙으로 보정
- [x] backend/app 회귀 테스트 추가

### 검증
- [x] `curl -I https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/person/middle/2026/52605.jpg` 가 `HTTP 200`으로 응답하는지 확인
- [x] 패치 후 local backend `/api/home?date=2026-05-20`의 홈런왕 quick item에 `imageUrl`과 선수 상세 route가 포함되는지 확인
- [x] 390x844 웹 preview에서 김도영 선수 상세 카드의 얼굴 이미지 정상 렌더링 확인
- [x] 390x844 웹 preview 홈 quick item에서 `김` fallback 대신 김도영 얼굴 이미지가 렌더링되는지 확인
- [x] `backend/.venv/bin/pytest -q backend/tests/test_home.py`
- [x] `cd app && fvm flutter test test/data/models/home_aggregate_test.dart`

### 메모
- 원인은 선수 이미지 파일 부재가 아니라 홈 quick item payload 누락이었다.

---

## 2026-05-20: 릴리즈 버저닝 세분화 및 패치노트 재정렬 (superseded)

### 완료
- [x] 이전 정리안은 preview train 기반이었으나, Director 지시로 위 `0.0.x` 숫자 릴리즈 체계에 의해 폐기
- [x] 현재 앱 버전은 위 작업에서 `0.0.11+11`로 재정렬
- [x] `docs/VERSIONING.md`는 preview segmentation rule 대신 plain numeric release map으로 재작성
- [x] `.claude/skills/kbo-version-release`에 historical release split 시 `docs/VERSIONING.md`와 앱 내 패치노트를 함께 갱신하도록 보강
- [x] `CHANGELOG.md`와 앱 내 `patch_notes.md`는 `0.0.1~0.0.11` 기준으로 재작성

### 검증
- [x] 기존 preview/prerelease 태그는 삭제하고 숫자 태그로 재생성하는 기준으로 변경

---

## 2026-05-20: 홈 보조 로딩 fan-out 제거 및 데이터 경로 문서 재정렬

### 완료
- [x] 홈 화면에서 `/home` aggregate 로딩 중 별도로 `recordsOverviewProvider`를 호출하던 보조 섹션 제거
- [x] 실행되지는 않지만 재활성화 시 첫 화면을 API prefetch에 다시 묶을 수 있던 blocking startup prefetch 죽은 코드 제거
- [x] 값이 더 이상 set되지 않는 `startupScoreboardProvider`와 Home/Main의 의존성 제거
- [x] 홈 첫 화면 데이터 흐름을 `scoreboardProvider` + 지연 `homeAggregateProvider`로 고정하고, aggregate 실패 시 schedule/standings/records 로컬 조립 fallback이 재진입하지 않도록 문서 기준 재정렬
- [x] 실제 startup은 local onboarding/my-team 상태만 확인하고, 화면별 원격 데이터는 해당 route/provider가 소유하도록 정리
- [x] 웹에서는 홈 위젯/Live Activity resume observer를 등록하지 않도록 하여 기록실/일정 화면 복귀 시 전역 scoreboard refresh가 끼어들지 않게 정리
- [x] 더 이상 set되지 않는 `startup_preload_done:*` Home 플래그 읽기 제거
- [x] 홈 scoreboard 자동 refresh를 live 30초 / scheduled 5분 / terminal 정지로 조정해 같은 정보를 과하게 반복 호출하지 않도록 정리
- [x] 라인업 탭 첫 진입에서 박스스코어 파생 batter/pitcher fallback watch를 제거하고 `/game/{gameId}/lineup` + 양 팀 선수 이미지 lookup만 사용하도록 축소
- [x] 라인업 선발 비교에서 박스스코어가 없을 때 `0.00` 같은 가짜 수치 대신 `-` / `선발 발표`로 표시하도록 보정
- [x] 상세/스코어/중계/박스스코어/라인업 탭의 현재 provider fan-out 문서를 실제 구현 기준으로 갱신
- [x] local native 기본 API-first, `PREFER_DIRECT_SCRAPE=true` 명시 임시 direct-primary 검증 모드 기준을 엔지니어링 노트에 반영

### 검증
- [x] `rg`로 Home에서 `recordsOverviewProvider(season)`, overview lazy section, `GameDetailPreloadService` 재참조가 없는지 확인
- [x] `rg`로 startup blocking prefetch / startup preload version / startup API task batch 재참조가 없는지 확인
- [x] `rg`로 app/lib의 `startup_preload_done` 재참조가 없는지 확인
- [x] `rg`로 Lineup tab의 `battersProvider` / `pitchersProvider` / `gameBoxscoreProvider` 재참조가 없는지 확인
- [x] 데이터 리프레시 문서의 stale direct-debug / 이전 시즌 snapshot 차용 / 과거 preload 표현 제거 확인
- [x] `cd app && fvm flutter analyze lib/features/home/home_screen.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/widget_test.dart test/data/local_asset_player_repository_test.dart -r expanded`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_snapshot_services.py backend/tests/test_home.py backend/tests/test_scoreboard_service_cache.py`
- [x] `cd app && fvm flutter build web --release --dart-define=APP_ENV=local`
- [x] 웹 재빌드 후 Home 네트워크 호출이 `/api/scoreboard/home` + `/api/home` 2개로 제한되는지 Playwright network log로 확인
- [x] 웹 재빌드 후 Records는 `/api/records/overview`, Schedule은 `/api/schedule` 단일 호출로 진입하는지 확인
- [x] 웹 재빌드 후 `#/game/20260519KTSS0?tab=lineup` 네트워크 호출에서 `/api/game/.../boxscore`가 사라지고 `/api/game`, `/lineup`, 양 팀 `/players`만 남는지 확인

---

## 2026-05-20: 버저닝 / 릴리즈 노트 루틴 정리 (superseded)

### 완료
- [x] 이전 정리안은 `0.1.0` preview train을 가정했으나, Director 지시로 no-preview `0.0.x` 체계로 대체
- [x] 버전 정책 기준 문서 `docs/VERSIONING.md` 추가
- [x] 버전 변경 시 `CHANGELOG.md`, 앱 내 패치노트(`app/assets/bootstrap/patch_notes.md`), GitHub 릴리즈 노트, `docs/WORKLOG.md`를 함께 갱신하도록 `.claude/skills/kbo-version-release` 추가
- [x] `kbo-release-flow`, `AGENTS.md`, `CLAUDE.md`, `.claude/SKILL_REFERENCE.md`, `README.md`에 새 루틴 반영
- [x] 앱 내 패치노트의 업데이트 섹션은 위 작업에서 `0.0.11+11` 기준으로 재작성

### 검증
- [x] `docs/VERSIONING.md` 기준은 위 작업에서 plain numeric release map으로 변경

---

## 2026-05-20: 기록실 과거 시즌 snapshot 보강

### 완료
- [x] 기록실 팀 상세가 2026 외 시즌에서 현재 로스터/direct 결과를 섞을 수 있던 원인 확인
- [x] 앱 번들 `team_players` snapshot을 2022~2026 전 구단으로 확장
- [x] 앱 번들 `team_stats`는 hitting/pitching이 모두 있는 complete snapshot만 포함하도록 필터링
- [x] direct KBO 선수 검색은 현재 등록 선수 기준이므로 과거 시즌 팀 로스터 요청에서는 snapshot fallback으로 내려가도록 차단
- [x] `DeviceSnapshotPlayerRepository` cache key version을 올려 기존 기기 cache에 저장됐을 수 있는 잘못된 과거 시즌 팀 기록을 무효화
- [x] local asset이 없는 시즌은 다른 시즌 snapshot을 빌려 보여주지 않고 빈 상태로 처리하도록 변경
- [x] `scripts/generate_bootstrap_snapshots.py`가 backend team snapshot을 앱 bootstrap asset으로 동기화하도록 보강
- [x] release API backend 준비 항목은 구현하지 않고 `docs/RELEASE_API_BACKEND_TODO.md` TODO로 분리

### 검증
- [x] 앱 번들 team_players가 2022~2026 각 10개 구단 snapshot을 포함하는지 확인
- [x] 앱 번들 team_stats가 partial historical snapshot을 제외하고 complete snapshot만 포함하는지 확인
- [x] `python3 -m py_compile scripts/generate_bootstrap_snapshots.py`
- [x] `cd app && fvm flutter test test/data/local_asset_player_repository_test.dart`
- [x] `cd app && fvm flutter test --dart-define=PREFER_DIRECT_SCRAPE=true test/data/providers_routing_test.dart`
- [x] `cd app && fvm flutter analyze lib/data/repositories/kbo_direct_player_repository.dart lib/data/repositories/device_snapshot_player_repository.dart lib/data/repositories/local_asset_player_repository.dart test/data/local_asset_player_repository_test.dart pubspec.yaml`

---

## 2026-05-20: iPhone 임시 direct-primary local release-mode 실행 경로 보정

### 완료
- [x] API 미구현 영역 검증을 위해 iPhone local release 실행 경로를 임시 direct-primary 모드로 재분리
- [x] `./scripts/codex-run.sh ios-local-release` 를 `APP_ENV=local + PREFER_DIRECT_SCRAPE=true` release-mode로 고정
- [x] `scripts/codex-run-ios-local-release.sh` 래퍼 추가
- [x] 일반 local native provider routing은 기본 API 경로를 유지하고, direct는 `PREFER_DIRECT_SCRAPE=true` 명시 빌드에서만 켜지는지 회귀 테스트 보강
- [x] `README.md`, `docs/APP_STANDALONE_MODE.md`, `CHANGELOG.md`에 iPhone local release-mode 검증 기준 반영

### 검증
- [x] `bash -n scripts/codex-run.sh`
- [x] `plutil -lint app/ios/Runner/Info.plist`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/data/providers_routing_test.dart test/data/local_asset_player_repository_test.dart`
- [x] `./scripts/codex-run.sh ios-local-release` 로그가 `temporary direct-primary` 모드를 명시하도록 보정
- [x] `xcrun devicectl device process launch --device 7A054DC8-7915-5B43-BA79-3060BE1A3209 --terminate-existing com.kbofans.kboFans` 로 설치 앱 launch 확인
- [x] historical team stats snapshot 중 hitting/pitching 한쪽만 있는 partial payload가 팀 기록 UI에 노출되지 않도록 local asset loader와 snapshot generator 방어 로직 추가
- [x] `fvm flutter test test/data/local_asset_player_repository_test.dart -r expanded`
- [x] `cd app && fvm flutter test`
- [x] `cd app && fvm flutter build web --release --dart-define=APP_ENV=local`

---

## 2026-05-20: release API health gate 추가

### 완료
- [x] `scripts/release-api-health-check.sh` 추가
- [x] release API host DNS lookup, HTTPS TLS 인증서, `/api/health`, `/api/scoreboard/home`, `/api/home`, `/api/schedule`, `/api/standings`, `/api/records/overview` 검증을 하나의 gate로 묶음
- [x] GitHub Actions `App Build Artifacts`에서 `APP_ENV=release` matrix 빌드 전에 health gate를 실행하고, 통과한 API base URL을 `--dart-define=API_BASE_URL=...` 로 주입하도록 보강
- [x] workflow 입력 `release_api_base_url` 추가. 운영 API가 `https://api.kbofans.com/api`가 아니면 입력/variable/secret `RELEASE_API_BASE_URL`로 실제 API를 지정하도록 정리
- [x] 로컬 `./scripts/codex-run.sh ios-release`도 `APP_ENV=release`와 release API health gate를 사용하도록 변경
- [x] `README.md`, `docs/DISTRIBUTION_GUIDE.md`, `.claude/skills/kbo-release-flow/SKILL.md`, `CHANGELOG.md`에 release gate 기준 반영

### 검증
- [x] `RELEASE_API_HEALTH_TIMEOUT_SECONDS=5 scripts/release-api-health-check.sh` 기본 production API DNS 실패 확인
- [x] `ALLOW_INSECURE_RELEASE_API=true RELEASE_API_HEALTH_DATE=2026-05-19 RELEASE_API_HEALTH_MONTH=2026-05 RELEASE_API_HEALTH_SEASON=2026 scripts/release-api-health-check.sh http://127.0.0.1:8000/api` 로 local backend 성공 확인
- [x] `cd app && fvm flutter analyze lib/core/config/app_config.dart lib/data/providers.dart lib/features/game_detail/tabs/lineup_tab.dart lib/services/widget_sync_service.dart test/data/providers_routing_test.dart`
- [x] `cd app && fvm flutter test test/data/providers_routing_test.dart test/data/local_asset_player_repository_test.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test`

---

## 2026-05-20: 패치노트 버전별 표시

### 완료
- [x] `assets/bootstrap/patch_notes.md`를 버전 섹션 기준으로 정리
- [x] 패치노트 화면을 버전별 카드로 표시하고 현재 설치 버전과 일치하는 항목에 `현재 설치됨` 배지 표시
- [x] web/package metadata 조회 실패 시 패치노트 첫 버전을 현재 번들 버전 fallback으로 사용
- [x] `docs/APP_SPEC.md`, `CHANGELOG.md`에 버전별 패치노트 기준 반영

### 검증
- [x] `cd app && fvm dart format lib/features/settings/patch_notes_screen.dart`
- [x] `cd app && fvm flutter analyze lib/features/settings/patch_notes_screen.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/widget_test.dart test/services/push_notification_service_test.dart test/core/router/app_router_test.dart`
- [x] `cd app && fvm flutter build web --release --dart-define=APP_ENV=local`
- [x] 390x844 Puppeteer preview에서 버전별 카드와 `현재 설치됨` 배지 렌더링 확인

---

## 2026-05-20: local native dev-api DNS 실패 원인 분석 및 라우팅 보정

### 완료
- [x] `Failed host lookup: 'dev-api.kbofans.com'` 재현 로그와 local DNS/curl 실패를 기준으로 직접 원인 확인
- [x] local native no-override 실행이 dev API를 먼저 호출하던 `AppConfig` / repository routing 불일치 정리
- [x] 홈/일정/순위는 local native no-override에서 direct KBO 경로를 우선 사용하고, 기록실은 bundled asset fallback을 우선 사용하도록 보정
- [x] 위젯/백그라운드 scoreboard fetch도 같은 local native routing 정책을 쓰도록 정리
- [x] resume scoreboard sync를 throttle하고, 홈 화면 자체 resume invalidation 중복을 제거
- [x] 홈 loading shell의 다중 spinner를 skeleton placeholder 중심으로 정리
- [x] 원인/수정/검증 기준 문서화 (`docs/LOCAL_NATIVE_API_FAILURE_ANALYSIS_2026-05-20.md`)

### 검증
- [x] `curl -I --max-time 5 https://dev-api.kbofans.com/api/health` 실패로 dev API DNS 미해석 확인
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test`
- [x] `cd app && fvm flutter build ios --debug --no-codesign --dart-define=APP_ENV=local`
- [x] `cd app && fvm flutter run -d 00008130-0008198E3E78001C --debug --dart-define=APP_ENV=local --no-pub` 로 실기기 launch / VM Service 연결 확인
- [x] local native provider routing 회귀 테스트 추가 (`app/test/data/providers_routing_test.dart`)
- [ ] local iOS simulator/device no-override 실행 로그에서 `dev-api.kbofans.com` 반복 호출 없음 확인

---

## 2026-05-20: 설정 앱 정보 및 지원 동작 복구

### 완료
- [x] `앱 정보 및 지원`의 죽은 행을 실제 동작으로 연결
- [x] 앱 버전을 `package_info_plus` 기반의 실제 `version+buildNumber` 표시로 정리
- [x] 이용약관/개인정보처리방침은 앱 내 문서 시트로 열고, 오픈소스 라이선스는 Flutter 라이선스 페이지로 연결
- [x] 문의하기는 `support@kbofans.com` 메일 작성으로 연결하고, 메일 앱을 열 수 없으면 주소를 클립보드에 복사하도록 fallback 처리
- [x] `docs/APP_SPEC.md`, `docs/FIGMA_PROMPT.md`, `CHANGELOG.md`에 앱 정보 및 지원 동작 기준 반영

### 검증
- [x] `cd app && fvm dart format app/lib/features/settings/settings_screen.dart app/test/features/settings/settings_screen_test.dart`
- [x] `cd app && fvm flutter analyze lib/features/settings/settings_screen.dart test/features/settings/settings_screen_test.dart`
- [x] `cd app && fvm flutter test test/features/settings/settings_screen_test.dart`
- [x] `cd app && fvm flutter test test/widget_test.dart test/features/settings/settings_screen_test.dart`

### 메모
- 원인은 화살표 UI만 있고 `onTap`이 없는 행과 하드코딩된 버전 표시였다.
- 현재 약관/개인정보 문구는 MVP용 앱 내 문서 기준이다. 정식 배포 전 스토어 심사용 문안 확정이 필요하다.

---

## 2026-05-20: 기록실/경기 상세 불필요 호출 추가 제거

### 완료
- [x] 팀 기록 상세가 보조 순위 표시를 위해 `/api/standings`를 같이 부르던 구조 제거
- [x] 팀 기록 상세 상단 요약은 `/api/team/{teamId}/records` 응답의 팀 타격/투수 지표만 사용하도록 정리
- [x] 경기 상세 기본 점수 탭의 `/highlights` 즉시 호출을 제거하고, 하이라이트는 명시 요청 시에만 로드하도록 지연
- [x] Android/iOS 앱 루트에서 모든 화면에 따라붙던 `scoreboardProvider(today)` watch를 제거해, 기록실/일정 직접 진입 시 위젯 동기화용 스코어보드 요청이 자동 발생하지 않도록 정리
- [x] Android/iOS non-blocking startup prefetch에서 `scoreboard`/`homeAggregate` 워밍을 제거해, 앱 시작만으로 화면 외 데이터를 미리 당기지 않도록 정리
- [x] 앱 루트 widget test가 홈 네트워크를 열지 않도록 onboarding 미완료 상태로 검증 범위를 좁힘
- [x] `AppMotionSwitcher`의 analyzer fatal info를 정리해 전체 analyze가 깨지지 않도록 보정
- [x] 홈 보조 섹션의 local fallback assembly 제거: `/api/home` 실패 시 UI가 직접 `schedule`/`standings`/`recordsOverview`를 추가 호출하지 않도록 정리
- [x] 홈 fallback 제거로 미사용이 된 로컬 조립 helper를 삭제해 fallback 재유입 지점을 줄임
- [x] Android/iOS local startup에서 KBO 릴레이 로그인 세션을 선행 prime 하던 hidden crawl 제거
- [x] 릴레이 세션은 릴레이 탭 진입 시 `KboDirectRepository`의 실제 relay fetch 경로에서만 준비하도록 유지

### 검증
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test`
- [x] `cd app && fvm flutter build web --release --dart-define=APP_ENV=local`
- [x] 브라우저 실측: `/records/team/KT` 첫 진입 API가 `/api/team/KT/records?season=2026` 하나만 남음
- [x] 브라우저 실측: `/game/20260519KTSS0` 첫 진입 API가 `/api/game/20260519KTSS0` 하나만 남고 `/highlights` 즉시 호출 없음
- [x] 브라우저 실측: `/home` 첫 진입 API가 `/api/scoreboard/home` + `/api/home`만 호출하고 schedule/standings/records fallback 호출 없음

---

## 2026-05-20: 설정 패치노트 화면 추가

### 완료
- [x] 설정 화면의 `앱 정보 및 지원`에 `패치노트` 진입점 추가
- [x] `/patch-notes` 상세 화면을 추가하고 번들 asset `assets/bootstrap/patch_notes.md`를 읽어 표시하도록 연결
- [x] `docs/APP_SPEC.md`, `CHANGELOG.md`에 패치노트 진입점 반영

### 검증
- [x] `cd app && fvm dart format lib/core/router/app_router.dart lib/features/settings/settings_screen.dart lib/features/settings/patch_notes_screen.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/widget_test.dart test/services/push_notification_service_test.dart test/core/router/app_router_test.dart`
- [x] `cd app && fvm flutter build web --release --dart-define=APP_ENV=local`
- [x] 390x844 Puppeteer preview에서 `/patch-notes` 화면 렌더링 및 patch notes asset 로드 확인

---

## 2026-05-20: Android 경기 따라가기 진행형 알림 구현

### 완료
- [x] `경기 따라가기` follow session을 Android에서도 진행형 ongoing notification으로 표시하도록 `LiveActivityService` 확장
- [x] 따라가기 시작 시 Android 알림 권한을 명시 action 흐름에서 요청하고, 같은 알림 ID로 스코어/이닝/업데이트 시각을 갱신
- [x] 앱 안 `그만 보기`, Android 알림의 `그만 보기` action, 경기 종료/취소/중단, follow 대상 누락 시 Android 진행형 알림도 함께 해제
- [x] `docs/APP_SPEC.md`, `CHANGELOG.md`에서 Android 진행형 알림을 준비중 표기 대신 구현 표면으로 반영

### 검증
- [x] `cd app && fvm dart format lib/services/live_activity_service.dart lib/features/game_detail/game_detail_screen.dart`
- [x] `cd app && fvm flutter analyze lib/services/live_activity_service.dart lib/features/game_detail/game_detail_screen.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/services/live_activity_service_test.dart`
- [x] `cd app && fvm flutter test test/services/push_notification_service_test.dart`
- [x] `cd app && fvm flutter build apk --debug --dart-define=APP_ENV=local`

### 메모
- `cd app && fvm flutter test test/widget_test.dart`는 현재 워크트리의 startup/direct KBO pending timer로 실패한다. 이번 Android ongoing notification 테스트는 별도 서비스 테스트로 통과했다.

---

## 2026-05-20: 설정 앱 밖 표면 설명 제거

### 완료
- [x] 설정 화면의 `앱 밖 표면` 설명 블록을 제거해 장면별 알림 설정과 중복되는 메타 설명을 없앰
- [x] 전달 방식 picker 문구를 `이 장면을 어떻게 받을지` 기준의 사용자 언어로 정리
- [x] `docs/APP_SPEC.md`, `CHANGELOG.md`에 설정 화면 카피 원칙과 변경 사항 반영

### 검증
- [x] `cd app && fvm dart format lib/features/settings/settings_screen.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/widget_test.dart test/services/push_notification_service_test.dart`

---

## 2026-05-20: 설정 앱 버전 표시 실제 메타데이터 연결

### 완료
- [x] 설정 화면의 `버전` 값을 하드코딩 문자열이 아니라 플랫폼 앱 메타데이터에서 읽도록 변경
- [x] 버전 로딩 실패 시 잘못된 숫자 대신 `확인 불가`를 표시하도록 처리
- [x] `docs/APP_SPEC.md`, `CHANGELOG.md`에 설정 앱 정보 표시 기준 반영

### 검증
- [x] `cd app && fvm flutter pub add package_info_plus`
- [x] `cd app && fvm dart format lib/features/settings/settings_screen.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/widget_test.dart test/services/push_notification_service_test.dart`
- [x] `cd app && fvm flutter build web --release --dart-define=APP_ENV=local`

---

## 2026-05-20: 홈런왕 카피 반영

### 완료
- [x] 홈/기록실/records overview의 홈런 관련 리더 표현을 `홈런왕` 중심 카피로 정리
- [x] backend snapshot fallback, 테스트 기대값, APP_SPEC, 디자인 산출물의 동일 표현 동기화

---

## 2026-05-20: web deep-link 목적지 보존 검증 및 라우터 보정

### 완료
- [x] 390x844 web capture로 `/#/schedule`, `/#/standings`, `/#/records`, `/#/records/team/HT`, `/#/records/leaderboard/avg`, `/#/game/20260519LGHT0?tab=*` 직접 진입을 재검증
- [x] onboarding 상태가 `null -> true`로 바뀌는 순간 `GoRouter`가 재생성되며 deep-link 목적지가 `/#/home`으로 유실되는 문제 확인
- [x] `GoRouter` 인스턴스는 유지하고 onboarding 상태 변경은 `refreshListenable`으로 전달하도록 수정
- [x] 라우터 인스턴스 재생성 방지 회귀 테스트 추가
- [x] 홈 보조 섹션을 앱 내부 일정/순위/기록실 조합 대신 backend `/api/home` 단일 호출 우선으로 전환
- [x] 웹 부트스트랩 선로딩과 루트 native widget sync watch를 분리해, 기록실/일정/상세 화면 진입 시 불필요한 스코어보드/홈 API 호출이 따라붙지 않도록 보정
- [x] 게임 상세 진입 직후 post-frame refresh가 같은 `/api/game/{gameId}`를 즉시 중복 호출하던 경로 제거
- [x] 경기 상세 라인업 탭에서 relay, standings, schedule 2개월, team stats 2팀을 즉시 자동 로드하던 구조를 제거해 라인업 필수 데이터 중심으로 호출 축소
- [x] local 환경에서는 web/native 모두 `/api/metrics/client` 진단 POST를 보내지 않도록 막아 QA 네트워크 노이즈와 불필요한 로컬 호출 제거
- [x] 일정 화면 최초 로딩에서 `RefreshIndicator`와 중앙 spinner가 중첩되던 구조를 제거하고 회귀 테스트 추가

### 검증
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/widget_test.dart test/services/push_notification_service_test.dart test/core/router/app_router_test.dart`
- [x] `cd app && fvm flutter build web --release --dart-define=APP_ENV=local`
- [x] `cd app && fvm flutter test`
- [x] `backend/.venv/bin/pytest -q`
- [x] `http://127.0.0.1:7359/index.html#/records`, `#/schedule`, `#/home`, `#/game/20260519KTSS0`, `#/game/20260519KTSS0?tab=relay`, `?tab=boxscore`, `?tab=lineup`, `#/records/team/KT`, `#/records/leaderboard/avg` 브라우저 network request 재검증
- [x] local web 홈 재측정에서 `/api/metrics/client` POST가 사라지고 `/api/scoreboard/home`, `/api/home`만 남은 것 확인
- [x] 일정 화면 초기 로딩이 `CircularProgressIndicator` 1개만 렌더하고 `RefreshIndicator`를 중복 생성하지 않는 widget test 추가
- [x] 수정 전 재현 산출물: `artifacts/kbo-regression-sweep-2026-05-20-v11/summary.json`
- [x] 수정 후 통과 산출물: `artifacts/kbo-regression-sweep-2026-05-20-v12/summary.json`, `artifacts/kbo-regression-sweep-2026-05-20-v13/summary.json`

### 메모
- hash route 직접 진입은 수정 후 목적지를 유지한다.
- path route 직접 진입(`/schedule`, `/game/...`)은 현재 `python -m http.server` 정적 preview에서 `404`가 정상 관찰된다. 배포 서버에서 path URL을 쓰려면 SPA fallback 설정이 별도로 필요하다.
- `APP_ENV=local` web preview에는 DevConsole floating button이 표시되어 일부 우하단 컨텐츠를 가릴 수 있다. release 환경에서는 숨겨지는 local QA 표면이다.

---

## 2026-05-19: v4 UX 보완안 실제 UI 반영

### 완료
- [x] 설정 화면 용어를 `바로 알림 / 묶음 요약 / 따라가기만 / 끄기`로 정리하고 중복 제목을 `알림` / `장면별 알림` 구조로 조정
- [x] 홈 대표 경기 카드의 CTA를 예정/라이브/종료 상태별로 분리하고, `중계 보기`와 알림/따라가기 액션이 같은 callback을 쓰지 않도록 수정
- [x] 종료 경기 상세에서 하이라이트가 탭 진입을 가리지 않도록 스코어 탭 footer로 이동
- [x] 마이팀 브리프의 최근 3경기 chip을 가로 스크롤로 바꾸고 CTA/metric 밀도와 하단 safe area를 보강
- [x] 홈/경기상세의 stale성 문구를 `방금 업데이트` 고정에서 상태별 `최종 기록`, `예정` 등으로 분기
- [x] `docs/APP_SPEC.md`, `CHANGELOG.md`에 변경된 UX 흐름과 용어 반영

### 검증
- [x] `cd app && fvm dart format lib/features/settings/settings_screen.dart lib/features/home/widgets/my_team_game_card.dart lib/features/home/home_screen.dart lib/features/game_detail/game_detail_screen.dart lib/features/game_detail/tabs/score_tab.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/widget_test.dart test/services/push_notification_service_test.dart`
- [x] `cd app && fvm flutter build web --release --dart-define=APP_ENV=local`
- [x] `node artifacts/kbo-v4-ux-eval/capture-v4-screens.js`
- [x] 화면 산출물 갱신: `artifacts/kbo-v4-ux-eval/03-home-state.png`, `01-settings-playbook.png`, `04-settings-surfaces.png`, `05-settings-delivery-picker.png`, `02-game-detail-relay.png`

### 메모
- native Live Activity / Android 홈 위젯 실기기 캡처는 아직 별도 QA로 남는다.
- 현재 web smoke 기준 홈 CTA 잘림, 설정 용어 혼란, 경기 상세 하이라이트 우선 노출 문제는 해소됐다.

---

## 2026-05-19: 일정 구장별 보기 퀵링크 추가

### 완료
- [x] 구장별 일정 상단에 구장명과 경기 수를 보여주는 가로 퀵링크 버튼 row 추가
- [x] 퀵링크 탭 시 해당 구장 섹션 헤더로 부드럽게 스크롤되도록 `Scrollable.ensureVisible` 연결
- [x] 월별 `PageView`, 팀 필터, 구장별 팀 필터 구조는 유지하면서 월+구장 단위 section key를 사용해 월 스와이프와 충돌하지 않도록 조정
- [x] `docs/APP_SPEC.md`, `docs/FIGMA_PROMPT.md`, `CHANGELOG.md`에 사용자 체감 동작 반영

### 검증
- [x] `cd app && fvm flutter analyze lib/features/schedule/schedule_screen.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter build web --release`

### 메모
- 기존 구장별 보기에는 구장 섹션이 아래로 길게 나열되어 원하는 구장으로 이동하려면 수동 스크롤이 필요했다.
- 퀵링크는 현재 필터 결과에 남은 구장만 표시하므로 마이팀/팀별 필터와 같은 목록 기준을 공유한다.

---

## 2026-05-19: v4 Moment Surface UX 화면 평가

### 완료
- [x] v4 Moment Subscription / Surface Strategy 기준으로 실제 Flutter web 390x844 화면을 재캡처
- [x] 홈, 설정 알림 플레이북, 앱 밖 표면 설명, 전달 방식 picker, 경기 상세 화면을 화면 근거와 함께 평가
- [x] Apple HIG, Android Live Updates/Notification Permission, WCAG Target Size, NN/g notification/status feedback 기준으로 UX 원칙 정리
- [x] `docs/UX_REVIEW_V4_MOMENT_SURFACE_2026-05-19.md`에 P1/P2/P3 개선 우선순위 문서화
- [x] `docs/UX_FIX_PROPOSAL_V4_MOMENT_SURFACE_2026-05-19.md`에 문제별 원인, 수정안, 구현 범위, QA/DoD를 추가 문서화

### 검증
- [x] `GET http://127.0.0.1:8000/api/health`
- [x] `node artifacts/kbo-v4-ux-eval/capture-v4-screens.js`
- [x] 화면 산출물: `artifacts/kbo-v4-ux-eval/03-home-state.png`, `01-settings-playbook.png`, `04-settings-surfaces.png`, `05-settings-delivery-picker.png`, `02-game-detail-relay.png`
- [x] 코드 위치 확인: `home_screen.dart`, `my_team_game_card.dart`, `settings_screen.dart`, `game_detail_screen.dart`, native widget/live activity files

### 메모
- 현재 UX 평가는 82/100으로 판단했다. 방향은 맞지만 홈 CTA 노출, `중계 보기` 진입 결과, Live/Widget/stale 용어 명확성은 후속 수정이 필요하다.
- 수정 순서는 copy 정리, 홈 CTA 상태 분기, 카드 callback 분리, 상세 relay 우선 노출, 브리프 compact 조정, native surface QA 순서가 가장 리스크가 낮다.

---

## 2026-05-19: 기록실 runtime 검증 및 OPS+ snapshot 정규화

### 완료
- [x] 기록실 overview, 리더보드, 팀 기록 합본, 선수 상세 API를 실제 local FastAPI 경로로 재검증
- [x] 10개 구단 `/api/team/{teamId}/records?season=2026` 합본 응답이 모두 `200`으로 종료되고 선수 목록/타격/투수 스탯을 포함하는지 확인
- [x] 구형 `records_overview` snapshot에 `opsPlus`가 없어도 backend 응답 단계에서 현재 계약에 맞춰 OPS+ 리더보드를 계산하도록 보정
- [x] 하단 탭 실제 클릭으로 기록실 첫 화면과 리더보드 상세 진입을 390x844 web smoke로 확인

### 검증
- [x] `backend/.venv/bin/python -m compileall backend/src backend/tests/test_records_overview.py backend/tests/test_snapshot_services.py`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_records_overview.py backend/tests/test_snapshot_services.py backend/tests/test_teams.py`
- [x] 실제 API 계측: `records/overview` 리더보드 `avg/hr/ops/opsPlus/era` 각 5건 포함
- [x] 실제 API 계측: `leaderboard avg/hr/ops/opsPlus/era`는 24~30건, unsupported `war`는 빈 목록으로 종료
- [x] 실제 API 계측: `KT/SS/LG/HT/SK/WO/LT/HH/NC/OB` 팀 기록 합본이 모두 선수 60명 이상과 팀 타격/투수 스탯을 반환
- [x] 웹 smoke 산출물: `artifacts/kbo-records-check/records-tab-overview-v2.png`, `artifacts/kbo-records-check/records-team-after-click-v2.png`

### 메모
- 기록실 직접 URL(`/records`, `/records/team/*`, `/records/leaderboard/*`)은 web boot 단계에서 `/home`으로 되돌거나 `Page Not Found`가 나는 deep-link 문제가 별도로 관찰됐다. 하단 탭/앱 내 네비게이션은 동작하지만, web preview/release 딥링크 안정화는 후속 과제로 분리한다.

---

## 2026-05-19: v4 Moment Subscription 실제 앱 반영

### 완료
- [x] `docs/design/kbo-fans-mobile-ui-alerts-outside-v4-2026-05-19/preview.png` 기준의 Moment Subscription / Surface Strategy를 실제 Flutter 화면에 맞춤
- [x] 앱 전역 색상/카드/입력/버튼 테마를 v4 보드의 `#07090C`, `#10141A`, `#171D24`, `#323A45`, `#2979FF`, `#FF4444` 체계로 정리
- [x] 설정 화면을 `알림 플레이북` 중심으로 정리하고 Moment별 `바로 / 요약 / Live만 / 끄기` 전달 방식을 v4 카드 톤으로 표시
- [x] 경기 상세 라이브 화면의 `경기 따라가기`를 Live 표면 / Push / Widget 역할 분리형 CTA로 보강
- [x] 홈, 일정, 기록실, 온보딩의 모바일 폭, 카드 반경, 헤더 구조, 하단 탭 밀도를 v4 보드의 compact dark sports tone에 맞춰 유지
- [x] 하단 탭을 `홈 / 일정 / 순위 / 기록실 / 설정` 순서와 작은 outline icon 상태로 정리

### 검증
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/services/push_notification_service_test.dart test/widget_test.dart`
- [x] local FastAPI + web static preview 390x844 캡처 확인: 홈, 일정, 기록실, 설정, 경기 상세

### 메모
- 이전 빌드/브라우저 캐시에서는 문서 시안만 있고 Flutter UI가 일부만 반영된 상태로 보일 수 있어, web service worker/cache를 지우고 새 번들로 확인해야 한다.
- v4 기준은 알림 강도 다이얼이 아니라 야구 장면 Moment와 전달 표면 분리다. Push는 즉시 이벤트, Live 표면은 따라가는 경기 상태, Widget은 개인화 상태판 역할로 제한한다.

---

## 2026-05-19: Compact scoreboard / 앱 밖 refresh 루프 축소

### 완료
- [x] 백엔드 `/scoreboard/compact` endpoint 추가
- [x] compact endpoint가 위젯/Live 표면용으로 최대 1경기만 선택하고, 해당 경기만 enrich하도록 구현
- [x] 최초 실행 remote prefetch가 홈 진입을 막지 않도록 blocking startup prefetch 비활성화
- [x] 위젯 background refresh가 일반 API 모드에서 `/scoreboard/compact`를 우선 사용하도록 변경
- [x] 위젯 sync에서 relay/current-at-bat 조회를 제거해 위젯 갱신이 별도 문자중계 크롤링 루프가 되지 않도록 정리
- [x] Live Activity sync 내부의 direct KBO current-at-bat fallback 제거
- [x] KBO live scoreboard detail payload의 총점이 비어 있을 때 이닝별 점수 합산으로 `score`를 보정
- [x] 단건 경기 상세가 오늘/미래 경기의 오래된 `games/{gameId}` snapshot을 먼저 반환하지 않도록 수정
- [x] 경기 종료 전환 직후 KBO scroll scoreboard가 비어도 `LiveTextView1` 이닝표와 main score로 상세 스코어를 보정
- [x] 앱 상세 캐시 키를 `game_detail_v2:{gameId}`로 올려 기존 0:0 상세 캐시를 재사용하지 않도록 조정
- [x] v4 delivery 모델에 맞춰 immediate Moment만 direct push topic을 만들도록 테스트 기대값 갱신
- [x] `docs/APP_SPEC.md`, `docs/KBO_DATA_REFRESH_ARCHITECTURE_2026-05-19.md`에 compact endpoint와 남은 Live state 과제 반영

### 검증
- [x] `backend/.venv/bin/python -m compileall backend/src`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_scoreboard_service_cache.py backend/tests/test_games.py backend/tests/test_snapshot_services.py`
- [x] `backend/.venv/bin/pytest -q`
- [x] 실제 KBO upstream을 타는 service 계측: 2026-05-19 기준 home cold는 detail/view1 각 5회, compact cold는 각 1회로 감소 확인
- [x] 실제 KBO live 경기 기준 service 계측: LG-KIA `20260519LGHT0` 응답이 390ms 수준으로 종료되고, 점수 `LG 0 : 12 KIA` 계산 확인
- [x] 실제 KBO 종료 전환 경기 기준 service/API/web 상세 계측: KT-삼성 `20260519KTSS0`이 `FINAL`, `KT 2 : 10 삼성`, 이닝표/H/E/B 포함으로 렌더됨 (`artifacts/kbo-live-loading-check/detail-ktss-final-transition-fixed.png`)
- [x] 로컬 web release + FastAPI + system Chrome headless 390x844 smoke: 첫 실행 seed 상태에서 blocking loader가 사라지고 홈 live 카드가 렌더됨 (`artifacts/kbo-live-loading-check/home-lg-nonblocking-fixed-score.png`)
- [x] `cd app && fvm dart format --set-exit-if-changed lib/data/repositories/api_game_repository.dart lib/services/widget_sync_service.dart lib/services/live_activity_service.dart lib/features/settings/settings_screen.dart test/services/push_notification_service_test.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/widget_test.dart test/data/models/records_overview_test.dart test/services/push_notification_service_test.dart`

### 메모
- Live Activity의 batter/pitcher/B-S-O 표시는 client direct crawl로 채우지 않고, 추후 backend-owned compact live state payload로 복구하는 쪽이 맞다.
- `settings_screen.dart`의 `SizedBox(minHeight:)`는 현재 Flutter API에 없는 파라미터라 전체 analyze를 막고 있어 `ConstrainedBox`로 같은 의도를 유지해 수정했다.

---

## 2026-05-19: 알림 플레이북 / 앱 밖 경험 v4 앱 반영

### 완료
- [x] 설정 화면의 단순 알림 토글을 Moment별 `바로 / 요약 / Live만 / 끄기` 전달 방식 선택 UI로 전환
- [x] 기본 플레이북을 `경기 시작/경기 종료/라인업=요약`, `득점/홈런/역전=바로`, `이닝 교대=Live만`으로 정리
- [x] 앱 시작 시 OS 알림 권한을 바로 요청하지 않고, `권한 확인`, `바로 알림`, `경기 따라가기` 같은 명시적 사용자 action 이후에만 요청하도록 변경
- [x] 로컬 경기 이벤트 알림과 FCM topic 구독이 `바로 알림` Moment만 대상으로 삼도록 조정
- [x] 경기 상세 라이브 경기 헤더 아래에 `경기 따라가기` CTA를 추가하고, Live Activity는 사용자가 선택한 경기만 동기화하도록 변경
- [x] `docs/APP_SPEC.md`, `docs/FIGMA_PROMPT.md`, `CHANGELOG.md`를 실제 구현된 Moment 목록과 기본값에 맞춰 동기화

### 검증
- [x] `cd app && fvm dart format lib/services/push_notification_service.dart lib/services/game_event_alert_service.dart lib/services/live_activity_service.dart lib/features/game_detail/game_detail_screen.dart lib/features/settings/settings_screen.dart test/services/push_notification_service_test.dart`
- [x] `cd app && fvm flutter analyze lib/services/push_notification_service.dart lib/services/game_event_alert_service.dart lib/services/live_activity_service.dart lib/features/game_detail/game_detail_screen.dart lib/features/settings/settings_screen.dart test/services/push_notification_service_test.dart`
- [x] `cd app && fvm flutter test test/services/push_notification_service_test.dart test/widget_test.dart`

---

## 2026-05-19: 실시간/스냅샷 데이터 분리 및 중복 로딩 기술 검토

### 완료
- [x] `docs/KBO_DATA_REFRESH_ARCHITECTURE_2026-05-19.md`에 live / warm cache / persisted snapshot / bundled bootstrap 데이터 분류 기준 문서화
- [x] 백엔드 service/crawler/cache/snapshot 책임 경계와 endpoint별 freshness matrix 정리
- [x] 반복 크롤링 방지를 위한 singleflight, rate-limit, stale-while-revalidate, request budget 설계안 정리
- [x] 홈, 일정, 경기 상세, Score/Relay/Boxscore/Lineup 탭, 기록실 화면의 현재 over-fetch 후보와 목표 호출 구조 검토
- [x] 실제 파일/라인 기준 evidence map 추가
- [x] widget background, local alert, direct KBO repository, backend route fan-out까지 추가 검토
- [x] P0/P1/P2 구현 순서와 구현 후 request count 목표치 정리

### 원인
- 실시간 데이터와 과거/기록성 데이터를 한 정책으로 처리하면, live freshness를 잃거나 반대로 안정 데이터까지 매번 KBO 웹을 다시 긁게 된다.
- 일부 화면은 실제로 필요한 payload보다 넓은 provider를 구독하거나 preload를 통해 detail/relay/boxscore/lineup/player data를 한꺼번에 데우고 있어 로딩 중첩과 upstream 부담이 생길 수 있다.
- 화면 외에도 widget background refresh와 local alert processing이 별도 실시간 refresh surface가 될 수 있어, 화면 provider만 줄여서는 전체 KBO 호출량을 통제할 수 없다.

### 검증
- [x] 관련 코드 경로 확인: `app/lib/data/providers.dart`, `app/lib/features/home/home_screen.dart`, `app/lib/features/schedule/schedule_screen.dart`, `app/lib/features/game_detail/*`, `app/lib/services/game_detail_preload_service.dart`, `backend/src/kbo_fans_backend/services/*`
- [x] 추가 코드 경로 확인: `app/lib/services/widget_sync_service.dart`, `app/lib/services/game_event_alert_service.dart`, `app/lib/data/repositories/kbo_direct_repository.dart`, `backend/src/kbo_fans_backend/api/routes/*`
- [x] 문서 변경 범위 확인: `docs/KBO_DATA_REFRESH_ARCHITECTURE_2026-05-19.md`

---

## 2026-05-18: KBO 원천 웹 의존도 완화 1차 보강

### 완료
- [x] `docs/KBO_DATA_RESILIENCE_PLAN_2026-05-18.md`에 live / warm cache / persisted snapshot / bundled bootstrap 기준 정리
- [x] 월간 일정 API가 성공한 비어 있지 않은 payload를 항상 schedule snapshot으로 남기도록 조정
- [x] 기록실 leaderboard API가 `leaderboard/{season}:{metric}` snapshot을 저장/조회하도록 보강
- [x] 앱 leaderboard API 실패 시 bundled records overview snapshot에서 metric별 리더보드를 복구하도록 fallback 추가

### 원인
- KBO 공식 웹/HTML/ASMX 응답은 느리거나 마크업이 바뀌기 쉬운데, 일부 경로가 요청 시점 recrawl 또는 direct KBO fallback에 의존했다.
- 일정 snapshot 저장 조건이 모든 경기가 종료된 월로 제한되어, 현재 월 KBO 일정 원천이 깨졌을 때 재사용할 마지막 정상 월 payload가 부족할 수 있었다.
- records overview는 snapshot-first였지만 leaderboard 단건 endpoint는 snapshot 저장/조회가 없어 같은 기록 데이터를 다시 원천 호출할 여지가 있었다.

### 검증
- [x] `cd backend && uv run --with pytest pytest tests/test_schedule.py tests/test_records_overview.py tests/test_snapshot_services.py -q`
- [x] `cd backend && python3 -m compileall src tests/test_schedule.py tests/test_records_overview.py`
- [x] `cd app && fvm flutter analyze lib/data/repositories/api_player_repository.dart`

---

## 2026-04-25: 박스스코어 주자 상태 `-` 표시 보정

### 완료
- [x] direct KBO relay parser가 베이스 이미지에서 `ground_base*.png`를 못 읽고 `alt="주자"`만 받은 경우, 1/2/3루 주자 이름으로 주자 상태를 재구성하도록 보강
- [x] 박스스코어 라이브 요약의 `주자` 타일이 `baseState`가 비어 있어도 주자 이름 필드로 `주자1루`, `주자1,3루`, `만루` 등을 표시하도록 보정
- [x] 문자중계 현재 타석 배지도 같은 fallback을 사용하도록 맞춰 표시 일관성 개선
- [x] 백엔드 relay crawler도 동일하게 주자 이름 기반 baseState fallback을 추가

### 원인
- KBO live text HTML에서 주자 이미지가 `ground_base*.png` 형태로 오면 정상 표시됐지만, 일부 응답에서는 `alt="주자"`만 남아 parser가 빈 문자열로 처리했다
- 박스스코어 탭은 빈 `baseState`를 `-`로 표시했기 때문에 실제 주자가 있어도 `-`로 보일 수 있었다

### 검증
- [x] `cd app && fvm flutter analyze lib/data/repositories/kbo_direct_repository.dart lib/features/game_detail/tabs/boxscore_tab.dart lib/features/game_detail/tabs/relay_tab.dart`
- [x] `cd app && fvm flutter test test/widget_test.dart`
- [x] `cd backend && uv run --with pytest pytest tests/test_relay_crawler.py -q`
- [x] `cd backend && python3 -m compileall src tests/test_relay_crawler.py`

---

## 2026-04-25: 라인업 선발투수 프로필 이미지 보강

### 완료
- [x] 라인업 데이터 모델에 선발투수 id/imageUrl 후보를 추가
- [x] 앱 direct KBO 라인업 생성 시 `Main.asmx/GetKboGameList`의 `T_PIT_P_ID` / `B_PIT_P_ID`로 선발투수 이미지 URL을 즉시 구성하도록 보강
- [x] 백엔드 라인업 API도 main game 메타데이터에서 선발투수 id/name/imageUrl을 함께 내려주도록 보강
- [x] 라인업 탭 이미지 매칭을 선수목록 `imageUrl`뿐 아니라 선수 id 기반 CDN URL, 현재 타석 relay 이미지, 괄호/표기 변형 제거 매칭까지 사용하도록 개선
- [x] 상세 선로딩 서비스가 선발투수 id/imageUrl 기반 이미지를 미리 캐시하도록 보강

### 원인
- 선발 카드가 이름 기반 선수 이미지 맵에 의존해, 선수목록 로딩 지연/실패 또는 이름 표기 변형이 있으면 즉시 fallback 글자 카드로 떨어질 수 있었음
- 실제 KBO main game payload에는 선발투수 id가 이미 있으므로, 선수목록 조회와 무관하게 `person/middle/{season}/{playerId}.jpg` URL을 만들 수 있었음

### 검증
- [x] `cd app && fvm flutter analyze lib/data/models/boxscore.dart lib/data/repositories/api_game_repository.dart lib/data/repositories/kbo_direct_repository.dart lib/features/game_detail/tabs/lineup_tab.dart lib/services/game_detail_preload_service.dart`
- [x] `cd app && fvm flutter test test/widget_test.dart`
- [x] `cd backend && uv run --with pytest pytest tests/test_lineup.py tests/test_schedule.py -q`
- [x] `cd backend && python3 -m compileall src tests/test_lineup.py`

---

## 2026-04-25: 문자중계 로딩 대기 고착 방지

### 완료
- [x] direct KBO 문자중계가 경기 전체 스코어보드 조회를 먼저 기다리지 않고 `Main.asmx` 메타데이터와 live text 요청으로 바로 진입하도록 조정
- [x] `LiveText.aspx` / `LiveTextView2.aspx` 문자중계 요청은 startup/history warm 의 전역 KBO 요청 queue 를 우회하도록 조정
- [x] 세션 준비용 `LiveText.aspx` GET 은 2초 안에 끝나지 않으면 건너뛰고 실제 중계 데이터인 `LiveTextView2.aspx` POST 로 진행하도록 조정
- [x] 문자중계 요청에 dedupe, timeout, 시작/완료 로그를 추가해 로딩 고착과 원인 추적성을 개선
- [x] 경기 상세 자동 새로고침이 진행 중일 때 같은 provider 를 반복 invalidate 하지 않도록 guard 추가
- [x] 라이브 경기 상세 자동 갱신 주기를 30초로 조정하고 종료/취소/서스펜디드 경기는 반복 갱신을 중단
- [x] direct 선수 목록 조회가 선수별 상세/누적기록 페이지를 대량 병렬 호출하지 않도록 정리하고, 선수 상세 화면에서만 상세 데이터를 조회하도록 조정

### 원인
- `getRelayData()`가 먼저 `getGame()`을 호출하면서 당일 전체 스코어보드와 각 경기 `GetScoreBoardScroll` 조회를 기다렸고, startup/history warm 요청이 동시에 쌓이면 문자중계가 사용자 탭 진입 뒤에도 뒤로 밀릴 수 있었음
- 상세 화면 타이머가 10~15초마다 relay provider 를 다시 invalidate 해, 느린 요청이 끝나기 전에 로딩 상태가 반복 갱신될 수 있었음
- 팀 선수 목록 direct fallback 이 선수마다 상세/누적기록 페이지를 동시에 요청해 KBO 원본 연결을 포화시키고, 문자중계 요청까지 timeout 가능성을 높였음

### 검증
- [x] `cd app && fvm flutter analyze lib/data/repositories/kbo_direct_repository.dart lib/data/repositories/kbo_direct_player_repository.dart lib/features/game_detail/game_detail_screen.dart`

---

## 2026-04-25: 경기 상세 데이터/이미지 선로딩

### 완료
- [x] 홈 스코어보드에서 마이팀/라이브/종료 경기 우선으로 최대 3경기의 상세 데이터를 백그라운드 선로딩하도록 추가
- [x] 일정 화면에서 선택 날짜의 상위 경기와 탭 직전 경기 상세 데이터를 선로딩하도록 추가
- [x] 경기 상세 진입 직후 문자중계/박스스코어/라인업 데이터를 미리 읽고, 라인업·문자중계·박스스코어에 등장하는 선수 프로필 이미지를 캐시에 올리도록 추가
- [x] 선로딩은 3분 TTL과 in-flight dedupe 를 적용해 같은 경기를 반복 요청하지 않도록 제한
- [x] 예정 경기는 팀 로고/기본 정보 중심으로 두고, 문자중계·박스스코어·라인업 선로딩은 라이브/종료 경기 위주로 제한

### 원인
- 문자중계/박스스코어 탭은 데이터 provider 가 준비되어도 선수 이미지는 실제 위젯 렌더 시점에 내려받아 첫 진입 체감이 늦을 수 있었음
- 홈/일정에서 이미 어떤 경기를 볼 가능성이 높은지 알 수 있으므로, 상세 진입 전에 핵심 payload 와 이미지 캐시를 미리 데우는 편이 체감 지연을 줄일 수 있음

### 검증
- [x] `cd app && fvm flutter analyze lib/services/game_detail_preload_service.dart lib/features/home/home_screen.dart lib/features/schedule/schedule_screen.dart lib/features/game_detail/game_detail_screen.dart`

---

## 2026-04-25: 일정 탭 당일 경기 상태 보정

### 완료
- [x] 앱 direct KBO 일정 월 조회 결과에 오늘 날짜 `Main.asmx/GetKboGameList` 메타데이터를 합쳐 진행 중 경기가 `경기 전`으로 보이지 않도록 수정
- [x] 백엔드 일정 API도 오늘 날짜 일정에 main game 상태/점수/구장 메타를 병합하도록 보강
- [x] synthetic gameId 가 main game id 와 정확히 일치하지 않는 경우에도 원정/홈 팀 ID 기준으로 main game 을 매칭하도록 보완

### 원인
- `GetScheduleList` 기반 일정 월 데이터는 진행 중에도 action/status 값이 `SCHEDULED` 상태로 남을 수 있었고, 기존 보강 로직은 종료 경기 점수 누락만 처리했다
- 실제 진행 상태는 `Main.asmx/GetKboGameList`의 `GAME_STATE_SC=2`에 있으므로 일정 탭도 이 메타데이터를 합쳐야 했다

### 검증
- [x] `cd app && fvm flutter analyze lib/data/repositories/kbo_direct_repository.dart lib/features/schedule/schedule_screen.dart lib/features/schedule/widgets/schedule_game_card.dart`
- [x] `cd backend && uv run --with pytest pytest tests/test_schedule.py -q`
- [x] `cd backend && python3 -m compileall src tests/test_schedule.py`

---

## 2026-04-02: 문자중계 선수 프로필/볼카운트 시각화 강화

### 완료
- [x] 경기 상세 `문자중계`의 현재 타석 카드에 B/S/O를 숫자+색상 요약 카드로 재구성
- [x] 현재 타석의 타자/투수 프로필 이미지 우선순위를 정리해 direct relay 이미지와 선수 이미지 맵 fallback을 함께 사용
- [x] 문자중계 주요 플레이 카드에 주체 선수 아바타를 추가
- [x] 문자중계 타석 카드를 방송형 레이아웃으로 재구성해 회차 헤더, 상대투수/상대팀, 선수 프로필, 플레이 결과, 순번형 투구 로그가 한 카드 안에 보이도록 조정
- [x] 투구 로그를 `N구` 기준으로 다시 보여주고, 볼/스트라이크/파울 결과 배지와 누적 B/S 카운트 요약을 같이 노출
- [x] 문자중계 이닝 칩을 `전체 / N회초 / N회말` 선택형 필터로 바꿔 회차별 중계만 따로 볼 수 있게 조정
- [x] 박스스코어의 `핵심 타자` / `핵심 투수` 카드에 선수 프로필 이미지와 고대비 텍스트 스타일을 적용
- [x] iOS 잠금화면 Live Activity에서 스코어 컬럼이 화면 양끝으로 벌어지지 않도록 중앙 정렬 그룹으로 조정
- [x] iOS 잠금화면 Live Activity와 iOS 위젯 점수 영역에 팀 로고가 보이도록 팀 ID 동기화와 SwiftUI 로고 렌더 추가
- [x] iOS 잠금화면 Live Activity와 iOS 위젯에 현재 타석 타자/투수와 투구 수(`N구`)가 함께 보이도록 payload와 표시 라인 확장
- [x] 홈 `지금 보면 좋은 정보`의 선수 카드 탭 시 최근 기록 요약 바텀시트를 먼저 보여주고 선수 상세로 이어지게 조정
- [x] `docs/APP_SPEC.md`, `CHANGELOG.md`에 문자중계 UI 변경사항 반영

### 원인
- 기존 문자중계 탭은 현재 타석 카드에 선수 정보가 일부 있었지만, 개별 중계 이벤트에서는 누구 플레이인지 시각적으로 즉시 연결되기 어려웠음
- 투구 로그는 텍스트만 보여서 `1구 스트라이크`, `2구 파울` 이후 현재 카운트가 어떻게 누적됐는지 한 번에 읽기 어려웠음

### 검증
- [x] `cd app && fvm flutter analyze lib/features/game_detail/tabs/relay_tab.dart`

### 비고
- 투구 로그의 누적 카운트는 pitch text(`N구`, `볼`, `스트라이크`, `파울`)를 기준으로 UI에서 계산해 표시한다
- pitch 로그별 아웃 수는 원문 데이터가 충분하지 않아 이번 단계에서는 현재 타석 카드의 B/S/O 강조를 우선 유지했다

---

## 2026-04-02: 푸시 토픽 동기화 오작동 방지

### 완료
- [x] 마이팀 미선택 상태에서는 마이팀 이벤트 푸시 토픽을 구독하지 않도록 조정
- [x] FCM 토큰 갱신 시 초기 캡처값이 아니라 현재 저장된 마이팀 기준으로 재동기화하도록 수정

### 원인
- 기존 구현은 `myTeam == null` 인 상태에서 `*_ALL` 토픽 이름을 만들어 사실상 리그 전체 이벤트를 받게 될 수 있었음
- 토큰 refresh 리스너가 `initialize()` 시점의 `myTeam` 값을 캡처해, 이후 응원팀 변경 뒤 토큰이 바뀌면 예전 팀 기준으로 재구독할 여지가 있었음

### 검증
- 코드 경로 기준으로 `setTeam()` 이후 `syncRegistration()` 이 저장된 `myTeam` 과 동일한 값을 사용하도록 확인
- 토큰 refresh 경로가 `syncRegistration(forceToken: ...)` 를 통해 최신 저장 팀을 다시 읽도록 확인

---

## 2026-04-02: 종료 경기 예매 정보 숨김

### 완료
- [x] 경기 상세에서 종료/취소/서스펜디드 경기는 예매 정보 카드를 숨기도록 조정
- [x] 일정 카드에서 종료/취소/서스펜디드 경기는 예매 요약을 숨기도록 조정
- [x] 백엔드 `ticketInfo` 생성 로직이 종료 상태에서는 값을 내려주지 않도록 정리
- [x] 종료 경기 예매 비노출 정책을 문서와 테스트에 반영

### 검증
- Flutter 위젯 테스트에 종료 경기 예매 비노출 케이스 추가
- 백엔드 테스트에 `FINAL` 상태 `ticketInfo is None` 케이스 추가

### 비고
- 기존 캐시/스냅샷에 `ticketInfo`가 남아 있더라도 앱 UI에서 종료 상태면 한 번 더 숨기도록 방어 처리

---

## 2026-03-31: 에이전트 메모와 저장소 스킬 정리

### 완료
- [x] `AGENTS.md`에 런타임/운영 메모 추가
- [x] `CLAUDE.md`에 동일한 저장소 운영 인사이트 반영
- [x] 반복 가능한 작업을 `.claude/skills/` 로 분리
  - `kbo-runtime-data`
  - `kbo-release-flow`
  - `app-startup-runtime-triage`
  - `ios-device-run-action`

### 반영 인사이트
- 웹/release 는 backend API 경로를 기본으로 사용
- 로컬 네이티브는 direct crawler 경로를 디버깅 목적에 한해 사용 가능
- home first paint 는 경량 payload / cache 우선
- historical standings/records/completed games 는 snapshot 우선
- push 실패 시 `github-personal` SSH alias 경로 사용
- local Android API 연결은 `10.0.2.2` 를 기본값으로 보는 편이 안전함
- 실기기 실행 이슈는 `flutter devices` 와 `xcodebuild -showdestinations` 를 같이 봐야 함

---

## 2026-03-31: 인사이트 문서화 및 Claude 스킬 추출

### 완료
- [x] 최근 캐시/snapshot/문서 동기화 인사이트를 `docs/ENGINEERING_NOTES.md`로 정리
- [x] `.claude/skills/kbo-history-snapshot/SKILL.md` 추가
- [x] `.claude/skills/kbo-doc-sync/SKILL.md` 추가
- [x] `.claude/SKILL_REFERENCE.md` 추가
- [x] `AGENTS.md`, `CLAUDE.md`에 새 인사이트와 skill 진입점 연결

### 원인
- 최근 작업에서 히스토리 데이터 snapshot 우선 전략과 문서 동기화 규칙이 반복적으로 등장했고, 매번 대화로만 유지하면 다음 세션에서 쉽게 누락될 수 있었음
- repo-local Claude skill 체계가 이미 일부 존재했기 때문에, 새로 얻은 반복 패턴도 같은 위치에 편입하는 편이 유지보수에 유리했음

### 비고
- 이번 단계는 코드 실행 경로 변경이 아니라 컨텍스트/워크플로우 정리 작업이다
- 새 skill 은 Claude 로컬 기준 진입점이고, Codex 쪽은 `AGENTS.md`와 문서 연결로 함께 발견 가능하도록 맞췄다

---

## 2026-03-31: 웹 UX/UI 점검 및 10개 페르소나 분석

### 완료
- [x] Flutter 웹 디버그 세션 실제 실행
- [x] `#/onboarding`, `#/home`, `#/schedule`, `#/standings`, `#/settings` 라우트 실측
- [x] 홈 화면 네트워크 호출(`scoreboard`, `schedule`, `standings`, `records/overview`) 확인
- [x] 10개 유저 페르소나 기준 UX/UI 개선점 문서화 (`docs/UX_AUDIT_2026-03-31.md`)
- [x] `README.md`의 웹 플랫폼 존재 여부 문구 최신화
- [x] 웹에서 모바일 화면이 과도하게 늘어나지 않도록 공통 `AppPageFrame` 추가
- [x] 온보딩 카드 밀도와 설명 문구 조정
- [x] 홈 마이팀 미선택 CTA와 오늘의 야구 빠른 액션 보강
- [x] 일정 화면에 달력 범례 추가
- [x] 순위 화면에 마이팀 요약 카드 추가
- [x] 설정 화면에 알림 설명문과 토글별 보조 문구 추가
- [x] 순위/기록실 요약 시즌별 번들 스냅샷 fallback(`2001~현재`) 추가
- [x] 앱 부트스트랩에 timeout/fallback 을 추가해 shared preferences 응답 지연 시 무한 스플래시를 피하도록 보강
- [x] 웹 HTML 스플래시에 DOM 감지/timeout 제거 fallback 추가
- [x] 정적 빌드 기반 `web-static` 프리뷰 스크립트 추가
- [x] 기본 `codex-run-web.sh` 를 정적 프리뷰 기준으로 전환하고 `codex-run-web-dev.sh` 추가
- [x] 게임 상세 UI 의도를 `docs/GAME_DETAIL_UI_NOTES.md` 로 문서화
- [x] 기기 단독모드 디버깅 메모를 `docs/GAME_DETAIL_DEBUG_NOTES.md` 로 문서화

### 확인 사항
- `flutter run -d chrome` 디버그 세션은 정상 렌더링됨
- `flutter run -d web-server --web-port 7357` 는 일반 Chrome 기준으로 Flutter view 가 뜨지 않아 안정적인 검증 경로로 보기 어려움
- 웹 프리뷰는 `./scripts/codex-run-web-static.sh` 또는 `./scripts/codex-run.sh web-static` 기준으로 사용하는 쪽이 안전함
- Codex 액션 기본 웹 실행 경로는 `./scripts/codex-run-web.sh`, Chrome 디버그가 필요하면 `./scripts/codex-run-web-dev.sh`
- 실제 시각 검증 기준으로 홈은 정보 구조가 풍부하지만 첫 화면 우선순위 정리가 더 필요함

### 검증
- [x] `cd app && fvm flutter analyze --no-fatal-infos`
- [x] `cd app && fvm flutter test`

### 비고
- macOS 앱 포커스 경쟁 때문에 기록실/경기 상세는 안정적인 스크린샷 확보가 제한됐고, 해당 영역은 코드 구조와 라우트 접근 가능 여부를 함께 참고해 판단함

## 2026-03-31: 히스토리 데이터 선수집 / 스냅샷 우선 전략 명문화

### 완료
- [x] `docs/APP_SPEC.md`에 live / warm cache / persisted snapshot 3계층 데이터 전략 추가
- [x] 선수 과거 기록, 지난 경기 결과, 지난 날짜 순위를 원천 재크롤링보다 저장된 스냅샷 우선으로 응답한다는 정책 명시
- [x] 선수 상세 / 일정 / 순위 화면 운영 메모에 히스토리 데이터 선계산 및 재검증 원칙 반영
- [x] `README.md`, `CHANGELOG.md`에 로딩 체감 개선을 위한 snapshot 우선 운영 방침 반영

### 원인
- 현재 문서는 홈 `30초 TTL`, 기록실 `5분 TTL` 정도까지만 정의되어 있었고, 과거 데이터까지 매 요청 시점 수집 대상으로 볼 여지가 있었음
- 사용자 경험 관점에서는 지난 경기, 지난 순위, 선수 과거 기록은 앱 진입 즉시 보여야 하고, 이 영역에 매번 크롤링 지연이 걸리면 제품 방향인 "열면 바로 야구"와 충돌함
- KBO 원천 응답은 느리거나 불안정할 수 있어, 종료 경기/히스토리 영역은 수집 시점과 조회 시점을 분리하는 쪽이 운영 안정성에도 유리함

### 비고
- 이번 단계는 문서/아키텍처 결정 반영이며, 실제 DB snapshot 스키마와 배치 작업 구현은 후속 개발 범위다
- 공개 API 계약은 유지하고, 서버 내부 응답 전략을 live cache 중심에서 snapshot 우선 구조로 확장하는 기준만 먼저 확정했다

---

## 2026-03-31: 마이팀 경기 이벤트 로컬 알림 추가

### 완료
- [x] 홈 스코어보드 갱신 시 마이팀 경기 시작 / 득점 / 역전 / 경기 종료를 감지하는 로컬 알림 서비스 추가
- [x] 기존 설정 화면의 `경기 시작 / 득점 / 역전 / 경기 종료` 토글을 로컬 이벤트 감지 기준으로 재사용
- [x] 점수 변화 비교용 스냅샷을 로컬에 저장해 중복 알림을 줄이도록 정리

### 비고
- 이 방식은 원격 푸시가 아니라 앱 실행 중 또는 갱신 주기 시점 기준의 best-effort 로컬 알림임
- 홈 폴링 주기를 따르므로 완전 실시간 보장은 안 됨
- 홈런 전용 알림은 scoreboard만으로는 확정이 어려워 이번 단계에서는 별도 미구현

## 2026-04-01: 로컬 경기 이벤트 알림 확장

### 완료
- [x] `local` 환경에서도 홈 스코어보드 갱신 시 로컬 경기 이벤트 알림이 동작하도록 홈 화면 호출 조건 정리
- [x] 홈런 알림을 relay event 비교 기준으로 구현
- [x] 이닝 교대 알림을 relay `INNING_CHANGE` 비교 기준으로 구현
- [x] 라인업 공개/변경 알림을 lineup signature 비교 기준으로 구현
- [x] 설정 화면에 `라인업`, `이닝 교대` 토글 추가
- [x] push registration payload 와 backend schema 에 `lineupOpened`, `inningChange` 설정값 반영
- [x] `fvm flutter analyze` 대상 파일 무이슈 확인

### 비고
- 로컬 알림은 여전히 앱 refresh 주기 기반 best-effort 이며 서버 push 대체는 아님
- `리그 전체 알림`이 켜져 있으면 마이팀 외 경기에도 동일한 로컬 이벤트 알림을 적용

---

## 2026-03-31: 예매 오픈 로컬 알림 다단계 예약

### 완료
- [x] 예매 오픈 로컬 알림을 하루 전 / 1시간 전 / 10분 전 3단계로 예약하도록 변경
- [x] 예매 알림 해제 시 예약된 3개 리마인드를 모두 취소하도록 정리
- [x] 예약 결과 메시지에 실제로 설정된 리마인드 시점을 표시하도록 보완

---

## 2026-03-31: relay 테스트 안정화 / 상태 라벨 공통화

### 완료
- [x] `tests/test_relay_service.py`가 실제 `RelayCrawler` 네트워크 결과에 흔들리지 않도록 fallback 검증용 failing stub 추가
- [x] 백엔드 전체 `pytest` 기준 `relay_service` 2건 실패 해소
- [x] 앱 상태 라벨 매핑을 공통 유틸로 분리해 일정 화면이 이를 재사용하도록 정리
- [x] 홈/상세 fallback 상태 문구도 공통 상태 라벨 유틸을 재사용하도록 정리
- [x] 홈 spotlight/status chip 과 홈 경기 카드도 공통 상태 배지 컴포넌트를 사용하도록 통일
- [x] 일정 카드 위젯을 분리하고 상태 라벨/점수/서스펜디드 정책 회귀 방지 widget test 추가
- [x] 일정 카드 골든 테스트와 기준 이미지 추가
- [x] 날짜별 스코어보드 응답을 30초 TTL 캐시에 보관하고 경기별 enrich 를 병렬화해 홈 재진입 속도 개선
- [x] 홈/기록실 실측 지표를 `/api/metrics/client` 로 서버에 전송하고 `backend/logs/client_metrics.log` 에 저장하도록 추가
- [x] KBO 원본 호출 공통 베이스에 circuit breaker 를 넣고 주요 홈/기록실 경로 crawler 를 이를 사용하도록 정리
- [x] scoreboard / team stats / team players 에 stale cache fallback 을 추가해 KBO 원본 실패 시 직전 정상 응답을 재사용하도록 보강
- [x] 웹 `API 진단` 화면을 추가해 `health / scoreboard / schedule` 상태를 한 번에 확인 가능하도록 구현
- [x] README / APP_SPEC 에 운영 메모, 캐시 TTL, 로그 위치, 진단 화면 정보를 반영
- [x] 친구/테스터 배포 경로를 정리한 `docs/DISTRIBUTION_GUIDE.md` 추가
- [x] `docs/DISTRIBUTION_GUIDE.md`에 iOS TestFlight / Android 내부 테스트 실제 업로드 순서 추가
- [x] `docs/ANDROID_SIGNING_GUIDE.md` 추가
- [x] `docs/IOS_TESTFLIGHT_CHECKLIST.md` 추가
- [x] Android release signing 을 `key.properties` 기반 구조로 정리
- [x] `.claude/skills/app-distribution/SKILL.md` 추가
- [x] `.claude/SKILL_REFERENCE.md`에 `app-distribution` 추가
- [x] 배포 / 액션 등록 관련 인사이트를 `AGENTS.md`, `CLAUDE.md`에 반영
- [x] 구현 인사이트 정리용 `docs/ENGINEERING_NOTES.md` 추가
- [x] 반복 작업을 위한 `.claude/skills/ios-live-activity-widget`, `.claude/skills/mobile-preview-release` 추가
- [x] `AGENTS.md`, `CLAUDE.md` 에 문서/스킬 진입점 반영

### 검증
- [x] `cd backend && source .venv/bin/activate && pytest -q`
- [x] `cd app && fvm flutter analyze --no-fatal-infos`
- [x] `cd app && fvm flutter test test/features/schedule/widgets/schedule_game_card_test.dart`
- [x] `cd app && fvm flutter test test/features/schedule/widgets/schedule_game_card_golden_test.dart`
- [x] `/api/scoreboard?date=2026-03-31` 실측
  - 첫 호출: 약 0.184초
  - 캐시 적중 후: 약 0.003초

---

## 2026-03-30: 홈 화면 브리프/요약 구조 1차 추가

### 완료
- [x] 홈 상단에 `마이팀 브리프` 카드 추가
- [x] 홈 상단에 `오늘의 야구` 요약 카드 추가
- [x] 홈 상단에 `빠른 콘텐츠` 카드 섹션 추가
- [x] 경기 없는 날에도 홈이 비어 보이지 않도록 빈 상태 구조를 브리프 중심으로 보완
- [x] 홈 브리프 데이터에 마이팀 순위, 최근 흐름, 리그 리더/오늘의 플레이어 요약 반영

### 원인
- 기존 홈은 사실상 스코어보드 전용 화면이라 경기 없는 날이나 마이팀 경기가 없는 날에 화면이 지나치게 비어 보였음
- 앱을 열자마자 야구 맥락이 전달되기보다, 경기 카드가 없으면 볼 정보가 거의 없었음

### 검증
- [x] `cd app && fvm flutter analyze --no-fatal-infos`
- [x] `cd app && fvm flutter test`
- [x] 웹에서 홈 화면 브리프 카드 렌더링 확인

---

## 2026-03-31: 원격 푸시 경로 연결

### 완료
- [x] 앱에 Firebase 초기화 및 FCM 토큰/토픽 동기화 서비스 추가
- [x] 마이팀 변경 시 푸시 토픽 재구독 및 `/api/push/register` 재등록 연결
- [x] 설정 화면 알림 토글을 SharedPreferences에 저장하고 푸시 구독과 연동
- [x] Android 13+ `POST_NOTIFICATIONS` 권한 선언 추가
- [x] 백엔드 `/api/push/test` 테스트 발송 endpoint 추가
- [x] 백엔드 Firebase Admin 서비스 계정 경로/프로젝트 ID 설정 추가
- [x] 진단 화면에 푸시 초기화/토픽 상태 표시 추가

### 비고
- 실제 원격 푸시 수신까지는 앱의 Firebase 설정 파일(`GoogleService-Info.plist`, `google-services.json`)과 백엔드 서비스 계정 JSON이 필요
- 현재 코드 경로는 연결됐지만, 위 설정 파일이 없으면 런타임에서 초기화가 skip 될 수 있음

---

## 2026-03-30: 웹 하이라이트 재생 시 스크롤 잠김 수정

### 완료
- [x] 기록실 첫 화면 리더보드에 리그 홈런 순위 추가
- [x] 웹에서 하이라이트 인라인 재생 후 페이지 스크롤이 막히던 문제 수정
- [x] 웹 하이라이트를 인라인 재생하면서도 `스크롤 / 플레이어 조작` 모드 전환으로 스크롤 충돌을 피하도록 조정
- [x] 하이라이트 안내 문구와 버튼 라벨을 웹 동작에 맞게 조정

---

## 2026-03-30: 최초 로딩 체감 속도 개선

### 완료
- [x] 백엔드 `/api/scoreboard`가 `yyyyMMdd` 형식 날짜도 허용하도록 보강해 웹 홈 화면 날짜 포맷 예외 제거
- [x] 앱 시작 직후 홈, 일정, 순위, 기록실 핵심 데이터를 백그라운드 prefetch 하도록 조정
- [x] 기록실 팀 화면이 선수 목록과 팀 스탯을 별도 API 2개로 기다리지 않고 `/api/team/{teamId}/records` 합본 응답을 사용하도록 정리
- [x] 백엔드 기록실 크롤러에서 포지션별 선수 검색과 팀 타격/투수 스탯 수집을 병렬화해 최초 로딩 대기시간을 단축
- [x] 백엔드 `/api/team/{teamId}/records` endpoint 및 테스트 추가
- [x] 팀/시즌 기준 기록실 응답을 서비스 메모리 캐시에 5분 보관해 재진입 속도 개선
- [x] 웹 실행 검증 중 드러난 경기 상세 라인업 탭 파일 누락/생성자 불일치 문제 수정
- [x] 종료 경기 relay는 crawler 원문 대신 scoreboard 기반 summary relay를 우선 사용하도록 정리
- [x] live relay에서 crawler currentAtBat 가 비어 있으면 scoreboard current 정보로 보강하도록 수정
- [x] 예정 경기 `GetScoreBoardScroll` 응답에 `table2/table3` 가 없어도 홈 `/api/scoreboard` 가 500 없이 내려오도록 보강
- [x] 예정 경기 scoreboard fallback 에서 `inning` 이 `경기중` 으로 잘못 내려오지 않도록 `예정` 문구로 보정
- [x] 홈/순위 화면에서 raw `DioException` 대신 사용자용 에러 문구를 표시하도록 정리
- [x] 앱 API 요청 시간을 Dev Console 에 기록해 홈/기록실 병목을 확인할 수 있도록 보강
- [x] 기록실 서비스 캐시를 공통 TTL 캐시 유틸로 정리
- [x] 예정 경기에서는 YouTube 하이라이트 검색을 건너뛰어 불필요한 외부 요청 제거

### 원인
- 웹 검증 중 홈 화면 `scoreboard` 호출이 `20260330`처럼 하이픈 없는 날짜를 보내는 케이스가 확인됐고, 백엔드 `schedule` 조회는 `yyyy-MM-dd`만 가정하고 있었음
- 앱은 첫 진입 시 화면별로 필요한 데이터를 사용 시점에만 요청해서 하단 탭 첫 방문마다 네트워크 대기가 그대로 노출되고 있었음
- 기록실 팀 화면은 선수 목록과 팀 스탯을 각각 별도 요청으로 받았고, 백엔드도 일부 KBO 수집을 직렬로 처리하고 있었음
- 이 구조 때문에 기록실은 물론 일정/순위도 앱 실행 직후 첫 방문 체감이 무거웠음
- 실제 측정 결과 `LG` 기록실 합본 응답은 콜드 기준 약 8~11초가 걸려, 같은 팀 재진입도 서버 재수집이 반복되면 개선 폭이 작았음
- 웹 실행 검증 과정에서 `game_detail_screen.dart` 가 삭제된 `lineup_tab.dart` 를 import 하고 있어 앱 빌드 자체가 실패하고 있었음
- relay 서비스는 crawler 결과가 존재하면 그대로 반환하고 있었는데, 종료 경기에서는 테스트/UX가 기대하는 요약형 흐름과 다르게 원문 이닝 체인지 로그가 우선 노출될 수 있었음
- live 경기에서는 crawler 가 currentAtBat 를 비워 반환하는 경우에도 scoreboard current 정보로 보강하지 않아 현재 타석 정보가 비는 케이스가 있었음
- 홈 화면은 `/api/scoreboard` 를 직접 보는데, 예정 경기의 KBO scoreboard payload 에 `table2/table3` 가 없을 때 crawler 가 이를 무조건 참조하면서 `KeyError: table2` 로 500이 발생하고 있었음
- 홈 화면 에러 UI가 raw `DioException` 문자열을 그대로 노출하고 있어 사용자 관점에서 원인 파악이 어려웠음
- 기록실 캐시는 서비스별로 개별 구현이 중복돼 있어 TTL 정책을 바꾸거나 확장할 때 손볼 지점이 두 군데였음
- 예정 경기 scoreboard 에서도 YouTube 검색을 수행하고 있어 홈 첫 로딩 때 불필요한 외부 호출이 섞이고 있었음

### 검증
- [x] `cd backend && source .venv/bin/activate && pytest -q tests/test_teams.py`
- [x] `cd app && fvm flutter analyze --no-fatal-infos`
- [x] `http://127.0.0.1:3101/#/home`, `http://127.0.0.1:3101/#/records/team/LG` 웹 실행 확인
- [x] `http://127.0.0.1:8010/api/team/LG/records?season=2026` 응답 시간 측정
  - 첫 요청: 약 8.64초
  - 두 번째 요청: 0초대
- [x] `cd backend && source .venv/bin/activate && pytest -q`
- [x] `source .venv/bin/activate && PYTHONPATH=src python -c 'from kbo_fans_backend.services.scoreboard import ScoreboardService; print(ScoreboardService().get_scoreboard("2026-03-31")["games"][0]["status"])'`
- [x] `cd app && fvm flutter analyze --no-fatal-infos`

---

## 2026-03-30: 웹 기능 점검 및 기록실/설정 버그 수정

### 완료
- [x] Flutter 웹 앱을 실제 브라우저에서 실행해 홈, 일정, 경기 상세, 기록실, 설정 흐름 점검
- [x] 기록실 팀 선택 화면이 구단 10개의 선수 API를 동시에 호출하던 구조를 제거
- [x] 기록실 첫 화면에서 리그 리더보드/추천 선수만 먼저 보여주고, 팀 상세 진입 시에만 선수 데이터를 조회하도록 정리
- [x] 기록실 팀 상세가 웹에서 10초 API 타임아웃으로 비정상 실패하던 문제를 완화하기 위해 앱 API 타임아웃을 25초로 조정
- [x] 설정 화면의 `전체 경기 알림` 안내 문구가 스위치 상태와 반대로 보이던 문제 수정
- [x] 하이라이트 카드 타입/색상 처리, 미사용 import, deprecated API 사용 정리로 웹 analyze 경고 제거

### 원인
- 기록실 팀 선택 카드가 요약 문구를 만들기 위해 각 팀별 `teamPlayersProvider`를 모두 `watch`하고 있었음
- 웹에서는 첫 진입 시 `/api/team/{teamId}/players` 요청이 한꺼번에 발생해 타임아웃과 콘솔 노이즈가 생겼음
- KBO 크롤링 기반 선수/기록 API는 응답이 10초를 넘는 경우가 있어, 웹 Dio 클라이언트가 백엔드보다 먼저 요청을 중단하고 있었음
- 설정 화면은 `전체 경기 알림`이 꺼진 상태에서만 `마이팀 외 경기도 알림을 받습니다` 문구를 노출해 의미가 뒤집혀 있었음

### 검증
- [x] `cd app && fvm flutter analyze --no-fatal-infos`
- [x] `cd app && fvm flutter test`
- [x] Playwright로 `#/records`, `#/settings`, `#/schedule`, 경기 상세 화면 렌더링 확인
- [x] 기록실 첫 화면 재검증 시 팀별 선수 API 연속 호출/콘솔 에러가 사라진 것 확인
- [x] 기록실 팀 상세/선수 상세 재검증 시 웹에서 정상 렌더링되는 것 확인

### 비고
- 당시 `tests/test_relay_service.py` 2건 실패는 이후 `2026-03-31` 항목에서 fallback stub 추가로 정리됨

---

## 2026-03-30: 일정 카드 상태 문구 / 점수 표시 보강

### 완료
- [x] KBO 월간 일정 원본 `play_html`에서 경기 점수 파싱 추가
- [x] 백엔드 `/api/schedule` 응답에 `awayScore`, `homeScore` 필드 포함
- [x] 일정 화면 카드 상태 문구를 `경기 전 / 경기 중 / 경기 종료`로 통일
- [x] 일정 화면 카드 중앙 영역에 점수가 있으면 `awayScore : homeScore`, 없으면 `vs`를 표시하도록 수정
- [x] 관련 일정 화면 명세를 `docs/APP_SPEC.md`에 반영

### 비고
- KBO 월간 일정 원본은 종료 경기 점수를 직접 포함하고 있어 추가 scoreboard API 호출 없이 카드 점수 노출이 가능함
- 예정 경기는 점수 데이터가 없으므로 기존처럼 `vs`를 유지

---

## 2026-03-30: 종료 경기 상세 진입 오류 수정

### 완료
- [x] 일정 화면에서 `extra` 없이 상세 화면에 진입해도 `gameId` 기반 재조회로 경기 상세를 열 수 있도록 수정
- [x] 앱 상세 화면이 `state.extra` 의존으로 바로 실패하던 흐름을 Riverpod `gameProvider` 조회 기반으로 보완
- [x] 백엔드에 누락되어 있던 `/game/{gameId}` 단건 조회 endpoint 추가
- [x] 종료 경기에서도 경기 결과/박스스코어/라인업 진입이 가능하도록 앱-백엔드 상세 조회 경로 정리
- [x] 미구현 상태인 문자중계 API가 raw 에러로 노출되지 않도록 상태별 안내 문구로 대체
- [x] 문자중계 탭이 `relay` endpoint를 중복 호출하던 구조를 단일 호출로 정리
- [x] 백엔드 `relay` endpoint가 501 대신 빈 payload를 반환하도록 정리해 웹 콘솔 오류 제거
- [x] 예정 경기 `section=START_PIT` 링크를 `SCHEDULED`로 분류하도록 일정 상태 파싱 보정
- [x] 종료 경기 문자중계 탭에서 이닝별 득점 요약과 경기 종료 결과를 보여주는 summary relay 추가
- [x] KBO 로그인 세션을 사용하는 `LiveTextView2.aspx` crawler 추가
- [x] `KBO_RELAY_USER_ID` / `KBO_RELAY_PASSWORD` 환경변수 기반으로 실제 play-by-play relay 파싱 지원
- [x] `backend/.env` 자동 로드 지원 추가
- [x] 로컬 `backend/.env`에 KBO relay 계정 설정
- [x] 라인업 탭을 모바일 카드형 UI로 전면 정리
- [x] 라인업 탭 상단 스위처에 `AWAY/HOME + 팀명 + 로고` 표시 추가
- [x] 홈 진입 속도 개선을 위해 scoreboard 응답에서 유튜브 하이라이트 검색 제거
- [x] iOS/Android 런치 스크린을 다크 테마로 정리해 초기 흰 화면 노출 완화

### 원인
- 홈 화면은 `/game/:gameId` 라우팅 시 `extra: game`을 넘기지만, 일정 화면은 `gameId`만 넘기고 있었음
- `GameDetailScreen`이 `game == null`이면 즉시 `경기를 찾을 수 없습니다`를 렌더링하고 있었음
- 웹/릴리즈용 `ApiGameRepository.getGame()`가 호출하는 `/game/{gameId}` 백엔드 라우트가 실제로 없었음
- `/game/{gameId}/relay`는 아직 백엔드 미구현이라 상세 탭에서 사용자에게 실패 문구가 그대로 노출되고 있었음
- 앱에서 `relayProvider`와 `currentAtBatProvider`가 같은 endpoint를 각각 호출해 같은 실패가 중복 발생하고 있었음
- KBO 일정 응답에서 예정 경기가 `section=START_PIT`로 내려오는 케이스를 `SCHEDULED`로 분류하지 못해 상세 상태가 `UNKNOWN`으로 내려오고 있었음
- KBO 공식 live relay 원본 경로를 즉시 안정적으로 확보하기 어려워, 종료 경기의 경우 scoreboard 데이터로부터 흐름 요약을 만들어 탭 공백을 줄일 필요가 있었음
- KBO 공식 `문자중계보기`는 로그인 사용자에게만 `LiveText.aspx` / `LiveTextView1.aspx` / `LiveTextView2.aspx`를 정상 제공하고 있었음

---

## 2026-03-30: 예매 정보 / 예매 오픈 알림 추가

### 완료
- [x] 일정 화면 카드에 경기별 예매처와 예매 오픈 시간 표시 추가
- [x] 경기 상세 상단에 예매 정보 카드 추가
- [x] 경기 상세에서 예매처 외부 링크 열기 버튼 추가
- [x] 경기 상세에서 경기별 예매 오픈 알림 토글 추가
- [x] 디바이스 로컬 알림 기반 예매 오픈 시각 예약 알림 구현
- [x] 백엔드 `/api/schedule`, `/api/game/{gameId}`, `/api/scoreboard` 응답에 `ticketInfo` 필드 추가
- [x] 경기 상세 상단에 KBO 공식 / 유튜브 하이라이트 카드 추가
- [x] 백엔드에서 KBO 공식 링크 + 유튜브 검색 기반 `highlightInfo` 메타데이터 조회 추가
- [x] 하이라이트 카드에서 KBO 공식 페이지와 유튜브 웹 페이지를 각각 열 수 있도록 추가
- [x] 스코어 탭 이닝 셀 클릭 시 해당 회차 주요 장면 바텀시트 추가
- [x] 문자중계 탭이 라이브 경기 전용으로 막히지 않도록 완화
- [x] 라인업/상세 탭 좁은 폭 깨짐 대응을 위해 가로 스크롤 보강
- [x] 홈 스코어보드 기준 위젯 동기화 서비스 추가
- [x] 앱 foreground 기준 라이브 30초 / 예정 5분 자동 갱신 추가
- [x] Android 앱 위젯 리시버 / 레이아웃 / 15분 주기 background refresh 등록 추가
- [x] iOS WidgetKit용 데이터 공유/배경 갱신 훅 및 위젯 소스 초안 추가
- [x] 반복 패턴을 `.claude/skills/` 로 승격 (`kbo-asmx-direct-integration`)
- [x] AGENTS / CLAUDE / SKILL_REFERENCE 에 재사용 인사이트 동기화
- [x] 앱 단독 모드 전환 현황 문서 추가 (`docs/APP_STANDALONE_MODE.md`)

### 한계
- Android 위젯의 시스템 `updatePeriodMillis`는 30분 미만으로 내려갈 수 없어서 15분 주기는 Workmanager 기반 best-effort로 보강
- iOS WidgetKit은 시스템 budget 기반이라 실시간/초단위 갱신을 보장하지 않음
- 현재 relay API는 투구별 원문 중계가 아니라 회차별 점수 요약 이벤트 중심

### 비고
- KBO 일정 원본 응답에는 예매처/예매 오픈 시간이 없어 현재는 홈팀 기본 정책 기준 추정값으로 내려줌
- 실제 운영 단계에서는 팀별 공식 예매 페이지 크롤링 또는 별도 관리 데이터가 필요
- 웹에서는 로컬 예약 알림을 지원하지 않음

---

## 2026-03-30: 기록실 / 선수 상세 화면 추가

### 완료
- [x] 하단 탭에 `기록실` 추가
- [x] 마이팀 기준 선수 리스트 화면 추가
- [x] `전체 / 엔트리 / 엔트리 제외` 필터 추가
- [x] 선수 카드에 부상 / 엔트리 제외 상태 배지와 간단 기록 표시
- [x] 선수 프로필 / 시즌 기록 / 최근 기록을 보여주는 상세 화면 추가
- [x] 기록실에 `야수 / 투수` 탭 분리 추가
- [x] `타율 / OPS / ERA / WHIP` 기준 정렬 추가
- [x] 백엔드 `team players`, `player detail` API 추가
- [x] KBO 공식 등록 현황 / 선수 상세 기록 페이지 기반 크롤링 연결
- [x] 관련 문서(`README.md`, `CHANGELOG.md`, `docs/APP_SPEC.md`) 반영

### 비고
- 웹/릴리즈 기록실은 실제 백엔드 선수 API를 사용
- 네이티브 로컬 환경은 현재 mock fallback 유지
- KBO 공식 페이지에서 부상 사유를 직접 주지 않아 `말소 = 엔트리 제외`로 우선 표시

---

## 2026-03-30: README / CHANGELOG 정리

### 완료
- [x] 루트 `README.md` 신규 작성
- [x] 루트 `CHANGELOG.md` 신규 작성
- [x] Codex 앱 실행 액션용 `scripts/codex-run.sh` 추가
- [x] 저장소 실행 방법, 문서 우선순위, 현재 구현 범위를 루트 README에 정리
- [x] `AGENTS.md`에 README / CHANGELOG 지속 갱신 규칙 추가
- [x] `CLAUDE.md`에 README / CHANGELOG 문서 역할 및 갱신 규칙 추가
- [x] README에 Codex 앱 실행 액션 등록용 명령 추가

### 반영 원칙
- 이후 실행 방법, 현재 구현 범위, 저장소 구조가 바뀌면 `README.md`를 같이 갱신
- 이후 사용자 관점 기능 변화나 마일스톤 변화가 생기면 `CHANGELOG.md`를 같이 갱신

### 추가 수정
- [x] 백엔드 `int | None` 등 Python 3.10+ 타입 문법을 Python 3.9 호환 표기로 정리
- [x] `uvicorn` 실행 시 FastAPI import 단계에서 발생하던 타입 평가 오류 수정
- [x] `AGENTS.md`, `CLAUDE.md`에 Python 3.9 호환 타입 힌트 규칙 명시
- [x] Firebase iOS plugin 호환을 위해 iOS deployment target을 `15.0`으로 상향
- [x] Flutter web 플랫폼 추가 (`app/web`)
- [x] `scripts/codex-run.sh web` 실행 경로 추가
- [x] Codex 실행 액션용 플랫폼 분리 스크립트 추가 (`ios`, `android`, `web`)
- [x] iOS Xcode 프로젝트의 `SDKROOT` / `SUPPORTED_PLATFORMS`를 시뮬레이터 호환으로 정리

---

## 2026-03-30: AGENTS 컨텍스트 동기화

### 완료
- [x] `CLAUDE.md` 기반 `AGENTS.md` 신규 작성
- [x] 저장소 내 Markdown 문서 전체 재검토 (`CLAUDE.md`, `docs/PLANNING.md`, `docs/APP_SPEC.md`, `docs/WORKLOG.md`)
- [x] 문서 간 기준 우선순위 정리 (`AGENTS.md`에 반영)
- [x] 최신 모바일 스택 기준이 Flutter임을 재확인

### 확인 사항
- `docs/PLANNING.md` 마지막 "다음 단계" 항목의 `Expo 프로젝트 셋업` 문구를 `Flutter 프로젝트 셋업`으로 정정
- 최신 기준은 `Flutter + Dart`, `Riverpod`, `go_router`, `dio`, `FastAPI`, `AWS`, `FCM`

### 비고
- 이후 작업은 `AGENTS.md`를 기본 작업 가이드로 사용

### 추가 진행
- [x] `docs/FIGMA_PROMPT.md` 전체 검토
- [x] Figma 작업 스킬 및 대상 파일 접근 경로 확인

### 현재 블로커
- Figma MCP 조회 시 Starter 플랜 도구 호출 한도 초과로 파일 메타데이터 조회 실패
- 오류 메시지 기준 추가 작업 전 Figma MCP 한도 초기화 또는 상위 플랜 필요

### 추가 문서 정리
- [x] `docs/FIGMA_PROMPT.md` 반영해 `CLAUDE.md` 보강
- [x] `docs/FIGMA_PROMPT.md`와 최근 작업 상황 반영해 `AGENTS.md` 보강
- [x] `docs/TASK_DIVISION.md`를 협업 운영 문서 형태로 재정리

### 백엔드 착수
- [x] FastAPI 백엔드 기본 구조 생성 (`backend/`)
- [x] `pyproject.toml`, `.env.example`, `README.md` 추가
- [x] `api / core / crawlers / scheduler / push / schemas / utils` 패키지 골격 생성
- [x] `/api/health` 구현 및 나머지 제품 API 스텁 라우트 등록
- [x] 기본 테스트 파일 추가 (`backend/tests/test_health.py`)
- [x] `GetScheduleList` 기반 월간 일정 크롤러 구현
- [x] `GetScoreBoardScroll` 기반 스코어보드 상세 크롤러 구현
- [x] `GetBoxScoreScroll` 기반 박스스코어 크롤러 구현
- [x] `GetLineUpAnalysis` 기반 라인업 크롤러 구현
- [x] TeamRankDaily SSR 파싱 기반 순위 크롤러 구현
- [x] `/api/scoreboard`, `/api/schedule`, `/api/game/{gameId}/boxscore`, `/api/game/{gameId}/lineup`, `/api/standings` 연결
- [x] `/api/push/register` 성공 응답 구현

### 검증
- [x] `python3 -m compileall backend/src` 통과
- [x] 서비스 레벨에서 schedule/scoreboard/boxscore/lineup/standings 응답 샘플 확인

### 남은 백엔드 작업
- [ ] 문자중계 실제 데이터 경로 확인 및 `relay` 구현
- [ ] push/register 실제 FCM 연동 구현

---

## 2026-03-28: 프로젝트 초기 세팅 + 기획 완료

### 완료
- [x] Git 레포 생성 (godekd3133/kbo-fans, Private)
- [x] SSH 설정 (`github-personal` alias → `~/.ssh/andy` 키 → godekd3133)
- [x] `.gitignore` 작성
- [x] `CLAUDE.md` 프로젝트 컨텍스트 작성
- [x] `docs/PLANNING.md` 서비스 기획서 작성 (경쟁사 상세 분석 + 차별화 전략 포함)
- [x] `docs/APP_SPEC.md` 앱 상세 기획서 작성 (화면 6개 와이어프레임 + API 7개 명세)
- [x] `design_docs.docx` 수업 제출용 기획서 채움 (팀 정보, 기능 명세, 화면 목록, 패키지, 일정)
- [x] `docs/WORKLOG.md` 작업 이력 문서 생성

### 결정 사항
- **프레임워크**: Flutter + Dart (수업 필수 요구사항)
- **타겟 사용자**: 코어팬 + 라이트팬 모두
- **서비스 목표**: 앱스토어 출시
- **MVP 기능 4개**: 실시간 스코어보드, 문자중계, 박스스코어, 푸시 알림
- **백엔드 인프라**: AWS (EC2/ECS + RDS PostgreSQL + ElastiCache Redis)
- **상태관리**: Riverpod
- **라우팅**: go_router
- **HTTP**: dio

### 변경 이력
- React Native (Expo) → **Flutter (Dart)** 로 변경 (수업 요구사항)
- 인프라 미정 → **AWS** 로 확정
- 경쟁사 분석: 네이버 스포츠, SPORTS.i, 야구보구, ESPN 상세 분석 추가
- 차별화 전략 6가지 수립

### 파일 구조
```
kbo_fans/
├── CLAUDE.md
├── design_docs.docx
├── docs/
│   ├── PLANNING.md
│   ├── APP_SPEC.md
│   └── WORKLOG.md
```

### Figma
- 디자인 파일: https://www.figma.com/design/VZdeXTfwxJYBxy2xOJrl8c/Kbo-Fans
- Figma MCP 서버 연결 필요 (현재 미연결 상태)

### 다음 할 일
- [ ] Figma MCP 서버 연결 → 와이어프레임 직접 생성
- [ ] Flutter 프로젝트 셋업 (flutter create)
- [ ] 백엔드 프로젝트 구조 셋업 (FastAPI)
- [ ] 크롤링 프로토타입 (스코어보드 + 문자중계)
- [ ] 스코어보드 화면 구현

---

## 2026-03-31

### 작업 내용
- [x] native 앱 기본 데이터 경로를 `direct KBO only`에서 `API first + direct fallback` 구조로 전환해 홈/상세/relay/lineup이 같은 서버 응답을 우선 사용하도록 정리
- [x] 홈 스코어보드 live 경기에서 `H/E/B`가 0으로 보이던 문제를 수정하기 위해 backend scoreboard service에 `LiveTextView1.aspx` totals fallback 추가
- [x] live 경기 scoreboard 응답에서 `예정/경기중` 같은 뭉툭한 inning 문구 대신 `Main.asmx` 기준 현재 이닝(`8회말` 등)이 우선되도록 merge 순서 정리
- [x] 종료 경기 relay가 득점 요약만 내려오던 문제를 수정해 final 상태에서도 crawler 원문 play-by-play를 우선 시도하고, 실패 시에만 summary fallback 사용
- [x] 문자중계 회차 칩 점프가 lazy sliver 문맥에서 실패하던 문제를 수정하기 위해 relay 카드 렌더를 전체 Column 구조로 변경
- [x] 경기 상세 `문자중계` 탭의 현재 타석 카드를 이닝/주자/타자/투수/투구수/BSO와 최근 교체/직전 플레이가 함께 보이도록 재구성
- [x] relay 목록을 최신 seq 기준 역순 정렬하고, 타석 결과 카드에 이벤트 배지와 플레이 주체 텍스트를 추가
- [x] 웹 검증 중 발견된 경기 상세 `박스스코어` / `라인업` 500 오류 수정
- [x] 예정 경기에서 KBO 박스스코어 응답 키가 없을 때 빈 데이터로 정상 응답하도록 방어 로직 추가
- [x] 기록실 팀 상세 `/team/{teamId}/records`가 선수 크롤링 타임아웃으로 전체 500이 되던 문제를 부분 성공 응답으로 변경
- [x] 팀 선수 목록 크롤링을 경량화해 `/team/{teamId}/players` 및 `/team/{teamId}/records` 응답 시간 단축
- [x] 기록실 overview 서비스에 TTL 캐시 추가
- [x] 기록실 overview featured 카드 생성 시 선수 상세 크롤링 제거 및 리더보드 병렬 수집 적용
- [x] 현재 월 일정 API에 TTL 캐시 추가
- [x] 홈 보조 섹션을 `마이팀/핵심 카드`와 `overview 카드`로 분리해 첫 체감 렌더를 앞당김
- [x] 경기 상세에서 `boxscore` / `lineup` 중복 API 호출을 provider 공유 구조로 제거
- [x] 예정/종료/취소 경기 relay 요청 시 크롤러를 타지 않도록 short-circuit 처리
- [x] records overview 영속 snapshot fallback 추가
- [x] 앱 로컬 API 캐시를 TTL 기반으로 조정해 신선한 데이터 재사용 시 불필요한 백그라운드 재요청 제거
- [x] 홈 화면에서 `schedule` / `standings` 중복 구독 제거
- [x] 홈 `overview` 섹션을 실제 노출 위치 기준으로 lazy load
- [x] 홈 secondary 섹션 전용 aggregate endpoint (`GET /api/home`) 추가
- [x] 홈 화면에서 aggregate 성공 시 secondary 섹션을 서버 조합 데이터로 렌더, 실패 시 기존 provider 조합 fallback 유지
- [x] 관련 백엔드 회귀 테스트 추가
- [x] iPhone local 디버그에서 `records`가 mock/localhost 경로로 빠지던 분기를 제거하고 iOS local 기본 API를 dev 서버로 전환
- [x] direct KBO 일정 파서가 당일 예정 경기 행의 빈 action 셀 때문에 `gameId`를 잃고 오늘 경기 전체를 누락하던 문제 수정
- [x] direct KBO 일정에서 링크가 비어 있어도 날짜+팀명으로 `gameId`를 복원하도록 보강
- [x] local iPhone에서 backend 없이도 `Main.asmx` 기반 live 상태 판정과 `LiveTextView2.aspx` 기반 문자중계를 직접 파싱하도록 direct KBO 경로 보강
- [x] direct relay용 KBO 로그인 플로우를 앱 내부에 추가하고 live scoreboard fallback을 `Main.asmx` 메타데이터로 보강

### 검증 메모
- `GET /api/game/20260331HTLG0/boxscore` : `500` -> `200` (예정 경기 빈 데이터 응답)
- `GET /api/game/20260331HTLG0/lineup` : `500` -> `200`
- `GET /api/team/LG/records?season=2026` : `500` -> `200`
- `GET /api/team/LG/players?season=2026` : 약 `19s` -> 약 `3.7s`
- `GET /api/team/LG/records?season=2026` : 약 `10s+` 실패 -> 약 `3.2s`
- `GET /api/records/overview?season=2026` : 약 `4~6s` -> 약 `1.1s`, 캐시 히트 시 `0.01s` 이내
- 홈 화면은 보조 섹션을 한 번에 기다리지 않고 순차 노출되도록 조정
- `GET /api/game/20260331HTLG0/relay` : non-live 경기에서 크롤러 우회, 약 `0.56s`
- `GET /api/game/20260331HTLG0/boxscore` : 캐시 히트 기준 약 `0.20s`
- 앱 재진입/탭 재방문 시 `schedule`, `standings`, `records`, `player detail`, `overview`는 TTL 내 네트워크 재호출 없이 로컬 캐시 우선 사용
- 홈 화면은 `schedule` / `standings`를 한 번만 읽고 두 섹션에서 재사용
- 홈 `overview`는 고정 시간 지연 대신 실제 화면 근접 시점에 로드
- `GET /api/home?date=2026-03-31&myTeam=LG` : `200`, 약 `0.66s`
- KBO `GetScheduleList` 2026-03 응답에서 `03.31(화)` 예정 경기 행은 review/relay 링크가 비어 있어 기존 파서가 `gameId`를 빈 값으로 처리하던 것을 확인
- KBO `Main.asmx/GetKboGameList` 2026-03-31 응답에서 `GAME_STATE_SC=2` 와 현재 타석 count 필드가 live 판정 근거로 유효함을 확인
- KBO `LiveTextView2.aspx` 20260331OBSS0 응답이 로그인 후가 아닌 direct 호출에서도 relay markup(`#numCont*`, `.playerBox`, `p.present`)을 반환하는 것을 확인
- live direct lineup에서 `GetLineUpAnalysis`는 타선만 제공하고 선발명은 비운다는 점을 확인하고, `Main.asmx/GetKboGameList`의 `T_PIT_P_NM/B_PIT_P_NM` 및 relay 현재 투수로 선발/불펜 fallback 합성 로직을 추가
- live relay 교체 문구(`투수 오러클린 : 투수 백정현 (으)로 교체`)에서 불펜 투수 순서를 복원할 수 있음을 확인하고, local direct 라인업 탭 투수 fallback에 relay 기반 불펜 목록을 연결
- direct boxscore fallback에도 `투수 운용`과 `라인업 기준 타순` 섹션을 추가해 공식 박스스코어 payload가 비어도 라이브 경기 맥락을 유지하도록 보강
- 기록실/선수 데이터 로딩은 모바일 local에서도 `API -> 기기 로컬 snapshot -> 번들 asset` 순서로 동작하도록 `DeviceSnapshotPlayerRepository`를 추가
- `fvm flutter analyze --no-fatal-infos` 통과

### 문서화
- [x] `docs/APP_SPEC.md` 문자중계 탭 UI 요소 설명을 최신 relay 카드 구조 기준으로 갱신
- [x] `docs/APP_SPEC.md`에 종료 경기 relay의 full play-by-play 우선 / summary fallback 정책 반영
- [x] 홈 전용 aggregate endpoint 기반 성능 개선 제안서 작성 (`docs/PERFORMANCE_PROPOSAL_HOME_AGGREGATE.md`)
- [x] 홈 aggregate endpoint 구현 계획서 작성 (`docs/PERFORMANCE_IMPLEMENTATION_PLAN_HOME_AGGREGATE.md`)

### 후속 확인 필요
- [ ] local Android/iOS 기기 단독모드에서 앱 시작 직후 종료가 재발하지 않는지 확인
- [ ] local standalone에서 위젯 / Live Activity / 로컬 알림이 실제로 동작하는지 확인
- [ ] direct KBO `SR_ID` 기반 요청 변경 후 점수판 H/E/B, 이닝별 점수, 라인업, 박스스코어가 실경기 기준으로 안정화됐는지 확인
- [ ] direct relay 현재 타석 카드의 팀 로고 / 선수 프로필 이미지 렌더가 실제 기기에서 정상인지 확인

- [x] iOS 런치 스크린 문구를 단순화하고, AppDelegate/Flutter 첫 프레임 startup 타이밍 로그를 추가해 첫 프레임 이전 지연 구간을 구분 가능하게 함
- [x] 최초 startup preload는 API 캐시/스냅샷을 경기·일정·순위·리그 기록·전 팀 기록실·당일 경기 상세까지 순차 저장하고, Flutter boot 화면은 진행 상태를 단계별로 계속 갱신하도록 조정
- [x] direct KBO 일정 월 조회에서 비정형 row 한 건으로 `Bad state: No element` 가 월 전체 로딩을 깨지지 않도록 row 단위 예외 격리와 상세 진단 로그 추가
- [x] Flutter 전역 예외 로그에 stack trace 를 함께 남기도록 조정해 재현 시 원인 추적 가능성 강화
- [x] 일정 화면 구장별 보기에서 팀별 필터 칩을 추가해 특정 팀 경기만 구장 기준으로 좁혀볼 수 있게 조정
- [x] 일정 화면 구장별 보기에도 월별 `PageView`를 적용해 좌우 스와이프와 헤더 좌우 버튼으로 달 이동이 가능하도록 정리
- [x] 박스스코어 투수 카드도 타자와 동일한 선수 이미지 매핑을 사용하도록 수정해 프로필 사진이 표시되게 조정

---

## 2026-04-01

### 작업 내용
- [x] GitHub Actions 수동 빌드 워크플로우 `.github/workflows/app-build-artifacts.yml` 추가
- [x] `platform` (`android` / `ios` / `web` / `all`) 과 `app_environment` (`local` / `dev` / `release` / `all`) 입력으로 빌드 매트릭스를 선택할 수 있게 구성
- [x] Android 에서 환경별 `apk`, `aab` 아티팩트를 업로드하도록 구성
- [x] iOS 에서 환경별 unsigned simulator 앱 zip 아티팩트를 업로드하도록 구성
- [x] iOS 인증서/프로비저닝 시크릿이 준비된 경우 선택적으로 signed `ipa` 를 생성하도록 구성
- [x] Web 에서 환경별 정적 빌드 zip 아티팩트를 업로드하도록 구성
- [x] README / 배포 가이드 / Android 서명 가이드 / iOS TestFlight 체크리스트에 GitHub Actions 빌드본 추출 절차와 CI 시크릿 목록 반영
- [x] 남은 GitHub Secrets 등록 / 실행 검증 항목을 `docs/GITHUB_ACTIONS_BUILD_TODO.md` 로 분리 정리

### 검증 메모
- GitHub Actions 워크플로우는 `workflow_dispatch` 수동 실행 기준으로 설계함
- Android 서명 시크릿이 없으면 현재 Gradle 정책대로 debug signing fallback release 빌드가 생성되도록 유지
- iOS 는 기본 경로를 simulator용 unsigned 빌드로 두고, 인증서/프로비저닝 시크릿이 있을 때만 signed `ipa` 경로를 활성화함
- 앱 환경값은 기존 `AppConfig` 의 `APP_ENV=local|dev|release` 정의를 그대로 사용함

### 후속 확인 필요
- [ ] GitHub 저장소 Secrets 에 Android/iOS signing 값을 실제 등록한 뒤 `Actions > App Build Artifacts` 실런 검증
- [ ] signed iOS `ipa` 생성 시 현재 프로비저닝 프로파일 specifier 명이 Runner / Widget 번들 ID와 정확히 일치하는지 확인

---

## 2026-05-18

### 작업 내용
- [x] 현재 기획/디자인 문서 기준으로 제품 보강 방향 감사 문서 작성
- [x] 마이팀 데일리 루프, 홈 브리프, 라이트팬/코어팬 정보 깊이, 알림 프리셋, 위젯 방향 정리
- [x] UI/UX 관점에서 홈, 경기 상세, 일정, 순위, 기록실, 설정/알림별 보강 체크리스트 정리
- [x] 디자인 시스템 관점에서 상태 색상, 카드 체계, 팀 컬러 사용 원칙, 타이포그래피, 이미지 fallback 방향 정리

### 산출물
- `docs/PRODUCT_DESIGN_GROWTH_AUDIT_2026-05-18.md`

### 검증 메모
- 기준 문서: `CLAUDE.md`, `docs/PLANNING.md`, `docs/APP_SPEC.md`, `docs/FIGMA_PROMPT.md`, `docs/UX_AUDIT_2026-03-31.md`, `docs/WORKLOG.md`
- 이번 작업은 기획/디자인 문서화 범위이며, 앱 런타임 화면 캡처나 코드 변경은 수행하지 않음

---

## 2026-05-19

### 작업 내용
- [x] 앱 전역 라우팅 모션 추가: 부트/온보딩 fade, 하단 5탭 fade+미세 slide, 경기 상세/진단 drill-in 전환 적용
- [x] 하단 탭 선택 상태의 아이콘 scale, 배경/테두리, 라벨 스타일 전환을 같은 easing으로 정리
- [x] 화면 전환 모션 원칙을 `docs/APP_SPEC.md`와 `CHANGELOG.md`에 반영
- [x] `docs/PRODUCT_DESIGN_GROWTH_AUDIT_2026-05-18.md`의 제품/디자인 보강안을 기준 문서에 반영
- [x] `docs/PLANNING.md`에 제품 한 줄 정의, 마이팀 데일리 사용 루프, 정보 깊이 원칙, 상태 중심 디자인 원칙 반영
- [x] `docs/APP_SPEC.md`에 홈 마이팀 브리프 상태별 규칙, 경기 상세 탭 간 맥락 연결, 일정/순위 보강, 알림 프리셋, 위젯 원칙 반영
- [x] `docs/FIGMA_PROMPT.md`에 5탭 구조, 기록실 페이지, 카드 체계, 상태 표현, 알림 프리셋 UI, 홈 상태 프레임 보강 반영
- [x] 모바일 디자인 보드 HTML 제작 (`docs/design/kbo-fans-mobile-ui-2026-05-19/index.html`)
- [x] 디자인 보드 렌더 확인용 preview 이미지 생성 (`docs/design/kbo-fans-mobile-ui-2026-05-19/preview.png`)
- [x] UI/UX 원칙과 플랫폼 레퍼런스를 반영한 v2 방향 문서 작성 (`docs/UI_UX_REFERENCE_DEVELOPMENT_2026-05-19.md`)
- [x] 레퍼런스 기반 v2 모바일 디자인 보드 제작 (`docs/design/kbo-fans-mobile-ui-reference-v2-2026-05-19/index.html`)
- [x] v2 디자인 보드 렌더 확인용 preview 이미지 생성 (`docs/design/kbo-fans-mobile-ui-reference-v2-2026-05-19/preview.png`)
- [x] 디자인 철학 / 플랫폼 UX / 스포츠앱 레퍼런스 기반 v3 방향 문서 작성 (`docs/UI_UX_DESIGN_PHILOSOPHY_REFERENCE_2026-05-19.md`)
- [x] `Stadium Control Room for My Team` 콘셉트의 v3 모바일 디자인 보드 제작 (`docs/design/kbo-fans-mobile-ui-philosophy-v3-2026-05-19/index.html`)
- [x] v3 디자인 보드 렌더 확인용 preview 이미지 생성 (`docs/design/kbo-fans-mobile-ui-philosophy-v3-2026-05-19/preview.png`)
- [x] 알림 강도 / 앱 밖 경험 v3 문제를 기준으로 notification, Live Activity, Android Live Update, Widget 트렌드 재분석 문서 작성 (`docs/UI_UX_NOTIFICATION_OUTSIDE_APP_TRENDS_2026-05-19.md`)
- [x] `Moment Subscription & Surface Strategy` 콘셉트의 v4 모바일 디자인 보드 제작 (`docs/design/kbo-fans-mobile-ui-alerts-outside-v4-2026-05-19/index.html`)
- [x] v4 디자인 보드 렌더 확인용 preview 이미지 생성 (`docs/design/kbo-fans-mobile-ui-alerts-outside-v4-2026-05-19/preview.png`)
- [x] 실제 마케팅/발표자료 제작을 가정한 5장 Feature Graphics 구성과 Claude Design PPT 프롬프트 작성 (`docs/FEATURE_GRAPHICS_CLAUDE_DESIGN_PROMPT_2026-05-19.md`)
- [x] KBO Fans 5장 Feature Graphics HTML 시안 제작 (`docs/design/kbo-fans-feature-graphics-2026-05-19/index.html`)
- [x] Feature Graphics 전체 preview 및 개별 slide PNG 5장 생성 (`docs/design/kbo-fans-feature-graphics-2026-05-19/preview.png`, `slide-01.png` ~ `slide-05.png`)
- [x] Feature Graphics 메시지를 마이팀 한눈 보기, 경기 일정/예매/예매 알림, 득점/역전 알림, 실시간 문자중계, 선수 기록실 기준으로 재구성
- [x] Claude Design PPT 프롬프트와 HTML/PNG 시안을 동일한 5대 차별점 기준으로 갱신
- [x] v4 알림 / 앱 밖 경험 기준을 `docs/APP_SPEC.md`, `docs/FIGMA_PROMPT.md`, `docs/PLANNING.md`의 canonical 제품/화면/API 계약에 반영
- [x] 구형 `알림 프리셋 + 이벤트 토글 + 실시간 위젯` 표현을 `Moment Subscription + Surface 분리 + Widget Status Board` 기준으로 재정의
- [x] KBO 데이터 갱신 구조 P0 구현: 기본 direct scrape/fallback 제거, startup/detail preload 축소, Schedule/Home 자동 detail preload 제거, Score/Relay/Lineup 탭 과다 provider 의존 축소
- [x] `docs/KBO_DATA_REFRESH_ARCHITECTURE_2026-05-19.md`에 P0 구현 상태와 남은 P1 범위 기록
- [x] KBO 데이터 갱신 구조 P1 일부 구현: backend `SingleFlight` 추가, 동일 날짜 scoreboard 병렬 요청 병합, `/game/{gameId}` 단건 상세가 같은 날짜 전체 경기 enrich를 수행하지 않도록 변경
- [x] `/api/game/{gameId}`가 scoreboard/game summary 성공 시 schedule fallback 조회를 추가로 하지 않도록 정리
- [x] V4 native surface QA 문서 작성 (`docs/UX_NATIVE_SURFACE_QA_V4_2026-05-19.md`)
- [x] iOS Widget / Live Activity / Dynamic Island에서 현재 타석 데이터가 없을 때 B/S/O `0` badge가 보이지 않도록 보정
- [x] `docs/APP_SPEC.md`에 unknown B/S/O를 실제 0카운트처럼 표시하지 않는 원칙 추가
- [x] Widget tap launch URI를 저장하고 iOS/Android widget click을 Flutter router로 연결해, 표시 중인 경기 상세로 바로 진입하도록 보강
- [x] Widget stale threshold를 추가해 live 경기는 2분, 그 외 상태는 15분 이상 갱신이 없으면 `업데이트 지연`으로 표시
- [x] Android 진행형 Live Update가 아직 구현 표면이 아님을 앱 copy와 spec에 명확히 반영
- [x] `ApiClient.getCached`의 fresh cache 선반환 조건을 `preferCache=true` 경로로 제한해, 현재 날짜/현재 시즌 화면의 fresh-first 정책이 실제로 적용되도록 수정
- [x] 현재 시즌 선수 목록, 선수 상세, 팀 스탯과 경기 상세 박스스코어/라인업도 정상 상황에서는 최신 API 응답을 먼저 받도록 정리
- [x] 온보딩 구단 선택 로고가 `26x17` 초소형 이미지에서 확대 렌더링되던 문제를 `64x41` 공식 엠블럼 경로와 고품질 필터링으로 보정

### 검증 메모
- 라우팅 모션 변경은 기존 `NoTransitionPage` 기반 하단 탭을 `CustomTransitionPage` 공통 helper로 바꾼 범위이며, OS 접근성의 애니메이션 줄이기 설정이 켜진 경우 전환 애니메이션을 생략하도록 처리함
- 검증으로 `fvm dart format`, `fvm flutter analyze`, 기존 Flutter 테스트 3종, `fvm flutter build web --release`, `http://localhost:7357` Puppeteer smoke를 실행했고 하단 5탭과 경기 상세 hash 라우팅 렌더를 확인함
- `kbo-doc-sync` 기준으로 UX/화면 상태 변경은 `APP_SPEC`와 `WORKLOG`에 반영
- 해당 v4 디자인 보드 작업 시점에는 실제 앱 UI 구현이나 Figma MCP 작업은 수행하지 않았고, 이후 앱 코드 반영은 같은 날짜 상단 작업 이력과 `CHANGELOG.md`에 따로 기록함
- Figma MCP 제작 도구는 현재 세션에서 호출 가능한 형태로 노출되지 않아, 우선 저장소 내 HTML 디자인 보드로 제작
- Playwright CLI + system Chrome channel 로 HTML 디자인 보드 full-page screenshot 생성 확인
- v2 UI/UX 보강은 Android NavigationBar/Layout 가이드, NN/g usability heuristics, WebAIM WCAG target size, Apple Widget/Live Activity 문서를 참고해 홈/상세/일정/기록실/알림/위젯 화면에 반영
- v2 디자인 보드는 외부 이미지 의존 없이 CSS 기반 팀 배지와 UI 요소로 렌더 안정성을 확보하고, Playwright CLI + system Chrome channel 로 full-page screenshot 생성 확인
- v3 UI/UX 보강은 GOV.UK Service Design, Calm Technology, Apple HIG/Widgets/Live Activities, Material 3, Microsoft Inclusive Design, IBM Design Language, Atomic Design, Baymard mobile app UX, ESPN/theScore 스포츠앱 패턴을 참고해 `Now / Next / Later`, `Attention Dial`, `Field View`, `Small Scoreboard Widget`, 반복 가능한 상태 컴포넌트 체계로 재정리
- v3 디자인 보드는 외부 이미지 의존 없이 CSS 기반으로 제작했고, Playwright CLI + system Chrome channel 로 full-page screenshot 생성 확인
- v4 UI/UX 보강은 Apple notification summary / Live Activities / Widgets, Android notification runtime permission / Live Updates, theScore Live Activities & Events, ESPN alert preferences를 참고해 `알림 강도`를 `Moment Subscription`, `앱 밖 경험`을 iOS Live Activity / Android Live Update / Widget / Push 역할 분리로 재설계
- v4 디자인 보드는 외부 이미지 의존 없이 CSS 기반으로 제작했고, Playwright CLI + system Chrome channel 로 full-page screenshot 생성 확인
- Feature Graphics는 Google Play Feature Graphic 공식 요구사항인 1024x500 변환 가능성을 고려하되, Claude Design / PPT 사용성을 위해 16:9 wide layout으로 제작. 전체 preview와 각 slide 단위 PNG를 Playwright CLI + system Chrome channel 로 생성 확인
- 사장님이 지정한 핵심 매력 요소인 마이팀, 일정/예매, 예매 알림, 득점/역전 알림, 실시간 중계, 선수 기록실을 5장 Feature Graphics 구성과 개별 PNG에 재반영하고 Playwright CLI + system Chrome channel 로 재렌더 확인
- v4 canonical 반영은 당시 문서/spec/API 계약 범위였으며, 이후 Flutter 앱 반영은 같은 날짜 상단 작업으로 이어서 기록함
- 디자인 보드 변경 자체는 문서/디자인 산출물 범위였고, 별도 앱 런타임 캡처는 수행하지 않음
- KBO 데이터 갱신 P0 구현 검증으로 `fvm dart format`, `fvm flutter analyze`, `fvm flutter test test/widget_test.dart test/data/models/records_overview_test.dart test/services/push_notification_service_test.dart` 실행, 모두 통과
- KBO 데이터 갱신 P1 backend 검증으로 `backend/.venv/bin/python -m compileall backend/src`, `backend/.venv/bin/pytest -q backend/tests/test_scoreboard_service_cache.py backend/tests/test_games.py backend/tests/test_snapshot_services.py`, `backend/.venv/bin/pytest -q` 실행, 전체 41개 테스트 통과
- native surface 검증으로 `fvm flutter build ios --debug --no-codesign --dart-define=APP_ENV=local`, `fvm flutter build apk --debug --dart-define=APP_ENV=local`, `plutil -lint`, `xmllint --noout`, `fvm flutter analyze`, `fvm flutter test test/widget_test.dart test/services/push_notification_service_test.dart` 실행, 모두 통과
- iOS Simulator와 Android 기기/에뮬레이터가 없어 실제 앱 밖 표면 screenshot QA는 `docs/UX_NATIVE_SURFACE_QA_V4_2026-05-19.md`에 미완료 조건으로 분리 기록
- 캐시 정책 보정 후 `fvm dart format`, targeted `fvm flutter analyze`, backend records/schedule/scoreboard/team 테스트 20개, `fvm flutter build web --release --dart-define=APP_ENV=local` 통과
- 로컬 API 실측으로 home, scoreboard, schedule, standings, records overview, leaderboard(avg/hr/ops/era), KT team records/players/stats, KT-삼성 game detail/relay/boxscore/lineup 응답 확인
- 새 웹 번들을 `http://127.0.0.1:7357`에 다시 열고 home/schedule/standings/records/team records/game score 화면을 캡처해 표시값을 확인 (`artifacts/kbo-cross-screen-check-after-cache-fix/`)
- 온보딩 로고 보정 후 `fvm flutter analyze lib/core/constants/team_data.dart lib/features/onboarding/onboarding_screen.dart`, `fvm flutter build web --release --dart-define=APP_ENV=local` 통과, 웹 캡처 확인 (`artifacts/kbo-onboarding-logo-check/onboarding-logo-fixed.png`)

---

## 2026-05-20

### 작업 내용
- [x] `AppMotionSwitcher` / `AppMotionListItem` 공통 모션 위젯 추가
- [x] 홈 스코어보드 로딩/캐시/데이터/에러 전환에 공통 fade + 미세 slide 적용
- [x] 일정, 순위, 기록실, 선수 상세의 Async 상태 전환에 공통 모션 적용
- [x] 홈 경기 카드, 일정 경기 카드, 구장별 일정, 순위 행, 기록실 선수 카드, 리더보드 행에 짧은 등장 모션 적용
- [x] 하단 탭, 경기/일정 카드, 온보딩 구단 카드, 일정 필터/헤더 버튼, 기록실 카드/필터/정렬 chip, 리더보드 행에 press scale + opacity 피드백 적용
- [x] 홈/마이팀/일정/경기 상세 스코어에 value swap 모션 적용
- [x] 홈 마이팀 브리프, 최근 경기 chip, 오늘 경기 보조 행, 빠른 콘텐츠 카드까지 press 피드백 확장
- [x] 경기 상세 스코어 탭 회차 셀, 문자중계 이닝 chip, 박스스코어 팀 토글/선수 카드/선수 리스트 등장 모션, 하이라이트 카드/모드 chip에 micro motion 확장
- [x] 일정 달력 날짜 셀과 설정 마이팀 카드/알림 row/정보 row/전달 방식 option에 press 피드백 확장
- [x] 모션 원칙을 `docs/APP_SPEC.md`와 `CHANGELOG.md`에 반영
- [x] `LocalAssetPlayerRepository`의 `MockPlayerRepository` fallback 제거: 번들 스냅샷이 비어 있으면 빈 상태/명시적 오류를 반환해 기록실에 가짜 선수 데이터가 재유입되지 않도록 보정
- [x] local native `API_BASE_URL` 명시 경로에서 `/home` 실패 시 direct/provider 조립 fallback으로 재진입하지 않도록 차단
- [x] 일반 local API 라우팅에서 `FallbackGameRepository` direct fallback 제거
- [x] local native no-override 기본 경로도 API-backed provider로 고정하고, direct KBO는 `PREFER_DIRECT_SCRAPE=true` 명시 임시 direct-primary에서만 쓰도록 정리
- [x] 사용처가 사라진 `FallbackGameRepository` 구현 파일 삭제
- [x] 라인업 선발 비교 카드의 선수 사진 과확대/크롭을 줄이기 위해 fixed height와 `BoxFit.contain` 렌더로 보정
- [x] Android local 실행 스크립트가 emulator와 실기기를 구분해 emulator는 `10.0.2.2`, 실기기는 Mac LAN IP를 `API_BASE_URL`로 주입하도록 보정
- [x] 사용처가 없는 mock repository / mock data 파일을 삭제해 가짜 데이터 재연결 가능성을 차단
- [x] README의 local native direct scrape 기본값 설명을 API-first 정책에 맞게 갱신
- [x] `AGENTS.md`, `CLAUDE.md`, `.claude/skills/`의 direct fallback 허용 문구를 API-first / explicit temporary direct-primary 정책으로 동기화
- [x] 미사용 `AppConfig.useMockData` 필드 제거
- [x] local iOS 기본 API URL을 더 이상 DNS 실패하던 dev API로 두지 않고 `localhost` 기준으로 정리. 실기기는 실행 스크립트의 LAN IP override를 사용
- [x] local iOS 실기기 LAN API 접속을 위해 `NSLocalNetworkUsageDescription` / local networking ATS 설정 추가
- [x] Android debug/profile local API 접속을 위해 해당 variant에만 cleartext traffic 허용
- [x] 정상 player repository 경로에서 `KboDirectPlayerRepository` 객체 생성도 제거해 temporary direct-primary 분기를 더 명확히 분리
- [x] 오래된 local native 분석/standalone 문서를 API-first 정책으로 보정해 현재 구현과 문서 충돌 제거
- [x] direct-primary 기록실의 과거 시즌 조회 실패 원인 분석: KBO WebForms 시즌 변경 POST가 hidden field 일부만 보내 cookie/session form state 없이 오류 페이지로 떨어져 2025/2024 리더보드와 팀 스탯이 빈 결과가 되던 문제 확인
- [x] `KboDirectPlayerRepository`에 CookieJar 기반 session 유지와 전체 WebForms form payload 재전송을 적용해 과거 시즌 records overview / leaderboard / team stats POST를 정상화
- [x] direct-primary 과거 시즌 팀 기록실은 현재 로스터 검색 대신 KBO 시즌/팀 filter 기록 테이블에서 야수/투수 선수 기록을 구성하도록 보정
- [x] KBO 과거 리더보드에서 은퇴 선수 링크(`/Record/Retire/...`)를 버리던 파서를 보정해 2013 타율/홈런/OPS와 2011 ERA가 실제 공식 순위 1위부터 표시되도록 수정
- [x] 은퇴 선수 리더/팀 선수 항목은 `isRetired` 플래그를 앱/백엔드/snapshot 모델에 보존하고, 앱에서 은퇴 배지를 표시하며 상세 화면 진입은 막도록 보정
- [x] backend `RecordsOverviewCrawler` / `TeamStatsCrawler`도 동일한 전체 WebForms form payload 방식으로 보정해 이후 bootstrap/snapshot 생성이 빈 과거 시즌 데이터로 재생성되지 않도록 정리
- [x] 홈 스코어보드 캐시 저장이 `build` 이후 반복 `setState`를 유발할 수 있던 경로를 payload guard와 무상태 캐시 갱신으로 차단해 실기기 CPU/발열 위험을 낮춤
- [x] 실기기 발열 후보 추가 감사: 홈 이벤트 알림 side effect를 scoreboard payload당 1회로 제한하고, iOS widget App Group 초기화와 닫힌 Dev Console 로그 rebuild를 중복 실행하지 않도록 보정
- [x] 추가 발열 후보 감사: 경기 상세/기록실/일정/홈의 반복 팀 로고와 선수 썸네일에 메모리 디코딩 크기 상한을 걸어 작은 UI 이미지가 원본 크기로 디코딩되는 부담을 낮춤

### 검증 메모
- 모션은 새 패키지 없이 Flutter 기본 위젯만 사용했고, `MediaQuery.disableAnimations`가 켜진 경우 생략되도록 처리함
- 검증으로 `fvm dart format`, `fvm flutter analyze`, 기존 Flutter 테스트 3종, `fvm flutter build web --release --dart-define=APP_ENV=local` 실행, 모두 통과
- `http://localhost:7357` Puppeteer smoke로 온보딩 완료 후 home, schedule, standings, records, leaderboard, player detail, game detail hash 라우팅 렌더를 확인함
- 추가 데이터 경로 검증으로 `fvm flutter test test/data/local_asset_player_repository_test.dart`를 실행해 누락 asset이 mock player로 떨어지지 않는지 확인함
- direct-primary 실측으로 앱 repository가 2025 records overview `avg/hr/ops/opsPlus/era` 각 5개, LG 2025 팀 기록 54명(야수 30명/투수 24명), 팀 타율 `0.278`, 팀 ERA `3.79`를 반환하는지 확인함
- backend crawler 실측으로 2025 overview 각 리더 5개와 LG 2025 팀 타율/ERA 응답을 확인했고, `backend/.venv/bin/pytest -q backend/tests/test_records_overview.py backend/tests/test_teams.py` 통과
- 은퇴 선수 링크 보정 후 backend crawler 실측으로 2013 `avg/hr/ops/era`와 2011 `avg/hr/ops/era`가 공식 순위 1위부터 반환되는지 확인했고, 특히 2011 ERA가 `윤석민 2.45`부터 채워지는지 확인함
- 은퇴 선수 링크 보정 검증으로 `fvm flutter analyze`, `fvm flutter test test/data/models/records_overview_test.dart`, `python3 -m compileall -q backend/src`, `backend/.venv/bin/pytest -q backend/tests/test_records_overview.py` 통과
- 추가 검증으로 `python3 -m py_compile backend/src/kbo_fans_backend/crawlers/base.py backend/src/kbo_fans_backend/crawlers/records_overview.py backend/src/kbo_fans_backend/crawlers/team_stats.py`, `fvm flutter analyze`, `fvm flutter test test/data/local_asset_player_repository_test.dart` 통과
- 홈 캐시 루프 보정 후 `fvm flutter analyze app/lib/features/home/home_screen.dart`, `fvm flutter test test/widget_test.dart` 통과
- 발열 후보 추가 보정 후 `fvm flutter analyze app/lib/features/home/home_screen.dart app/lib/services/widget_sync_service.dart app/lib/core/widgets/dev_console.dart`, `fvm flutter test test/widget_test.dart test/services/push_notification_service_test.dart` 통과
- 이미지 디코딩 상한 보정 후 `fvm dart format app/lib/features/home/home_screen.dart app/lib/features/home/widgets/game_card.dart app/lib/features/home/widgets/my_team_game_card.dart app/lib/features/game_detail/game_detail_screen.dart app/lib/features/game_detail/tabs/boxscore_tab.dart app/lib/features/game_detail/tabs/relay_tab.dart app/lib/features/game_detail/tabs/lineup_tab.dart app/lib/features/records/leaderboard_screen.dart app/lib/features/records/records_screen.dart app/lib/features/standings/standings_screen.dart app/lib/features/schedule/widgets/schedule_game_card.dart`, `fvm flutter analyze app/lib/features/home/home_screen.dart app/lib/features/home/widgets/game_card.dart app/lib/features/home/widgets/my_team_game_card.dart app/lib/features/game_detail/game_detail_screen.dart app/lib/features/game_detail/tabs/boxscore_tab.dart app/lib/features/game_detail/tabs/relay_tab.dart app/lib/features/game_detail/tabs/lineup_tab.dart app/lib/features/records/leaderboard_screen.dart app/lib/features/records/records_screen.dart app/lib/features/standings/standings_screen.dart app/lib/features/schedule/widgets/schedule_game_card.dart`, `fvm flutter test test/widget_test.dart test/services/push_notification_service_test.dart` 통과
- 터치 피드백/점수 전환 모션 보강 후 `fvm dart format`, `fvm flutter analyze`, 기존 Flutter 테스트 3종, `fvm flutter build web --release --dart-define=APP_ENV=local` 통과. `http://127.0.0.1:7357` Puppeteer smoke로 home, schedule, standings, records, game detail 렌더 확인
- 추가 micro motion 확장 후 `fvm dart format`, `fvm flutter analyze`, 기존 Flutter 테스트 3종, `fvm flutter build web --release --dart-define=APP_ENV=local` 통과. local FastAPI + `http://127.0.0.1:7357` Puppeteer smoke로 home/schedule/standings/records/settings/game detail 및 score/relay/boxscore/lineup 탭 렌더 확인. 기존 dirty worktree의 backend/release 문서 변경은 건드리지 않고 Flutter UI 범위만 좁게 수정
