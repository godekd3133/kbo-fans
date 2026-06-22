# Push / Live Activity Backend Setup

> 작성일: 2026-06-04

## 결론

Firebase만으로는 경기 상황을 실시간으로 만들 수 없다.

- FCM: 일반 앱 푸시 알림 전달 채널
- APNs ActivityKit: iOS Live Activity / Dynamic Island 원격 갱신 채널
- Backend: KBO 경기 상태를 주기적으로 읽고, 변화된 상태를 FCM/APNs로 보내는 실행 주체

시연 때 노트북을 끄고 iPhone만 켜 둘 계획이면, backend는 AWS 같은 상시 실행 환경에 배포되어 있어야 한다.

## 필요한 계정 / 키

### Firebase

1. Firebase 프로젝트 생성
2. iOS 앱 등록
   - Bundle ID: `com.kbofans.kboFans`
   - 설정 파일: `GoogleService-Info.plist`
   - 저장 위치: `app/ios/Runner/GoogleService-Info.plist`
3. Android 앱 등록
   - Package: `com.kbofans.kbo_fans`
   - 설정 파일: `google-services.json`
   - 저장 위치: `app/android/app/google-services.json`
4. Firebase Admin service account 발급
   - 파일 예시: `backend/firebase-service-account.json`
   - git에 커밋하지 않는다.

### Apple Developer

1. App ID `com.kbofans.kboFans`에서 Push Notifications capability 활성화
2. Runner provisioning profile 재생성
3. Widget extension provisioning profile도 App Group 포함 상태로 재생성
4. APNs Auth Key 발급
   - Key ID: `APNS_KEY_ID`
   - Team ID: `APNS_TEAM_ID`
   - `.p8` 파일: 예시 `backend/AuthKey_<KEY_ID>.p8`
   - git에 커밋하지 않는다.

## Backend 환경 변수

운영 backend에는 아래 값을 secret/env로 넣는다.

```bash
APP_ENV=release
APP_DEBUG=false
API_PREFIX=/api
FIREBASE_PROJECT_ID=<firebase-project-id>
FIREBASE_SERVICE_ACCOUNT_JSON=<firebase-admin-service-account-json>
APNS_KEY_ID=<apple-apns-key-id>
APNS_TEAM_ID=<apple-team-id>
APNS_AUTH_KEY_P8=<apple-apns-auth-key-p8-content>
APNS_BUNDLE_ID=com.kbofans.kboFans
APNS_USE_SANDBOX=false
PUSH_REGISTRY_PATH=/var/lib/kbo-fans/push_registry.json
PUSH_SYNC_SECRET=<long-random-secret>
PUSH_SYNC_INTERVAL_SECONDS=5
```

AWS ECS/Fargate에서는 `FIREBASE_SERVICE_ACCOUNT_JSON`과 `APNS_AUTH_KEY_P8`을 AWS Secrets Manager에서 환경변수로 주입하는 방식을 권장한다. 로컬/EC2 파일 배포에서는 기존처럼 `FIREBASE_SERVICE_ACCOUNT_PATH`, `APNS_AUTH_KEY_PATH`를 사용할 수 있다.

개발/실기기 debug에서는 `APNS_USE_SANDBOX=true`를 쓴다. TestFlight / App Store 시연은 `APNS_USE_SANDBOX=false`가 필요하다.

AWS Secrets Manager 업로드:

```bash
AWS_REGION=<region> \
FIREBASE_SERVICE_ACCOUNT_FILE=/path/firebase-service-account.json \
APNS_AUTH_KEY_FILE=/path/AuthKey_<KEY_ID>.p8 \
./scripts/aws-push-secrets.sh
```

이 스크립트는 secret 값을 출력하지 않고, task definition renderer에서 쓸 `SECRET_ARN_*` export를 출력하고 `outputs/aws/ecs-fargate/secrets.env`에 저장한다.

## AWS 배포 권장안

가장 단순한 시연용 구조:

1. AWS ECS Fargate 또는 EC2에 FastAPI backend 배포
2. HTTPS 도메인 연결
   - 권장: `https://api.kbofans.com/api`
3. Firebase service account와 APNs `.p8`는 AWS Secrets Manager 또는 EC2 파일 secret으로 주입
4. `PUSH_REGISTRY_PATH`는 재시작 후에도 남는 저장소를 사용
   - EC2: EBS 경로
   - ECS: EFS 또는 이후 DB/DynamoDB로 대체
