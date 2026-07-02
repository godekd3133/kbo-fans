#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_FILE="$ROOT_DIR/infra/aws/cost-guard/cost-guard-stack.yaml"

STACK_NAME="${KBO_COST_GUARD_STACK_NAME:-kbo-fans-cost-guard}"
REGION="${AWS_REGION:-us-east-1}"
BUDGET_NAME="${KBO_COST_GUARD_BUDGET_NAME:-kbo-fans-cost-kill-switch}"
THRESHOLD_USD="${KBO_COST_GUARD_THRESHOLD_USD:-10}"
RESOURCE_PREFIX="${KBO_COST_GUARD_RESOURCE_PREFIX:-kbo-fans}"
GUARD_SCOPE="${KBO_COST_GUARD_SCOPE:-prefix}"
TARGET_REGIONS="${KBO_COST_GUARD_TARGET_REGIONS:-ap-northeast-2,us-east-1}"
SCHEDULE_EXPRESSION="${KBO_COST_GUARD_SCHEDULE:-rate(15 minutes)}"
ENABLE_SCHEDULED_CHECK="${KBO_COST_GUARD_ENABLE_SCHEDULED_CHECK:-true}"
DESTRUCTIVE_MODE="${KBO_COST_GUARD_DESTRUCTIVE_MODE:-false}"
DELETE_LIGHTSAIL_INSTANCES="${KBO_COST_GUARD_DELETE_LIGHTSAIL_INSTANCES:-false}"
DELETE_STACKS="${KBO_COST_GUARD_DELETE_STACKS:-}"
APPLY=false
INVOKE_NOW=false

usage() {
  cat <<'EOF'
Usage:
  ./scripts/aws-cost-guard-deploy.sh [--apply] [--invoke-now]

Options:
  --apply                 Deploy/update the AWS CloudFormation stack.
  --invoke-now            Invoke the guard Lambda once after a successful deploy.
  --region <region>       CloudFormation/Lambda/Budget region. Default: AWS_REGION or us-east-1.
  --stack-name <name>     CloudFormation stack name. Default: kbo-fans-cost-guard.
  --budget-name <name>    AWS Budget name. Default: kbo-fans-cost-kill-switch.
  --threshold-usd <n>     Monthly actual/forecast threshold. Default: 10.
  --resource-prefix <p>   Resource name/tag prefix for prefix scope. Default: kbo-fans.
  --scope <prefix|account>
                          prefix stops matching KBO resources only. account stops every supported runtime resource in target regions.
  --target-regions <csv>  Regions to stop resources in. Use "all" to enumerate enabled EC2 regions.
  --schedule <expr>       EventBridge schedule. Default: rate(15 minutes).
  --disable-schedule      Disable periodic Cost Explorer checks; Budget SNS still applies.
  --destructive           Allow fixed-cost cleanup such as configured CloudFormation stack deletion.
  --delete-lightsail-instances
                          With --destructive, delete matching Lightsail instances instead of only stopping them.
  --delete-stacks <csv>   CloudFormation stack names to delete only with --destructive.

Default mode is dry-run. It prints the exact guard configuration without making AWS changes.

Strict cost cap example:
  ./scripts/aws-cost-guard-deploy.sh \
    --apply \
    --invoke-now \
    --threshold-usd 10 \
    --resource-prefix kbo-fans \
    --target-regions ap-northeast-2,us-east-1 \
    --destructive \
    --delete-stacks kbo-fans-push-demo
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=true
      shift
      ;;
    --invoke-now)
      INVOKE_NOW=true
      shift
      ;;
    --region)
      if [[ -z "${2:-}" ]]; then
        echo "--region requires a value." >&2
        exit 2
      fi
      REGION="$2"
      shift 2
      ;;
    --stack-name)
      if [[ -z "${2:-}" ]]; then
        echo "--stack-name requires a value." >&2
        exit 2
      fi
      STACK_NAME="$2"
      shift 2
      ;;
    --budget-name)
      if [[ -z "${2:-}" ]]; then
        echo "--budget-name requires a value." >&2
        exit 2
      fi
      BUDGET_NAME="$2"
      shift 2
      ;;
    --threshold-usd)
      if [[ -z "${2:-}" ]]; then
        echo "--threshold-usd requires a value." >&2
        exit 2
      fi
      THRESHOLD_USD="$2"
      shift 2
      ;;
    --resource-prefix)
      if [[ -z "${2:-}" ]]; then
        echo "--resource-prefix requires a value." >&2
        exit 2
      fi
      RESOURCE_PREFIX="$2"
      shift 2
      ;;
    --scope)
      if [[ -z "${2:-}" ]]; then
        echo "--scope requires a value." >&2
        exit 2
      fi
      GUARD_SCOPE="$2"
      shift 2
      ;;
    --target-regions)
      if [[ -z "${2:-}" ]]; then
        echo "--target-regions requires a value." >&2
        exit 2
      fi
      TARGET_REGIONS="$2"
      shift 2
      ;;
    --schedule)
      if [[ -z "${2:-}" ]]; then
        echo "--schedule requires a value." >&2
        exit 2
      fi
      SCHEDULE_EXPRESSION="$2"
      shift 2
      ;;
    --disable-schedule)
      ENABLE_SCHEDULED_CHECK=false
      shift
      ;;
    --destructive)
      DESTRUCTIVE_MODE=true
      shift
      ;;
    --delete-lightsail-instances)
      DELETE_LIGHTSAIL_INSTANCES=true
      shift
      ;;
    --delete-stacks)
      if [[ -z "${2:-}" ]]; then
        echo "--delete-stacks requires a value." >&2
        exit 2
      fi
      DELETE_STACKS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

