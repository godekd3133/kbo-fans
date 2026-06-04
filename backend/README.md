# KBO Fans Backend

FastAPI backend for the KBO Fans mobile app.

## Goals

- Serve normalized REST APIs for the Flutter client
- Isolate KBO crawling logic from API route handlers
- Keep scheduler, push, and crawling boundaries clean enough for production growth

## Layout

```text
backend/
├── pyproject.toml
├── README.md
├── .env.example
├── src/kbo_fans_backend/
│   ├── api/
│   ├── core/
│   ├── crawlers/
│   ├── push/
│   ├── scheduler/
│   ├── schemas/
│   ├── services/
│   └── utils/
└── tests/
```

## Run locally

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
uvicorn kbo_fans_backend.main:app --reload
```

## Current status

- Health and product API routes are implemented for the current backend contract.
- KBO crawlers are separated from route handlers through service classes.
- Remote push supports FCM test sends, device token registration, ActivityKit token registration, APNs Live Activity updates, and scoreboard-based Live Activity / FCM moment sync.

## Push notifications

Remote push requires Firebase configuration on both app and backend.

- App:
  - iOS `GoogleService-Info.plist`
  - Android `google-services.json`
- Backend:
  - `FIREBASE_SERVICE_ACCOUNT_JSON` or `FIREBASE_SERVICE_ACCOUNT_PATH`
  - optional `FIREBASE_PROJECT_ID`
  - `APNS_KEY_ID`
  - `APNS_TEAM_ID`
  - `APNS_AUTH_KEY_P8` or `APNS_AUTH_KEY_PATH`
  - `APNS_BUNDLE_ID`
  - `APNS_USE_SANDBOX`
  - `PUSH_REGISTRY_PATH`
  - `PUSH_SYNC_SECRET`

Test send endpoint:

```bash
curl -X POST http://localhost:8000/api/push/test \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "KBO Fans Test",
    "body": "Push delivery test",
    "topic": "game_start_LG"
  }'
```

Scoreboard sync endpoint for Live Activity updates and FCM scoring moments:

```bash
curl -X POST http://localhost:8000/api/push/live-activity/sync-scoreboard \
  -H "X-Kbo-Push-Sync-Secret: $PUSH_SYNC_SECRET"
```

When `date` is omitted, the backend uses the current KBO game day in
`Asia/Seoul`, not the host machine's local or UTC date.

Configuration diagnostics endpoint:

```bash
curl http://localhost:8000/api/push/config-status \
  -H "X-Kbo-Push-Sync-Secret: $PUSH_SYNC_SECRET"
```

The response includes `scheduler.lastSyncAt` and `scheduler.lastSyncDate` after
the one-shot scheduler or long-running sync worker has run at least once.

Configuration diagnostics CLI:

```bash
python -m kbo_fans_backend.scheduler.push_config_status
```

Repository readiness check after deployment:

```bash
PUSH_SYNC_SECRET=<secret> ./scripts/push-readiness-check.sh https://api.kbofans.com/api
```

Render AWS ECS/Fargate task definitions and the execution-role secret-read
policy from environment values:

```bash
./scripts/aws-push-task-definitions.sh
```

Validate deployment env, rendered JSON, and AWS resources before registering
task definitions or starting services:

```bash
./scripts/aws-push-deploy-check.sh
```

Provision ALB / ECS / EFS / IAM as one CloudFormation stack:

```bash
./scripts/aws-push-demo-deploy.sh --dry-run
./scripts/aws-push-demo-deploy.sh
```

Manual stage commands:

```bash
./scripts/aws-push-image.sh --tag latest
./scripts/aws-push-cloudformation.sh
./scripts/aws-push-stack-outputs.sh
source outputs/aws/cloudformation/stack.env
```

Create or update AWS Secrets Manager values from local Firebase/APNs files:

```bash
AWS_REGION=<region> \
FIREBASE_SERVICE_ACCOUNT_FILE=/path/firebase-service-account.json \
APNS_AUTH_KEY_FILE=/path/AuthKey_<KEY_ID>.p8 \
./scripts/aws-push-secrets.sh
```

Scheduler CLI for AWS EventBridge scheduled ECS tasks:

```bash
python -m kbo_fans_backend.scheduler.live_activity_sync
```

Long-running sync worker for ECS/Fargate service deployments:

```bash
python -m kbo_fans_backend.scheduler.live_activity_sync_loop
```

## Docker

Build and run the backend image:

```bash
cd backend
docker build -t kbo-fans-backend .
docker run --rm -p 8000:8000 --env-file .env kbo-fans-backend
```

For AWS ECS/Fargate:

- API service command: default Docker `CMD`
- Live Activity sync worker command override:
  - `python`
  - `-m`
  - `kbo_fans_backend.scheduler.live_activity_sync_loop`
- EventBridge one-shot scheduler command override:
  - `python`
  - `-m`
  - `kbo_fans_backend.scheduler.live_activity_sync`
- Store Firebase service account JSON and APNs `.p8` in AWS Secrets Manager and inject them as `FIREBASE_SERVICE_ACCOUNT_JSON` / `APNS_AUTH_KEY_P8`, or mount files and use the path variables.
- `PUSH_REGISTRY_PATH` must point to shared persistent storage if API and scheduler run as separate tasks.
- ECS/Fargate templates and renderer live in `infra/aws/ecs-fargate/`.