5. Fargate sync worker 또는 cron으로 scoreboard/relay sync를 5초마다 실행
   - ActivityKit token이 등록된 경기는 APNs `liveactivity` update/end 발송
   - FCM device/topic 등록이 있으면 scoreboard diff 기준 `game_start`, `scoring`, `reversal`, `game_end`, `inning_change`, `at_bat` topic push 발행
   - 일반 FCM message에는 iOS APNs `apns-push-type=alert`, `apns-topic`, `aps.alert`, `aps.content-available=1`, `apns-priority=10`, default sound와 Android high priority / default sound 옵션을 포함
   - `homerun`은 live relay seq diff 기준으로 새 `HOMERUN` event 또는 `홈런` 텍스트가 들어올 때 topic push 발행

```bash
curl -X POST "https://api.kbofans.com/api/push/live-activity/sync-scoreboard" \
  -H "X-Kbo-Push-Sync-Secret: $PUSH_SYNC_SECRET"
```

```bash
python -m kbo_fans_backend.scheduler.live_activity_sync
```

Fargate에서 5초 단위 시연이 필요하면 장기 실행 worker를 쓴다.

```bash
python -m kbo_fans_backend.scheduler.live_activity_sync_loop
```

배포 후 설정 진단:

```bash
curl "https://api.kbofans.com/api/push/config-status" \
  -H "X-Kbo-Push-Sync-Secret: $PUSH_SYNC_SECRET"
```

repo에서 한 번에 확인:

```bash
PUSH_SYNC_SECRET=<long-random-secret> ./scripts/push-readiness-check.sh https://api.kbofans.com/api
```

readiness check는 기본적으로 `scheduler.lastSyncAt`이 180초 이내인지 확인한다. 이 값이 없거나 오래됐으면 API secret이 맞아도 sync worker가 멈춘 상태일 수 있으므로 실패해야 한다. 설정값만 먼저 확인할 때만 `PUSH_READINESS_REQUIRE_SCHEDULER=false`를 붙인다. `PUSH_READINESS_RUN_SYNC=true`를 붙이면 readiness check 중 `/push/live-activity/sync-scoreboard`를 한 번 호출한 뒤 config-status를 다시 읽어 heartbeat를 확인한다. `PUSH_READINESS_DATE`를 생략하면 date query를 보내지 않고 backend의 `Asia/Seoul` KBO 경기일 기본값을 사용한다. 특정 날짜 재현이 필요할 때만 `PUSH_READINESS_DATE=YYYY-MM-DD`를 지정한다.

또는 서버/ECS task 안에서:

```bash
python -m kbo_fans_backend.scheduler.push_config_status
```

`readyForIphoneOnlyDemo`가 `true`여야 TestFlight/운영 APNs, Firebase Admin, registry 저장소, scheduler secret이 모두 준비된 상태다.
`scheduler.lastSyncAt` / `scheduler.lastSyncDate`가 갱신되면 sync worker 또는 scheduler가 실제로 실행된 상태다.

KBO live 경기는 5초 sync worker, 예정 경기는 5분, 종료 경기는 sync 중단 정책이 적절하다.

배포 전에 로컬 설정 파일과 env 형태를 먼저 확인한다. 이 명령은 AWS를 호출하지 않고 secret 값을 출력하지 않는다.

```bash
./scripts/push-live-preflight.sh --app-only
./scripts/push-live-preflight.sh --env-file /path/to/kbo-fans-aws.env --aws
```

`--app-only`는 Firebase client 파일, APNs entitlement, Live Activity plist, Android google-services plugin, Flutter push registration 연결, release `API_BASE_URL` token-registration handoff를 확인한다. `--env-file ... --aws`는 Firebase Admin JSON, APNs `.p8`, `PUSH_SYNC_SECRET`, ECR/VPC/subnet/HTTPS mode env 형태까지 같이 확인한다. `ENABLE_HTTPS=false`는 도메인/ACM 전 임시 AWS backend smoke에만 사용하고, iPhone release token registration은 `ENABLE_HTTPS=true`와 `API_DOMAIN_NAME` / `ACM_CERTIFICATE_ARN`으로 되돌린다.

## Backend Docker 이미지

저장소에는 `backend/Dockerfile`이 있다.

```bash
cd backend
docker build -t kbo-fans-backend .
docker run --rm -p 8000:8000 --env-file .env kbo-fans-backend
```

