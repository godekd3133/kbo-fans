# AWS Cost Guard Runbook

## Goal

Stop KBO Fans AWS runtime services when either month-to-date actual cost or
forecasted monthly cost reaches USD 10.

This is a cost guard, not a real-time hard billing cap. AWS Billing, Budgets,
and Cost Explorer data can lag behind actual resource usage. The guard reacts as
soon as AWS exposes the over-threshold actual or forecast value to Budget SNS or
the scheduled Cost Explorer check.

## What It Deploys

`infra/aws/cost-guard/cost-guard-stack.yaml` creates:

- an AWS Budget at USD 10/month
- actual-cost and forecast-cost notifications at 100% of that budget
- an SNS topic for those budget notifications
- a Lambda cost guard
- an EventBridge scheduled rule that re-checks Cost Explorer every 15 minutes

The Lambda stops supported runtime resources in the configured target regions:

- ECS services: desired count `0`, then running tasks stopped
- Auto Scaling groups: min/max/desired `0`
- EC2 instances: stopped
- RDS instances: stopped when supported
- App Runner services: paused
- Lightsail instances: stopped by default

If `--destructive` is enabled, it may delete configured CloudFormation stacks.
Matching Lightsail instances are deleted only when `--delete-lightsail-instances`
is also set. Use these options for a hard cost emergency only.

## Important Limits

- AWS has no universal "stop every service" API.
- AWS Budget native actions are limited and do not cover the full KBO Fans
  runtime shape, so this repo uses Budget SNS plus Lambda.
- Cost Explorer data refresh is not real time, so costs can exceed USD 10 before
  AWS exposes the value.
- Forecast alerts require enough historical usage data. If AWS cannot generate a
  forecast yet, the actual-cost path still applies.
- Stopping a Lightsail instance does not stop Lightsail plan charges. Deleting it
  is required to stop that fixed charge.
- ALB/EFS/VPC-style fixed costs from the ECS/Fargate demo path usually require
  deleting the old CloudFormation stack, not just setting ECS desired count to
  zero.

## Safe Deployment

Dry-run first:

```bash
./scripts/codex-run.sh aws-cost-guard-deploy
```

Deploy the non-destructive guard:

```bash
./scripts/codex-run.sh aws-cost-guard-deploy \
  --apply \
  --invoke-now \
  --threshold-usd 10 \
  --resource-prefix kbo-fans \
  --scope prefix \
  --target-regions ap-northeast-2,us-east-1
```

This is the default operating mode. It stops KBO Fans compute/runtime surfaces
without deleting data-bearing or stack-owned resources.

## Strict Cost Emergency

Use this when availability is less important than immediately removing fixed
runtime cost:

```bash
./scripts/codex-run.sh aws-cost-guard-deploy \
  --apply \
  --invoke-now \
  --threshold-usd 10 \
  --resource-prefix kbo-fans \
  --scope prefix \
  --target-regions ap-northeast-2,us-east-1 \
  --destructive \
  --delete-stacks kbo-fans-push-demo
```

Expected impact:

- the old ECS/Fargate demo stack can be deleted
- matching Lightsail instances are stopped, not deleted
- API, push notification, Live Activity, and Dynamic Island remote sync stop
- existing mobile builds pointing at deleted backend URLs fail until a new API
  URL is deployed and shipped

Add `--delete-lightsail-instances` only when stopping the Lightsail API is not
enough and deleting the instance is acceptable.

Do not use `--scope account` unless this AWS account is dedicated to KBO Fans.

## Manual Recheck

After deployment, manually invoke the guard again:

```bash
aws lambda invoke \
  --region us-east-1 \
  --function-name kbo-fans-cost-kill-switch-lambda \
  --cli-binary-format raw-in-base64-out \
  --payload '{"source":"manual","reason":"operator-recheck"}' \
  /tmp/kbo-fans-cost-guard.json
cat /tmp/kbo-fans-cost-guard.json
```

Check logs:

```bash
aws logs tail /aws/lambda/kbo-fans-cost-kill-switch-lambda \
  --region us-east-1 \
  --since 30m
```

## Drift Repair

If someone manually deletes the Lambda, SNS topic, IAM role, or EventBridge rule,
CloudFormation can still show the guard stack as complete while the real guard is
gone. Confirm with:

```bash
aws cloudformation detect-stack-drift \
  --region us-east-1 \
  --stack-name kbo-fans-cost-guard
```

If the stack is drifted because guard resources were deleted, recreate it:

```bash
aws cloudformation delete-stack \
  --region us-east-1 \
  --stack-name kbo-fans-cost-guard
aws cloudformation wait stack-delete-complete \
  --region us-east-1 \
  --stack-name kbo-fans-cost-guard
./scripts/aws-cost-guard-deploy.sh --apply --invoke-now
```

## Disable

Delete the guard stack only when the budget kill switch is no longer desired:

```bash
aws cloudformation delete-stack \
  --region us-east-1 \
  --stack-name kbo-fans-cost-guard
```

Deleting the guard removes the Budget/SNS/Lambda/EventBridge automation. It does
not restart stopped services.
