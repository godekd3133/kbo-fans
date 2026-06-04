# iOS Live Activity / Widget Skill

## When To Use

- iOS WidgetKit, Live Activity, Dynamic Island 를 수정할 때
- 홈 위젯과 Live Activity 간 선택 우선순위를 맞출 때
- App Group, widget sync, resumed 재동기화 흐름을 점검할 때

## Files To Check First

- `app/lib/services/widget_sync_service.dart`
- `app/lib/services/live_activity_service.dart`
- `app/lib/main.dart`
- `app/ios/Runner/AppDelegate.swift`
- `app/ios/Runner/BackgroundIntent.swift`
- `app/ios/KboFansWidget/KboFansWidget.swift`
- `app/ios/Runner.xcodeproj/project.pbxproj`

## Working Rules

- Live Activity 선택 규칙은 문서와 코드에서 같이 유지한다.
  1. 진행중인 마이팀 경기
  2. 진행중인 다른 경기
  3. 오늘 마이팀 예정 경기
  4. 오늘 다른 예정 경기
- 홈 위젯과 Live Activity 동기화는 가능한 한 같은 scoreboard payload 를 사용한다.
- duplicate update 는 signature 비교로 막는다.
- 앱 resumed 시 scoreboard invalidate 를 통해 재동기화한다.
- Dynamic Island 는 UI만 구현해도 끝난 게 아니다.
  - Widget extension target membership
  - App Group entitlements
  - real device verification
  - ActivityKit push token backend registration
  - APNs `liveactivity` production push path
  를 체크한다.