ECS/Fargate에서는 같은 이미지를 두 방식으로 쓴다.

- API service: 기본 `CMD`
- Sync worker service command override:
  - `python`
  - `-m`
  - `kbo_fans_backend.scheduler.live_activity_sync_loop`
- EventBridge one-shot task command override:
  - `python`
  - `-m`
  - `kbo_fans_backend.scheduler.live_activity_sync`

API service와 Scheduler task가 같은 ActivityKit token registry를 봐야 하므로, `PUSH_REGISTRY_PATH`는 EFS/EBS 같은 공유 영속 경로를 사용한다. 현재 JSON registry는 같은 디렉터리의 lock file과 atomic replace로 API service / sync worker 동시 쓰기를 보호한다. 다중 인스턴스 운영으로 커지면 DynamoDB/RDS로 바꾸는 것이 맞다.

ECS/Fargate용 템플릿은 `infra/aws/ecs-fargate/`에 있다.

ECS/Fargate 배포는 두 경로가 있다.

- `infra/aws/ecs-fargate/`: 이미 만든 AWS 리소스에 task definition / IAM policy를 등록하는 수동 경로
- `infra/aws/cloudformation/`: ALB, ECS API service, sync worker, EFS, IAM, log group을 한 stack으로 만드는 경로

`infra/aws/ecs-fargate/deploy.env.example`를 로컬 env 파일로 복사한 뒤, 실제 AWS / Firebase / Apple 값을 채운다. 이 파일 하나가 preflight, 로컬 AWS 배포, GitHub Actions secrets/variables 업로드에 같이 쓰이는 준비 파일이다.

```bash
cp infra/aws/ecs-fargate/deploy.env.example /tmp/kbo-fans-aws.env
$EDITOR /tmp/kbo-fans-aws.env
./scripts/push-live-preflight.sh --env-file /tmp/kbo-fans-aws.env --aws
```

처음부터 복사해서 채우기보다 현재 repo의 Firebase client config 경로와 project id를 자동 반영한 초안을 만들 수도 있다.

```bash
./scripts/push-demo-env-bootstrap.sh --output /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans --force
$EDITOR /tmp/kbo-fans-aws.env
./scripts/push-demo-readiness-audit.sh --env-file /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans
```

bootstrap은 AWS, GitHub, Firebase, Apple API를 호출하지 않는다. `PUSH_SYNC_SECRET`는 로컬 파일에만 생성하고 출력하지 않으며, Apple APNs key와 AWS role/network/HTTPS 값은 placeholder로 남겨 audit이 잡게 한다. 생성된 env 파일에는 각 값의 발급 위치와 GitHub Secrets/Variables 업로드 대상이 주석으로 들어간다. `push-live-preflight.sh --aws`는 필수 배포값이 obvious placeholder로 남아 있으면 실패로 처리한다.

전체 준비 상태를 한 번에 보고 싶으면 setup status를 먼저 실행한다. 이 명령은 env 파일이 없으면 초안을 만들고, GitHub OIDC role dry-run과 readiness audit까지 실행하지만 실제 AWS 배포나 GitHub workflow dispatch는 하지 않는다.

```bash
./scripts/push-demo-setup-status.sh \
  --env-file /tmp/kbo-fans-aws.env \
  --repo godekd3133/kbo-fans
```

출력의 `Required Values` 섹션은 사장님이 직접 준비해야 하는 값을 한 번에 보여준다. 각 항목은 `get_from`, `put_in_env`, `github_target`, `aws_runtime_target`로 나뉘며, Firebase client 파일, Firebase Admin JSON, Apple APNs `.p8`, AWS ECR/VPC/Subnet/HTTPS mode, GitHub OIDC role, release `API_BASE_URL`을 어디서 가져와 어디에 넣는지 확인하는 기준이다.

`PUSH_SYNC_SECRET`는 `openssl rand -hex 32`로 만들고, `IOS_GOOGLE_SERVICE_INFO_PLIST_FILE`, `ANDROID_GOOGLE_SERVICES_JSON_FILE`, `FIREBASE_SERVICE_ACCOUNT_FILE`, `APNS_AUTH_KEY_FILE`은 로컬 파일 경로를 넣는다. GitHub Actions 배포를 쓸 때는 `AWS_ROLE_TO_ASSUME` OIDC role을 권장하며, 없으면 `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`를 넣는다. `github-push-secrets.sh`는 obvious placeholder 값을 GitHub에 업로드하지 못하게 막는다.

