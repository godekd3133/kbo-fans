# AWS Cost Guard

This stack is the KBO Fans billing kill switch.

It creates an AWS Budget at USD 10/month with both actual and forecasted
notifications, sends those notifications to SNS, and invokes a Lambda function
that stops KBO Fans runtime resources. The same Lambda also runs on an
EventBridge schedule to re-check Cost Explorer.

Deploy through the repo script:

```bash
./scripts/aws-cost-guard-deploy.sh --apply --invoke-now
```

Default scope is `kbo-fans` resource names/tags in `ap-northeast-2,us-east-1`.
Use destructive mode only when deleting fixed-cost resources is intentional:

```bash
./scripts/aws-cost-guard-deploy.sh \
  --apply \
  --invoke-now \
  --destructive \
  --delete-stacks kbo-fans-push-demo
```

See `docs/AWS_COST_GUARD_RUNBOOK.md` for limits and emergency procedure.
