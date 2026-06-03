# AWS ECS Fargate Push Demo Deployment

> Purpose: run KBO Fans push / Live Activity backend without the developer laptop.

## Target Shape

- ECS Fargate service 1: FastAPI backend HTTP API
- ECS Fargate service 2: scoreboard sync worker
- ECR: Docker image repository
- ALB + ACM: HTTPS endpoint such as `https://api.kbofans.com/api`
- EFS: shared runtime registry for FCM device tokens and ActivityKit push tokens
- Secrets Manager: Firebase Admin JSON, APNs `.p8`, sync secret
- IAM: ECS task execution role with ECR/log permissions plus push secret read access

This is the recommended iPhone-only demo path. The same Docker image is used for
both services; only the container command differs.

## Secrets Manager Values

Create these secrets before registering the ECS task definitions.

| Secret name | ECS env var | Value |
| --- | --- | --- |
| `/kbo-fans/firebase-service-account-json` | `FIREBASE_SERVICE_ACCOUNT_JSON` | Exact Firebase Admin service account JSON |
| `/kbo-fans/apns-auth-key-p8` | `APNS_AUTH_KEY_P8` | Exact Apple APNs Auth Key `.p8` content |
| `/kbo-fans/push-sync-secret` | `PUSH_SYNC_SECRET` | Long random secret string |

Keep these as AWS secrets. Do not write the values into repository files.

Create or update those secrets from local files:

```bash
AWS_REGION=<AWS_REGION> \
FIREBASE_SERVICE_ACCOUNT_FILE=/path/firebase-service-account.json \
APNS_AUTH_KEY_FILE=/path/AuthKey_<KEY_ID>.p8 \
./scripts/aws-push-secrets.sh
```

The script prints the three `SECRET_ARN_*` exports needed by the task definition
renderer and writes them to `outputs/aws/ecs-fargate/secrets.env`.

Build and push the backend image:

```bash
AWS_REGION=<AWS_REGION> \
ECR_REPOSITORY_URI=<ECR_REPOSITORY_URI> \
./scripts/aws-push-image.sh --tag latest
source outputs/aws/ecr/image.env
```

## Non-secret Environment

Both task definitions use these values:

```bash
APP_ENV=release
APP_DEBUG=false
API_PREFIX=/api
PORT=8000
FIREBASE_PROJECT_ID=<firebase-project-id>
APNS_KEY_ID=<apple-apns-key-id>
APNS_TEAM_ID=<apple-team-id>
APNS_BUNDLE_ID=com.kbofans.kboFans
APNS_USE_SANDBOX=false
PUSH_REGISTRY_PATH=/var/lib/kbo-fans/push_registry.json
PUSH_SYNC_INTERVAL_SECONDS=60
```

`APNS_USE_SANDBOX=false` is required for TestFlight / App Store production APNs.

## Files In This Directory

- `ecs-task-assume-role-policy.json`: shared trust policy for ECS task roles
- `iam-task-execution-secrets-policy.json`: execution-role inline policy template for reading push secrets
- `task-definition-api.json`: FastAPI HTTP service task definition template
- `task-definition-sync-worker.json`: long-running scoreboard sync worker task definition template
- `render_task_definitions.py`: validates environment variables and renders deployable JSON files

Replace placeholders before `aws ecs register-task-definition`:

- `<AWS_ACCOUNT_ID>`
- `<AWS_REGION>`
- `<ECR_REPOSITORY_URI>`
- `<ECS_TASK_EXECUTION_ROLE_ARN>`
- `<ECS_TASK_ROLE_ARN>`
- `<EFS_FILE_SYSTEM_ID>`
- `<FIREBASE_PROJECT_ID>`
- `<APNS_KEY_ID>`
- `<APNS_TEAM_ID>`
- `<SECRET_ARN_FIREBASE_SERVICE_ACCOUNT_JSON>`
- `<SECRET_ARN_APNS_AUTH_KEY_P8>`
- `<SECRET_ARN_PUSH_SYNC_SECRET>`

Use `deploy.env.example` as the checklist for values that must exist before the
task definitions can be registered. Copy it to a local untracked env file and
fill in the real AWS / Firebase / Apple values.

## Create IAM Roles