GitHub Actions용 AWS OIDC role은 아래 스크립트로 만들 수 있다. GitHub 공식 AWS OIDC 설정은 provider URL `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com`를 사용하고, AWS IAM은 `token.actions.githubusercontent.com:sub` 조건으로 repo/branch를 제한하라고 안내한다. 이 repo의 스크립트도 `repo:godekd3133/kbo-fans:ref:refs/heads/main`만 role을 assume할 수 있게 만든다.

```bash
./scripts/aws-github-oidc-role.sh \
  --env-file /tmp/kbo-fans-aws.env \
  --repo godekd3133/kbo-fans \
  --update-env-file \
  --dry-run

./scripts/aws-github-oidc-role.sh \
  --env-file /tmp/kbo-fans-aws.env \
  --repo godekd3133/kbo-fans \
  --update-env-file
```

실행 후 `/tmp/kbo-fans-aws.env`의 `AWS_ROLE_TO_ASSUME`가 실제 role ARN으로 바뀐다. 그 다음 `./scripts/github-push-secrets.sh --env-file /tmp/kbo-fans-aws.env --apply`를 실행하면 GitHub Actions secret으로 올라간다. OIDC role 생성 자체는 AWS IAM/CloudFormation 권한이 있는 로컬 AWS credential이 필요하다.

수동 경로의 실행 순서는 아래가 안전하다.

1. `./scripts/aws-push-secrets.sh`로 Secrets Manager 값을 만들고 `outputs/aws/ecs-fargate/secrets.env`를 생성한다.
2. `./scripts/aws-push-image.sh`로 backend Docker image를 ECR에 push하고 `outputs/aws/ecr/image.env`를 생성한다.
3. ECS task execution role / task role을 만든다.
4. ECR repository, EFS, CloudWatch log group을 만든다.
5. role ARN / ECR URI / EFS ID / secret ARN을 env로 넣고 `./scripts/aws-push-task-definitions.sh`를 실행한다.
6. 렌더링된 secret-read policy를 execution role에 붙인다.
7. `./scripts/aws-push-deploy-check.sh`로 AWS 리소스와 rendered JSON을 점검한다.

ECS IAM 최소 구성:

```bash
aws iam create-role \
  --role-name kbo-fans-ecs-task-execution \
  --assume-role-policy-document file://infra/aws/ecs-fargate/ecs-task-assume-role-policy.json

aws iam attach-role-policy \
  --role-name kbo-fans-ecs-task-execution \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

aws iam create-role \
  --role-name kbo-fans-ecs-task \
  --assume-role-policy-document file://infra/aws/ecs-fargate/ecs-task-assume-role-policy.json
```

CloudWatch log group도 task 실행 전에 만들어 둔다.

```bash
aws logs create-log-group \
  --region <AWS_REGION> \
  --log-group-name /ecs/kbo-fans-backend
```

task definition placeholder는 직접 편집하지 말고, AWS ARN/ID 값을 환경변수로 넣은 뒤 renderer로 생성한다. 이 renderer는 ECS task definition 2개와 task execution role에 붙일 Secrets Manager read policy를 함께 만든다.

```bash
source /tmp/kbo-fans-aws.env
source outputs/aws/ecs-fargate/secrets.env

./scripts/aws-push-task-definitions.sh
./scripts/aws-push-deploy-check.sh --skip-aws
```

렌더링 후 execution role에 push secret read inline policy를 붙인다.

```bash
aws iam put-role-policy \
  --role-name kbo-fans-ecs-task-execution \
  --policy-name kbo-fans-read-push-secrets \
  --policy-document file://outputs/aws/ecs-fargate/iam-task-execution-secrets-policy.rendered.json
```

AWS 리소스까지 실제로 보이는지 사전점검한다.

```bash
./scripts/aws-push-deploy-check.sh
```

렌더링 결과는 `outputs/aws/ecs-fargate/`에 생성되며 gitignore 대상이다. `AmazonECSTaskExecutionRolePolicy`는 ECR image pull과 CloudWatch Logs 기록에 필요하고, `kbo-fans-read-push-secrets` inline policy는 Firebase Admin JSON / APNs `.p8` / sync secret 주입에 필요하다. Secrets Manager 값이 customer-managed KMS key로 암호화되어 있으면 execution role에 해당 key의 `kms:Decrypt`도 추가한다.

