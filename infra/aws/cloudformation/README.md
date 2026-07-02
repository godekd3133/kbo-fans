# AWS CloudFormation Push Demo Stack

This path provisions the always-on backend needed for app-closed push and iOS
Live Activity / Dynamic Island updates.

## What It Creates

- ECS Fargate cluster
- API service behind an Application Load Balancer
- long-running scoreboard sync worker service
- EFS file system and mount targets for push / ActivityKit token registry
- ECS task execution role and task role
- CloudWatch log group
- security groups for ALB, ECS tasks, and EFS

It does not create Firebase, Apple APNs keys, ECR images, Route53 records, or ACM
certificates. Those remain external prerequisites for the real HTTPS/release path.

It can also create the separate GitHub Actions OIDC role used by the repository
workflow to deploy this stack without long-lived AWS access keys.

Before leaving this paid always-on path running, deploy the USD 10 actual /
forecast cost guard:

```bash
./scripts/aws-cost-guard-deploy.sh --apply --invoke-now
```

For fixed-cost cleanup, including deleting this demo stack during a strict cost
emergency, follow `docs/AWS_COST_GUARD_RUNBOOK.md`.

## Prerequisites

1. Firebase Admin service account JSON
2. Apple APNs Auth Key `.p8`
3. ACM certificate in the target AWS region when `ENABLE_HTTPS=true`
4. ECR repository with the backend image pushed as `:latest`, or set `CONTAINER_IMAGE_URI` to an exact image tag
5. VPC with two public subnets in different Availability Zones

If GitHub Actions will run the deployment, create the OIDC role first:

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

The role trusts only the GitHub OIDC subject
`repo:godekd3133/kbo-fans:ref:refs/heads/main`. After deploy,
`AWS_ROLE_TO_ASSUME` is written back to the env file and can be uploaded with
`./scripts/github-push-secrets.sh --env-file /tmp/kbo-fans-aws.env --apply`.

Create the push secrets first:

```bash
AWS_REGION=<region> \
FIREBASE_SERVICE_ACCOUNT_FILE=/path/firebase-service-account.json \
APNS_AUTH_KEY_FILE=/path/AuthKey_<KEY_ID>.p8 \
./scripts/aws-push-secrets.sh
```

Build and push the backend image to ECR:

```bash
AWS_REGION=<region> \
ECR_REPOSITORY_URI=<account>.dkr.ecr.<region>.amazonaws.com/kbo-fans-backend \
./scripts/aws-push-image.sh --tag latest
```

Copy the env checklist and fill in real values:

```bash
cp infra/aws/ecs-fargate/deploy.env.example /tmp/kbo-fans-aws.env
$EDITOR /tmp/kbo-fans-aws.env
./scripts/push-live-preflight.sh --env-file /tmp/kbo-fans-aws.env --aws
source /tmp/kbo-fans-aws.env
source outputs/aws/ecs-fargate/secrets.env
source outputs/aws/ecr/image.env
```

Dry-run local validation:

```bash
./scripts/aws-push-demo-deploy.sh --dry-run
```

Deploy the full demo pipeline:

```bash
./scripts/aws-push-demo-deploy.sh
source outputs/aws/cloudformation/stack.env
```

The full pipeline runs secret upload, backend image push, CloudFormation deploy,
stack output export, and push readiness. Set `ENABLE_HTTPS=false` only for a
temporary HTTP-only AWS smoke deploy before a domain and ACM certificate are
ready. To run stages manually, use:

```bash
./scripts/aws-push-image.sh --tag latest
./scripts/aws-push-cloudformation.sh
./scripts/aws-push-stack-outputs.sh
```

After deployment, use the stack output `ApiBaseUrl` as release `API_BASE_URL`
only when it is HTTPS and certificate-valid. `aws-push-cloudformation.sh` writes
that value to `outputs/aws/cloudformation/stack.env` as `RELEASE_API_BASE_URL`
and `API_BASE_URL`. In HTTP-only smoke mode, `ApiBaseUrl` is
`http://<alb-dns>/api` and should be used only for backend reachability checks.
If using a custom domain such as `api.kbofans.com`, create a Route53 alias/CNAME
to the stack output `LoadBalancerDnsName`, set `API_DOMAIN_NAME=api.kbofans.com`,
and use `https://api.kbofans.com/api`.

Verify:

```bash
PUSH_SYNC_SECRET=<secret> ./scripts/push-readiness-check.sh <ApiBaseUrl>
```

Then run the real iPhone flow:

1. Install the TestFlight build.
2. Open a live game detail.
3. Tap `경기 따라가기`.
4. Close the app.
5. Confirm `GET /api/push/config-status` shows a recent `scheduler.lastSyncAt`.
6. Confirm Dynamic Island / Lock Screen `updatedAt` changes on the worker interval.
