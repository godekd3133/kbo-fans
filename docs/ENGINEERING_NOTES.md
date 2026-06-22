# Engineering Notes

## Purpose

이 문서는 구현 중 얻은 반복적인 인사이트와 운영/검증 메모를 모은다.
기획 문서보다는 구현 판단 기준에 가깝고, `AGENTS.md` / `CLAUDE.md` 를 보완하는 용도로 사용한다.

## Local / Dev Data Behavior

- Backend는 active runtime component다. API-backed data, snapshot generation, push notification, Live Activity / Dynamic Island sync를 다루는 작업은 `app/`과 `backend/`를 함께 본다.
- 모든 일반 local/dev/release/web/native 앱 실행은 backend API mode를 기본으로 사용한다.
- Flutter provider routing은 `USE_BACKEND_API` 미지정 시에도 API mode다. 스크립트/CI에는 `USE_BACKEND_API=true`를 명시하고, direct KBO는 `USE_BACKEND_API=false`를 명시한 parser/debug 세션에서만 사용한다.
- release build는 화면 데이터와 push / Live Activity token registration 모두 운영 backend URL 기준으로 검증한다.
- 앱 startup은 원격 API prefetch를 소유하지 않는다. local onboarding/my-team 상태 확인 후 첫 route로 넘기고, scoreboard/home/records/schedule 요청은 각 화면 provider가 소유한다.
- noisy fallback 로그가 과하면 `local` / 테스트 바인딩에서 prefetch, metric, push init을 완화하는 방향이 안전하다.
- local, dev, release API base URL은 화면 provider와 push registration이 함께 쓰는 backend endpoint 설정값이다.
- 웹 빌드도 `APP_ENV=local` / `APP_ENV=release`에서 backend API를 기본으로 사용한다.
- iPhone local debug에서 `localhost` API는 실기기에서 직접 닿지 않는다.
  - Mac LAN IP를 `API_BASE_URL`로 주입하고 `USE_BACKEND_API=true` 를 함께 지정해야 한다.
- direct KBO source는 backend parser parity/debug 확인 기준이다.
  - scoreboard live status는 `Main.asmx/GetKboGameList` 를 우선 참고한다.
  - 일정 파서는 `GetScheduleList`의 빈 action cell에서도 `gameId`를 날짜+팀 코드로 복원해야 한다.
  - relay는 `LiveTextView2.aspx` markup(`#numCont*`, `p.present`, `.playerBox`) 기준으로 파싱한다.
- local/mobile 알림은 remote push가 아니라 앱 내부 비교 로직이다.
  - scoreboard diff: 경기 시작 / 득점 / 역전 / 종료
  - relay diff: 홈런 / 이닝 교대
  - lineup diff: 선발 라인업 공개 / 변경
  - 따라서 앱이 완전히 죽어 있으면 서버 push처럼 즉시 오지 않는다.