case "$GUARD_SCOPE" in
  prefix | account)
    ;;
  *)
    echo "--scope must be prefix or account." >&2
    exit 2
    ;;
esac

case "$ENABLE_SCHEDULED_CHECK" in
  true | false)
    ;;
  *)
    echo "KBO_COST_GUARD_ENABLE_SCHEDULED_CHECK must be true or false." >&2
    exit 2
    ;;
esac

case "$DESTRUCTIVE_MODE" in
  true | false)
    ;;
  *)
    echo "KBO_COST_GUARD_DESTRUCTIVE_MODE must be true or false." >&2
    exit 2
    ;;
esac

case "$DELETE_LIGHTSAIL_INSTANCES" in
  true | false)
    ;;
  *)
    echo "KBO_COST_GUARD_DELETE_LIGHTSAIL_INSTANCES must be true or false." >&2
    exit 2
    ;;
esac

if [[ ! "$THRESHOLD_USD" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "--threshold-usd must be a positive number." >&2
  exit 2
fi

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "Missing template: $TEMPLATE_FILE" >&2
  exit 1
fi

print_config() {
  cat <<EOF
aws_cost_guard=configuration
  stack_name=$STACK_NAME
  region=$REGION
  budget_name=$BUDGET_NAME
  threshold_usd=$THRESHOLD_USD
  resource_prefix=$RESOURCE_PREFIX
  scope=$GUARD_SCOPE
  target_regions=$TARGET_REGIONS
  schedule_enabled=$ENABLE_SCHEDULED_CHECK
  schedule_expression=$SCHEDULE_EXPRESSION
  destructive_mode=$DESTRUCTIVE_MODE
  delete_lightsail_instances=$DELETE_LIGHTSAIL_INSTANCES
  delete_cloudformation_stacks=${DELETE_STACKS:-<none>}
EOF
}

print_config

if [[ "$APPLY" != "true" ]]; then
  echo "aws_cost_guard=status=ok mode=dry-run"
  exit 0
fi

require_cmd aws

aws cloudformation deploy \
  --region "$REGION" \
  --stack-name "$STACK_NAME" \
  --template-file "$TEMPLATE_FILE" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    BudgetName="$BUDGET_NAME" \
    MonthlyLimitUsd="$THRESHOLD_USD" \
    ResourcePrefix="$RESOURCE_PREFIX" \
    GuardScope="$GUARD_SCOPE" \
    TargetRegions="$TARGET_REGIONS" \
    ScheduleExpression="$SCHEDULE_EXPRESSION" \
    EnableScheduledCheck="$ENABLE_SCHEDULED_CHECK" \
    DestructiveMode="$DESTRUCTIVE_MODE" \
    DeleteLightsailInstances="$DELETE_LIGHTSAIL_INSTANCES" \
    DeleteCloudFormationStacks="$DELETE_STACKS"

echo "aws_cost_guard=status=deployed stack=$STACK_NAME region=$REGION"

if [[ "$INVOKE_NOW" != "true" ]]; then
  exit 0
fi

function_name="$(
  aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='GuardFunctionName'].OutputValue | [0]" \
    --output text
)"

if [[ -z "$function_name" || "$function_name" == "None" ]]; then
  echo "Could not resolve GuardFunctionName from stack outputs." >&2
  exit 1
fi

invoke_output="$(mktemp)"
aws lambda invoke \
  --region "$REGION" \
  --function-name "$function_name" \
  --cli-binary-format raw-in-base64-out \
  --payload '{"source":"manual","reason":"post-deploy-cost-check"}' \
  "$invoke_output" >/dev/null

echo "aws_cost_guard=invoked function=$function_name"
cat "$invoke_output"
rm -f "$invoke_output"