- 앱 종료 후 Live Activity / Dynamic Island 갱신은 앱 direct data path가 아니라 backend scheduler/worker가 책임진다.
- release no-backend direct build도 token registration을 위해 운영 `API_BASE_URL`을 주입해야 한다. `USE_BACKEND_API=true`가 없으면 provider routing은 direct data로 유지된다.
- AWS 운영에서는 `FIREBASE_SERVICE_ACCOUNT_JSON`, `APNS_AUTH_KEY_P8`, `PUSH_SYNC_SECRET` secret env와 공유 `PUSH_REGISTRY_PATH`를 확인한다. JSON registry는 sibling lock file과 atomic replace를 쓰므로 API service와 sync worker가 같은 EFS/EBS 경로를 봐야 한다.
- 시연 배포 전에는 `./scripts/push-live-preflight.sh --env-file /path/to/kbo-fans-aws.env --aws`로 앱 Firebase 파일, APNs/Live Activity capability, backend secret env, AWS env 형태를 secret 출력 없이 점검한다.
- `infra/aws/ecs-fargate/deploy.env.example`를 push preflight, 로컬 AWS 배포, GitHub Actions secrets/variables 업로드의 단일 checklist로 사용한다. untracked env 파일로 복사한 뒤 placeholder를 모두 실제 값으로 바꾸고 `--apply`를 실행한다.
- 처음 env 파일을 만들 때는 `./scripts/push-demo-env-bootstrap.sh --output /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans --force`로 로컬 Firebase client config 경로와 project id가 반영된 초안을 만들 수 있다. Apple/APNs/AWS placeholder는 그대로 audit에서 잡히게 두고, 파일 안 주석을 각 값의 발급 위치와 업로드 대상 checklist로 사용한다.
- 전체 setup 흐름이 헷갈리면 `./scripts/push-demo-setup-status.sh --env-file /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans`를 먼저 실행한다. 이 명령은 env 생성, OIDC dry-run, readiness audit, 다음 명령 안내를 묶고 배포/dispatch는 하지 않는다.
- `push-live-preflight.sh --aws`는 배포 필수값의 obvious placeholder를 실패로 처리해야 한다. 첫 누락 파일에서 멈추지 말고 Firebase Admin, APNs, AWS 값들을 한 번에 모아 보여줘야 한다.
- `./scripts/push-demo-readiness-audit.sh --env-file /path/to/kbo-fans-aws.env --repo godekd3133/kbo-fans`로 앱 파일, env checklist, 로컬 tooling, GitHub Actions 입력값, 최신 deploy run을 배포 없이 점검한다. secret 값은 출력하지 않는다.
- AWS push secret은 `./scripts/aws-push-secrets.sh`로 생성/갱신한다.
- backend ECR image는 `./scripts/aws-push-image.sh`로 build/tag/push하고, 특정 tag 배포 시 `outputs/aws/ecr/image.env`의 `CONTAINER_IMAGE_URI`를 사용한다.
- ECS task definition과 execution-role secret-read policy는 `./scripts/aws-push-task-definitions.sh` 또는 `./scripts/codex-run.sh aws-push-task-defs`로 렌더링한다.
- ECS task 등록이나 service 생성 전 `./scripts/aws-push-deploy-check.sh`로 env, rendered JSON, secret, IAM role, ECR, EFS, CloudWatch log group 존재 여부를 점검한다.
- ALB, ECS service 2개, EFS registry, IAM role, log group을 한 번에 만들 때는 `./scripts/aws-push-cloudformation.sh`를 사용한다.
- CloudFormation stack output은 `./scripts/aws-push-stack-outputs.sh`로 추출하고, `outputs/aws/cloudformation/stack.env`의 `RELEASE_API_BASE_URL` / `API_BASE_URL`을 release build에 주입한다.
- 전체 시연 배포는 `./scripts/aws-push-demo-deploy.sh`를 우선 사용한다. secret 업로드, image push, CloudFormation deploy, output export, readiness를 순서대로 실행한다.
- 로컬 AWS CLI 또는 Docker daemon이 준비되지 않았으면 GitHub Actions `Push Demo Deploy` workflow를 사용한다.
- GitHub Actions AWS 인증은 access key보다 `AWS_ROLE_TO_ASSUME` OIDC role을 우선한다. `./scripts/aws-github-oidc-role.sh --env-file /path/to/kbo-fans-aws.env --repo godekd3133/kbo-fans --update-env-file`로 main branch 전용 trust policy를 만든 뒤 GitHub secrets에 업로드한다.
- GitHub Actions secrets/vars 준비는 `./scripts/github-push-secrets.sh --env-file /path/to/kbo-fans-aws.env` dry-run 후 `--apply`로 실행한다. secret 값을 로그에 출력하지 않는다.
- workflow 파일이 커밋/푸시된 뒤 `./scripts/github-push-demo-run.sh --dry-run true --watch`로 dry-run을 실행하고, 통과 후 `--dry-run false --watch`로 실제 배포한다. 이 스크립트는 dispatch 전에 필수 GitHub secrets/variables를 확인하며, 별도 점검을 끝낸 경우에만 `--skip-config-check`로 우회한다.
- scoreboard sync 기본 날짜는 `Asia/Seoul` KBO 경기일 기준이어야 한다.
- `GeneratedPluginRegistrant.register(...)` 중복 호출로 duplicate plugin crash 가 나지 않게 한다.
- widget extension plist 에서는
  - `CFBundleShortVersionString = $(MARKETING_VERSION)`
  - `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`
  를 사용한다.
- `Runner` / widget target 의 `SUPPORTED_PLATFORMS` 는 `iphoneos iphonesimulator` 로 명시한다.
- Xcode 의 `-showdestinations` 에 실제 iPhone / Simulator destination 이 보이는지 먼저 확인한다.

## Common Failure Clues

- `Duplicate plugin key: FLTFirebaseCorePlugin`
- `No such module 'workmanager'`
- `No such module 'home_widget'`
- `Appex bundle ... does not have a CFBundleVersion`
- `Found no destinations for the scheme`
- `iOS xx.x is not installed`

## Done Criteria

- Flutter -> native channel -> ActivityKit 경로가 끊기지 않는다
- 홈 화면 밖에서도 동기화가 유지된다
- 실기기 확인 필요 여부를 문서/답변에 명시한다