- 앱이 꺼진 뒤에도 알림이나 Dynamic Island가 바뀌려면 앱 direct KBO 경로가 아니라 운영 백엔드가 상태 변화를 읽어야 한다.
  - FCM은 일반 push notification 전달 채널이다.
  - iOS Live Activity / Dynamic Island 원격 갱신은 ActivityKit push token + APNs `liveactivity` push 채널이다.
  - backend scheduler가 live 경기 중 5초 간격으로 scoreboard/relay sync를 실행하고, 등록된 ActivityKit token에는 update/end payload를 보낸다.
  - 같은 scheduler가 이전 scoreboard state와 비교해 FCM topic push용 `game_start`, `scoring`, `reversal`, `game_end`, `inning_change`, `at_bat` moment를 발행한다.
  - 일반 경기 event FCM은 backend가 원정팀/홈팀/전체 topic과 함께 `*_GAME_{gameId}` 경기별 topic으로도 발송한다. 앱은 `followedGameIds`가 있으면 팀 경기 event topic 대신 경기별 topic을 구독해, 사용자가 따라가는 특정 경기만 일반 push로 정교하게 받는다.
  - `baseball_info`는 특정 경기 event가 아니므로 `followedGameIds`가 있어도 `baseball_info_<팀>` / `baseball_info_ALL` 범위를 유지한다.
  - 일반 FCM message의 iOS APNs config는 `apns-push-type=alert`, app bundle `apns-topic`, `aps.alert`, `aps.content-available=1`, `apns-priority=10`, default sound를 명시한다. 앱 쪽은 `remote-notification` background mode와 Firebase background handler를 유지해야 한다. 앱 실행 시점에 몰려 보이는 증상이 재현되면 이 alert-class payload가 운영 image에 배포됐는지 먼저 확인한다.
  - `GameEventAlertService`의 scoreboard/relay diff 기반 local notification은 local 개발 모드에서만 처리한다. release/dev에서 이 경로가 켜져 있으면 앱 resume/focus 시 지난 이벤트가 몰아서 표시될 수 있으므로 backend remote push와 역할을 섞지 않는다. 회귀 확인용으로만 `--dart-define=ENABLE_LOCAL_GAME_EVENT_ALERTS=true`를 명시해 보조 로컬 알림 경로를 켤 수 있다.
  - scoreboard diff만으로 확정하기 어려운 `homerun` moment는 같은 scheduler가 live relay seq baseline을 저장하고, 새 relay item의 `HOMERUN` event 또는 `홈런` 텍스트를 감지해 발행한다.
  - 앱 종료/백그라운드 push가 안 오면 먼저 `/push/register`가 실제 기기에서 성공해 registry `devices`가 채워졌는지 확인한다. 특정 경기 따라가기라면 registry의 `followedGameIds`, `topicCounts`의 `scoring_GAME_{gameId}` / `hit_GAME_{gameId}` / `game_start_soon_GAME_{gameId}`, `deviceSummaries`의 `notificationsAllowed` / `authorizationStatus` / `apnsTokenReady`도 같이 확인한다. 앱은 마이팀 선택 후 non-local 환경에서 최초 1회 권한 요청과 FCM registration sync를 자동 시도해야 한다.
  - `deviceSummaries.updatedAt`은 앱이 `/push/register`를 보낸 시각이고, `topicsUpdatedAt`은 운영자가 registry 기반 topic resubscribe를 수행한 시각이다. 단말 최신성 판단에는 `updatedAt`과 권한/APNs 상태를 보고, resubscribe 성공 여부에는 `topicsUpdatedAt`과 topic count를 본다.
  - 배포 후 `GET /api/push/config-status` 또는 `python -m kbo_fans_backend.scheduler.push_config_status`로 Firebase/APNs/registry/scheduler secret 누락을 먼저 확인한다.
  - local backend에서 `PUSH_SYNC_SECRET`이 없으면 `config-status`는 diagnostics 확인용으로 열어두지만, `/push/test`, `/push/baseball-info`, `/push/resubscribe-topics`, `/push/live-activity/sync-scoreboard` 같은 mutation endpoint는 Firebase/APNs까지 진행하지 않고 503으로 막아야 한다.
  - 앱 내부 receipt 확인용 `/push/test-device`는 운영 secret을 요구하지 않는다. 대신 앱이 현재 FCM token을 `/push/register`로 먼저 저장해야 하며, backend는 registry에 없는 token에는 발송하지 않는다. 이 endpoint에는 앱 번들에 `PUSH_SYNC_SECRET`을 넣지 않기 위한 self-test 경계만 둔다.
  - 외부에서 `PUSH_SYNC_SECRET=<secret> ./scripts/push-readiness-check.sh https://api.kbofans.com/api`를 실행하면 `/health`와 push readiness를 같이 확인할 수 있다.
  - GitHub Actions secret 컨텍스트에서 원격 테스트 푸시를 보낼 때는 `Push Test Notification` workflow 또는 `./scripts/github-push-test-notification-run.sh --topic baseball_info_ALL --watch`를 사용한다. 이 helper는 secret/token 값을 출력하지 않는다.
  - `Push Test Notification`을 `*_GAME_<gameId>` topic으로 보낼 때는 backend가 `type`, `gameId`, `topic`, 상세 `route` data를 함께 실어 receipt 조회에서 해당 팔로우 경기 수신 여부를 필터링할 수 있어야 한다.
  - 실제 단말이 remote push를 처리했는지 확인할 때는 `PUSH_SYNC_SECRET=<secret> ./scripts/push-receipt-status.sh --expect-receipt --game-id <gameId> --type <type>` 또는 GitHub Actions `Push Receipt Status` workflow / `./scripts/github-push-receipt-status-run.sh --expect-receipt --game-id <gameId> --type <type> --watch`를 사용한다. 이 경로는 `/push/config-status`의 `deviceSummaries`와 `recentPushReceipts`만 요약하고 raw device token은 출력하지 않는다.
  - backend image는 `./scripts/aws-push-image.sh`로 ECR에 push하고, 출력되는 `CONTAINER_IMAGE_URI`를 CloudFormation 배포에 사용할 수 있다.
  - AWS ECS/Fargate에서는 Firebase Admin JSON, APNs `.p8`, KBO relay credential을 Secrets Manager에서 `FIREBASE_SERVICE_ACCOUNT_JSON`, `APNS_AUTH_KEY_P8`, `KBO_RELAY_USER_ID`, `KBO_RELAY_PASSWORD` env로 주입하는 것이 파일 mount보다 단순하다. 로컬/EC2 파일 배포는 `*_PATH`를 계속 쓸 수 있다.
  - ECS task definition의 `secrets` env 주입은 task execution role 권한에 의존한다. `./scripts/aws-push-task-definitions.sh`가 생성한 `iam-task-execution-secrets-policy.rendered.json`를 execution role inline policy로 붙이고, AWS managed `AmazonECSTaskExecutionRolePolicy`도 함께 붙인다.
  - ECS task 등록이나 service 생성 전 `./scripts/aws-push-deploy-check.sh`로 env, rendered JSON, secret, IAM role, ECR, EFS, CloudWatch log group을 한 번에 확인한다.
  - 수동 ECS 조립 대신 `./scripts/aws-push-cloudformation.sh`를 쓰면 ALB, API service, sync worker, EFS token registry, IAM role, log group을 한 stack으로 만든다. ECR image, VPC/subnet, Firebase/APNs secret ARN은 여전히 사전 준비가 필요하다. 도메인/ACM 전 임시 backend smoke는 `ENABLE_HTTPS=false`로 가능하지만, iPhone release token registration은 HTTPS로 되돌려야 한다.
  - CloudFormation deploy 후 `./scripts/aws-push-stack-outputs.sh`가 stack output `ApiBaseUrl`을 `RELEASE_API_BASE_URL` / `API_BASE_URL`로 저장한다.
  - 전체 시연 배포는 `./scripts/aws-push-demo-deploy.sh`를 우선 사용한다. 이 스크립트는 secret upload, ECR image push, CloudFormation deploy, stack output export, push readiness 순서로 실행한다.
  - scoreboard sync 기본 날짜는 AWS UTC가 아니라 KBO 경기일 기준인 `Asia/Seoul`로 계산해야 한다.
  - 5초 시연에는 `python -m kbo_fans_backend.scheduler.live_activity_sync_loop` long-running worker가 EventBridge 1분 one-shot보다 예측 가능하다.
  - `config-status.scheduler.lastSyncAt`은 sync worker가 실제로 registry에 heartbeat를 남겼는지 보는 운영 신호다. secret readiness와 worker activity를 구분해서 판단한다.