CloudFormation 경로는 ECR image, VPC/subnet, Firebase/APNs secret ARN이 준비된 뒤 실행한다. 기본 image는 `$ECR_REPOSITORY_URI:latest`이고, 특정 tag를 쓰려면 `CONTAINER_IMAGE_URI`를 지정한다. 도메인/ACM certificate가 준비되지 않았으면 `ENABLE_HTTPS=false`로 HTTP-only AWS smoke deploy를 먼저 실행할 수 있다. 이 경우 stack output `ApiBaseUrl`은 `http://<alb-dns>/api`이며, 실제 iPhone release token registration에는 HTTPS 도메인이 필요하다.

```bash
source /path/to/kbo-fans-aws.env

./scripts/aws-push-demo-deploy.sh --dry-run
./scripts/aws-push-demo-deploy.sh
source outputs/aws/cloudformation/stack.env
```

통합 스크립트는 secret 업로드, backend image ECR push, CloudFormation deploy, stack output 추출, push readiness를 순서대로 실행한다. 실행 전에 `./scripts/push-live-preflight.sh --env-file /path/to/kbo-fans-aws.env --aws`로 로컬 앱 설정과 배포 env 형태를 확인한다. stack output의 `ApiBaseUrl`을 release `API_BASE_URL`로 사용한다. `aws-push-stack-outputs.sh`는 이 값을 `outputs/aws/cloudformation/stack.env`에 `RELEASE_API_BASE_URL` / `API_BASE_URL`로 저장한다. 커스텀 도메인(`https://api.kbofans.com/api`)을 쓸 경우 Route53 alias/CNAME을 output `LoadBalancerDnsName`으로 연결한 뒤 해당 도메인을 앱 release build에 주입한다.

KBO 문자중계는 `KBO_RELAY_USER_ID` / `KBO_RELAY_PASSWORD`가 API service와 sync worker 양쪽에 주입되어야 한다. 이 값이 빠지면 `/api/game/{gameId}/relay`가 live game에서 500으로 실패하고, relay 기반 홈런/타석 push도 동작하지 않는다.

로컬 Mac에서 배포할 때는 먼저 AWS CLI credential과 Docker daemon 상태를 확인한다.

```bash
./scripts/aws-push-tooling-check.sh
```

AWS CLI가 없거나 Docker Desktop이 꺼져 있으면 로컬 image build/push와 CloudFormation deploy가 진행되지 않는다. 이 경우 GitHub Actions의 `Push Demo Deploy` workflow로 같은 파이프라인을 runner에서 실행할 수 있다.

GitHub Actions에 넣을 값:

- `AWS_ROLE_TO_ASSUME` 또는 `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `IOS_GOOGLE_SERVICE_INFO_PLIST`
- `ANDROID_GOOGLE_SERVICES_JSON`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_SERVICE_ACCOUNT_JSON`
- `APNS_AUTH_KEY_P8`
- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `PUSH_SYNC_SECRET`
- `KBO_RELAY_USER_ID`
- `KBO_RELAY_PASSWORD`
- `ECR_REPOSITORY_URI`
- `VPC_ID`
- `PUBLIC_SUBNET_A_ID`
- `PUBLIC_SUBNET_B_ID`
- `ENABLE_HTTPS` (`true` 기본값, 도메인 전 HTTP-only smoke는 `false`)
- `API_DOMAIN_NAME` (선택, ACM certificate와 일치하는 커스텀 도메인)
- `ACM_CERTIFICATE_ARN` (`ENABLE_HTTPS=true`일 때 필수)

Actions workflow `Push Demo Deploy`에서 `dry_run=true`를 먼저 실행하면 secret/env 형태와 repo script path를 검증한다. `dry_run=false`는 실제 secret upload, ECR image push, CloudFormation deploy, stack output export, readiness를 실행한다.

GitHub Actions secrets/variables는 `gh` CLI로도 넣을 수 있다. 기본은 dry-run이고 실제 업로드는 `--apply`를 붙였을 때만 실행된다.

```bash
./scripts/push-demo-env-bootstrap.sh --output /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans --force
$EDITOR /tmp/kbo-fans-aws.env
./scripts/push-demo-setup-status.sh --env-file /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans
./scripts/push-live-preflight.sh --env-file /tmp/kbo-fans-aws.env --aws
./scripts/aws-github-oidc-role.sh --env-file /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans --update-env-file --dry-run
./scripts/aws-github-oidc-role.sh --env-file /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans --update-env-file
./scripts/github-push-secrets.sh --env-file /tmp/kbo-fans-aws.env
./scripts/github-push-secrets.sh --env-file /tmp/kbo-fans-aws.env --apply
```