Create the ECS task execution role and application task role before registering
the task definitions. The execution role is used by ECS to pull the image, write
logs, and inject Secrets Manager values. The application task role is currently
kept empty because the container does not call AWS APIs at runtime.

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

Use the returned role ARNs as `ECS_TASK_EXECUTION_ROLE_ARN` and
`ECS_TASK_ROLE_ARN` for the renderer. If the three Secrets Manager values use a
customer-managed KMS key, also grant the execution role `kms:Decrypt` on that
key.

The CloudWatch log group is referenced by the task definitions, so create it
before service launch:

```bash
aws logs create-log-group \
  --region <AWS_REGION> \
  --log-group-name /ecs/kbo-fans-backend
```

## Render Deployment JSON

Render and validate both task definitions without editing the templates
directly. This also renders the execution-role secret-read policy:

```bash
source /path/to/kbo-fans-aws.env
source outputs/aws/ecs-fargate/secrets.env

./scripts/aws-push-task-definitions.sh
./scripts/aws-push-deploy-check.sh --skip-aws
```

Rendered files are written under `outputs/aws/ecs-fargate/` and are ignored by
git.

Attach the rendered push secret policy to the task execution role:

```bash
aws iam put-role-policy \
  --role-name kbo-fans-ecs-task-execution \
  --policy-name kbo-fans-read-push-secrets \
  --policy-document file://outputs/aws/ecs-fargate/iam-task-execution-secrets-policy.rendered.json
```

After the role and AWS resources exist, run the full AWS-side preflight:

```bash
./scripts/aws-push-deploy-check.sh
```

## Build And Push Image

```bash
aws ecr create-repository --repository-name kbo-fans-backend

aws ecr get-login-password --region <AWS_REGION> \
  | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com

docker build -t kbo-fans-backend ./backend
docker tag kbo-fans-backend:latest <ECR_REPOSITORY_URI>:latest
docker push <ECR_REPOSITORY_URI>:latest
```

## Register Task Definitions

```bash
aws ecs register-task-definition \
  --cli-input-json file://outputs/aws/ecs-fargate/task-definition-api.rendered.json

aws ecs register-task-definition \
  --cli-input-json file://outputs/aws/ecs-fargate/task-definition-sync-worker.rendered.json
```

## Create Services

Create an ECS cluster, VPC subnets, security groups, ALB, target group, ACM
certificate, and EFS access point first. Then create two ECS services:

```bash
aws ecs create-service \
  --cluster kbo-fans \
  --service-name kbo-fans-api \
  --task-definition kbo-fans-backend-api \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<SUBNET_ID>],securityGroups=[<SECURITY_GROUP_ID>],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=<TARGET_GROUP_ARN>,containerName=api,containerPort=8000"

aws ecs create-service \
  --cluster kbo-fans \
  --service-name kbo-fans-sync-worker \
  --task-definition kbo-fans-backend-sync-worker \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<SUBNET_ID>],securityGroups=[<SECURITY_GROUP_ID>],assignPublicIp=ENABLED}"
```

The sync worker does not need a load balancer. It only needs outbound network
access to KBO, Firebase, and Apple APNs, plus EFS access to the same registry
path as the API service.

## Verify

After DNS and HTTPS are ready:

```bash
PUSH_SYNC_SECRET=<secret> ./scripts/push-readiness-check.sh https://api.kbofans.com/api
```

Expected:

```text
push_config=status=ok readyForIphoneOnlyDemo=true
Push readiness check passed.
```

Then run a real iPhone check:

1. Install the TestFlight build.
2. Open a live game detail.
3. Tap `경기 따라가기`.
4. Confirm `/api/push/live-activity/register` stores the ActivityKit token.
5. Close the app.
6. Confirm `GET /api/push/config-status` shows a recent `scheduler.lastSyncAt`.
7. Confirm Dynamic Island / Lock Screen `updatedAt` changes on the worker interval.

## EventBridge Alternative

Instead of the long-running sync worker service, you can run one-off ECS tasks
every minute with EventBridge Scheduler using the command:

```bash
python -m kbo_fans_backend.scheduler.live_activity_sync
```

EventBridge Scheduler has a practical 1-minute cadence, so the long-running
worker is better when you want a 30-second sports demo interval.