- 홈 scoreboard 자동 refresh cadence는 live 8초, scheduled 5분, terminal 정지로 둔다.
- 경기 상세는 live 기본 탭 8초, 문자중계 foreground 원천 갱신은 5초 cadence로 맞춘다.

## Backend Lint / Compatibility

- Backend는 `backend/pyproject.toml` 기준 Python `>=3.9`를 지원하므로, 기본 ruff gate는 `E,F,I,B`로 둔다.
- Python 3.9 정책이 유지되는 동안 pyupgrade(`UP`)를 기본 lint gate에 넣지 않는다. `Optional[...]` / `Union[...]`, `typing.Dict` / `typing.List` 같은 호환 표기를 강제로 바꾸면 repo 규칙과 충돌한다.

## Widget / Live Activity

- Live Activity 선택 우선순위:
  1. 진행중인 마이팀 경기
  2. 진행중인 다른 경기
  3. 오늘 마이팀 라인업 공개 예정 경기
  4. 오늘 다른 라인업 공개 예정 경기
- 라인업 공개 예정 경기 Live Activity는 `경기전` 상태와 양 팀 순위를 스코어 자리에 표시하고, 탭하면 라인업 탭으로 진입한다. 라인업 미공개 예정 경기는 follow session은 유지해도 Activity를 시작하지 않는다.
- 홈 위젯과 Live Activity는 가능한 한 같은 source scoreboard 를 기준으로 동기화한다.
- 중복 업데이트는 signature 비교로 억제한다.
- 앱이 native에서 resumed 될 때만 scoreboard 를 다시 invalidate 해 Live Activity 를 재동기화한다. 웹은 홈 위젯/Live Activity가 없으므로 전역 resume refresh를 등록하지 않는다.
- Live Activity 는 코드상 연결만으로 끝나지 않는다.
  - Widget extension signing
  - App Group entitlement
  - Push Notifications entitlement
  - ActivityKit push token backend registration
  - APNs provider key / team id / bundle id
  - 실제 기기 검증
  를 별도로 확인해야 한다.