이 스크립트는 `IOS_GOOGLE_SERVICE_INFO_PLIST`, `ANDROID_GOOGLE_SERVICES_JSON`, `FIREBASE_SERVICE_ACCOUNT_JSON`, `APNS_AUTH_KEY_P8`, `PUSH_SYNC_SECRET`, `AWS_ROLE_TO_ASSUME` 또는 AWS access key를 GitHub Secrets로 넣고, `AWS_REGION`, `FIREBASE_PROJECT_ID`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `ECR_REPOSITORY_URI`, `VPC_ID`, subnet, `ENABLE_HTTPS`, 선택 `API_DOMAIN_NAME`, 조건부 ACM ARN은 GitHub Variables로 넣는다. secret 값은 로그에 출력하지 않고, obvious placeholder 값은 업로드 전에 실패시킨다.

workflow 파일이 GitHub default branch에 올라간 뒤에는 CLI로 dispatch할 수 있다.

```bash
./scripts/github-push-demo-run.sh --dry-run true --watch
./scripts/github-push-demo-run.sh --dry-run false --watch
./scripts/github-push-test-notification-run.sh --topic baseball_info_ALL --watch
./scripts/github-push-receipt-status-run.sh --watch
```

현재 원격에 `.github/workflows/push-demo-deploy.yml`가 없으면 이 스크립트는 실패하면서 커밋/푸시가 필요하다고 안내한다. 필수 GitHub secrets/variables가 없으면 workflow run을 만들기 전에 누락 목록을 출력하고 중단한다. 이미 별도 확인을 끝낸 경우에만 `--skip-config-check`로 우회한다.
원격 테스트 푸시는 `.github/workflows/push-test-notification.yml`가 원격 default branch에 올라간 뒤 실행할 수 있다. 이 workflow는 GitHub secret `PUSH_SYNC_SECRET`과 variable `RELEASE_API_BASE_URL`을 사용하며, 로컬 CLI는 secret/token 값을 출력하지 않는다.
단말 receipt 조회는 `.github/workflows/push-receipt-status.yml` 또는 `./scripts/github-push-receipt-status-run.sh --expect-receipt --game-id <gameId> --type <type> --watch`로 실행한다. 이 workflow는 `GET /api/push/config-status`의 `pushReceiptCount` / `recentPushReceipts` 요약만 출력하고 raw device token은 출력하지 않는다.

전체 준비 상태를 한 번에 볼 때는 audit 스크립트를 쓴다. 이 명령은 앱 파일, env checklist, 로컬 AWS/Docker tooling, GitHub Actions workflow/secrets/variables, 최신 workflow run을 확인하지만 배포나 workflow dispatch는 하지 않는다.

```bash
./scripts/push-demo-readiness-audit.sh --env-file /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans
```

현재 GitHub secrets/variables가 비어 있으면 이 audit은 실패해야 한다. 그 상태가 정상적인 다음 액션 신호이며, `github-push-secrets.sh --apply` 이후 다시 audit을 실행한다.

audit 출력은 두 종류로 나뉜다.

- `next_config[...]`: Firebase Console, Apple Developer, AWS, GitHub 중 어디에서 어떤 값을 준비해야 하는지 알려주는 설정 작업
- `next_command:`: 준비한 env 파일을 기준으로 다음에 실행할 검증/업로드/배포 명령

예를 들어 `IOS_GOOGLE_SERVICE_INFO_PLIST`가 없으면 Firebase iOS 앱 설정 파일을 받아 `IOS_GOOGLE_SERVICE_INFO_PLIST_FILE`에 넣으라고 표시하고, `APNS_AUTH_KEY_P8`가 없으면 Apple APNs `.p8`와 `APNS_KEY_ID` / `APNS_TEAM_ID` 준비를 안내한다. secret 값 자체는 출력하지 않는다.
로컬 파일이나 env 값이 이미 준비되어 있는데 GitHub Actions secret/variable만 비어 있으면, audit은 새로 발급하라고 하지 않고 `github-push-secrets.sh --apply`로 업로드하라고 안내한다.

## 앱 빌드 설정

iOS release/TestFlight 앱은 아래가 필요하다.

- `app/ios/Runner/GoogleService-Info.plist`
- Runner target Push Notifications capability
- Runner entitlements의 `aps-environment`
  - Debug/Profile: `development`
  - Release: `production`
- Runner와 Widget extension `Info.plist`의 `NSSupportsLiveActivities=true`
- 5초 스포츠 갱신 시연을 위한 `NSSupportsLiveActivitiesFrequentUpdates=true`
- App Group: `group.com.kbofans.kbo_fans`
- Widget extension 포함 provisioning profile

앱은 사용자가 경기 상세에서 `경기 따라가기`를 누르면 ActivityKit push token을 backend에 등록한다. 이후 앱이 꺼져 있어도 backend가 APNs `liveactivity` push를 보내면 Dynamic Island가 갱신된다. 일반 푸시 설정은 FCM topic subscription으로 동작하며, backend scheduler가 scoreboard diff를 보고 득점/역전/종료/타석 같은 moment push를 발행하고 relay diff로 홈런 push를 발행한다.

## 완료 확인

- `POST /api/push/register`가 FCM token을 registry에 저장
- `POST /api/push/live-activity/register`가 ActivityKit token을 registry에 저장
- `./scripts/push-live-preflight.sh --env-file /path/to/kbo-fans-aws.env --aws`가 실패 0개로 통과
- `GET /api/push/config-status`의 `readyForIphoneOnlyDemo`가 `true`
- `GET /api/push/config-status`의 `registry.registeredDeviceCount`, `registry.topicCounts.game_start_soon_<팀>`, `registry.topicCounts.hit_<팀>`이 기대 단말/topic 등록과 일치
- `GET /api/push/config-status`의 `registry.deviceSummaries`가 기대 단말의 `installationIdSuffix`, `notificationsAllowed=true`, `authorizationStatus=authorized` 또는 `provisional`, iOS `apnsTokenReady=true`, 최신 앱 등록 `updatedAt`, topic 재동기화 `topicsUpdatedAt`을 token 원문 없이 보여줌
- `GET /api/push/config-status`의 `scheduler.lastSyncAt`이 sync worker 주기에 맞춰 갱신
- `PUSH_SYNC_SECRET=<...> ./scripts/push-readiness-check.sh https://api.kbofans.com/api` 통과
- `POST /api/push/live-activity/sync-scoreboard`가 등록된 live game에 APNs update/end를 보내고, 일반 푸시 등록 기기가 있으면 scoreboard diff와 relay diff 기반 FCM moment push를 보냄
- iPhone 실기기에서 앱을 종료한 뒤에도 Live Activity `updatedAt`이 서버 sync 주기에 맞춰 변경
- 일반 push 발송은 Firebase Console, `X-Kbo-Push-Sync-Secret`이 포함된 `/api/push/test`, `PUSH_SYNC_SECRET=<...> ./scripts/push-test-notification.sh --topic <topic>`, GitHub Actions `Push Test Notification`, 또는 scheduler의 `pushedMoments` 응답으로 확인
- 일반 visible push의 iOS APNs payload에는 alert/sound와 함께 `content-available=1`이 있어야 하며, 앱에는 `remote-notification` background mode와 Firebase background handler가 있어야 한다.
- 실제 단말 처리 receipt는 `PUSH_SYNC_SECRET=<...> ./scripts/push-receipt-status.sh --expect-receipt --game-id <gameId> --type <type>` 또는 GitHub Actions `Push Receipt Status`로 `/api/push/config-status`의 `recentPushReceipts`에 기록됐는지 확인
- 앱 안에서는 `설정 > API 진단 > 원격 푸시 테스트`가 현재 기기의 FCM token을 `/push/register`로 동기화한 뒤 `/push/test-device`로 self-test push를 요청

## 현재 코드 기준 주의

- `backend/data/runtime/`은 gitignore되어 실제 토큰이 커밋되지 않는다.
- 지금 token registry는 JSON 파일 기반이다. 시연에는 충분하고 파일락/atomic write로 API service와 sync worker의 동시 쓰기를 보호하지만, 다중 서버 운영으로 가면 DynamoDB/RDS 같은 영속 저장소로 바꿔야 한다.
- 앱 화면 데이터는 no-backend direct KBO 경로를 유지할 수 있지만, 앱 종료 후 push/Dynamic Island 실시간 갱신은 backend 없이는 불가능하다.