- local iPhone debug에서는 `home_widget` / App Group / Workmanager 경로가 런타임 안정성을 해칠 수 있다.
  - `APP_ENV=local` + iOS 에서는 widget sync / periodic refresh 등록을 no-op 처리하는 편이 안전하다.
- foreground 기준 잠금화면 체감 갱신은 홈 scoreboard invalidate 주기에 의해 사실상 상한이 결정된다.
  - live game polling 간격은 홈 scoreboard 8초, 문자중계 foreground/sync worker 5초 기준으로 맞춘다.
  - static widget timeline은 1분 단위 재로드를 요청한다.
  - Live Activity / widget `updatedAt` 에는 초 단위 시각을 넣어 실제 갱신 여부를 구분한다.
- widget/live sync signature는 점수/이닝이 안 바뀌더라도 live 중에는 일정 주기로 다시 흘려보내야 체감 갱신이 유지된다.

## Launch / First Frame

- iOS/Android launch surface 는 앱 테마와 같은 다크 배경을 유지해 흰 화면 플래시를 줄인다.
- launch UI 를 바꾸면 `CHANGELOG.md` 와 `docs/WORKLOG.md` 에 같이 반영한다.

## iOS Build / Pod Warnings

- Pod deployment target 경고는 `Podfile` 의 `post_install` 에서 일괄 보정하는 편이 낫다.
- 플러그인 Objective-C 경고는 repo 코드가 아니라 pub cache / pod 소스라, 가능하면 설정으로 억제하고 근본 수정은 dependency upgrade 로 푼다.
- `dummy.o has no symbols` 는 보통 harmless warning 이다.
- Flutter가 생성하는 `Generated.xcconfig` / `flutter_export_environment.sh` 에 stale `CONFIGURATION_BUILD_DIR` 가 남으면 `Pods_Runner.framework not found` 같은 링크 오류가 날 수 있다.
- Flutter native asset `objective_c.framework` 는 실기기 빌드에서 simulator slice가 섞이거나 adhoc 서명으로 남을 수 있다.
  - 앱 타깃 build phase에서 플랫폼에 맞는 `objective_c.dylib` 를 선택해 덮어쓰고 프레임워크 번들 단위로 다시 codesign 하는 방식이 안전했다.

## Release / Preview

- 프리뷰 릴리즈를 만들 때는:
  1. 워크트리를 먼저 비운다
  2. 최신 `main` 기준 커밋/푸시를 끝낸다
  3. preview tag 를 만든다 (`0.0.1-preview`, 필요 시 `.1`, `.2`)
  4. GitHub prerelease 를 생성한다
- preview tag 는 최신 커밋과 어긋나기 쉬우므로, release 시점의 SHA 를 반드시 확인한다.

## Distribution Docs

- 배포 관련 반복 작업은 아래 문서를 같이 유지한다.
  - `docs/DISTRIBUTION_GUIDE.md`
  - `docs/ANDROID_SIGNING_GUIDE.md`
  - `docs/IOS_TESTFLIGHT_CHECKLIST.md`
