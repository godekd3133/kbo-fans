#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_FILE="$ROOT_DIR/infra/aws/cloudformation/push-demo-stack.json"
STACK_NAME="${KBO_PUSH_STACK_NAME:-kbo-fans-push-demo}"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage:
  source /path/to/kbo-fans-aws.env
  source outputs/aws/ecs-fargate/secrets.env
  ./scripts/aws-push-cloudformation.sh

Options:
  --dry-run      Validate required env and local CloudFormation JSON only.
  --stack-name   Override CloudFormation stack name.

Required env:
  AWS_REGION
  VPC_ID
  PUBLIC_SUBNET_A_ID
  PUBLIC_SUBNET_B_ID
  ECR_REPOSITORY_URI
  FIREBASE_PROJECT_ID
  APNS_KEY_ID
  APNS_TEAM_ID
  SECRET_ARN_FIREBASE_SERVICE_ACCOUNT_JSON
  SECRET_ARN_APNS_AUTH_KEY_P8
  SECRET_ARN_PUSH_SYNC_SECRET

Optional env:
  KBO_PUSH_STACK_NAME
  KBO_STACK_NAME_PREFIX
  ENABLE_HTTPS        Default true. Set false for temporary HTTP-only AWS smoke deploys.
  API_DOMAIN_NAME     Optional custom API domain that matches ACM_CERTIFICATE_ARN.
  ACM_CERTIFICATE_ARN Required when ENABLE_HTTPS=true.
  CONTAINER_IMAGE_URI
  API_DESIRED_COUNT
  SYNC_WORKER_DESIRED_COUNT
  PUSH_SYNC_INTERVAL_SECONDS
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --stack-name)
      if [[ -z "${2:-}" ]]; then
        echo "--stack-name requires a value." >&2
        exit 2
      fi
      STACK_NAME="$2"
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

require_env() {
  local missing=()
  local name
  for name in "$@"; do
    if [[ -z "${!name:-}" ]]; then
      missing+=("$name")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing required environment variables:" >&2
    for name in "${missing[@]}"; do
      echo "  - $name" >&2
    done
    exit 2
  fi
}

require_cmd python3
require_env \
  AWS_REGION \
  VPC_ID \
  PUBLIC_SUBNET_A_ID \
  PUBLIC_SUBNET_B_ID \
  ECR_REPOSITORY_URI \
  FIREBASE_PROJECT_ID \
  APNS_KEY_ID \
  APNS_TEAM_ID \
  SECRET_ARN_FIREBASE_SERVICE_ACCOUNT_JSON \
  SECRET_ARN_APNS_AUTH_KEY_P8 \
  SECRET_ARN_PUSH_SYNC_SECRET

enable_https="${ENABLE_HTTPS:-true}"
case "$enable_https" in
  true | false)
    ;;
  *)
    echo "ENABLE_HTTPS must be true or false." >&2
    exit 2
    ;;
esac

if [[ "$enable_https" == "true" ]]; then
  require_env ACM_CERTIFICATE_ARN
fi

container_image_uri="${CONTAINER_IMAGE_URI:-$ECR_REPOSITORY_URI:latest}"

python3 -m json.tool "$TEMPLATE_FILE" >/dev/null

if grep -Eq '<[A-Z0-9_]+>' "$TEMPLATE_FILE"; then
  echo "Unresolved placeholder found in $TEMPLATE_FILE" >&2
  exit 2
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "aws_push_cloudformation=status=ok mode=dry-run stack=$STACK_NAME"
  exit 0
fi

require_cmd aws

aws cloudformation deploy \
  --region "$AWS_REGION" \
  --stack-name "$STACK_NAME" \
  --template-file "$TEMPLATE_FILE" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    StackNamePrefix="${KBO_STACK_NAME_PREFIX:-kbo-fans}" \
    VpcId="$VPC_ID" \
    PublicSubnetAId="$PUBLIC_SUBNET_A_ID" \
    PublicSubnetBId="$PUBLIC_SUBNET_B_ID" \
    EnableHttps="$enable_https" \
    ApiDomainName="${API_DOMAIN_NAME:-}" \
    AcmCertificateArn="${ACM_CERTIFICATE_ARN:-}" \
    ContainerImageUri="$container_image_uri" \
    FirebaseProjectId="$FIREBASE_PROJECT_ID" \
    ApnsKeyId="$APNS_KEY_ID" \
    ApnsTeamId="$APNS_TEAM_ID" \
    FirebaseServiceAccountSecretArn="$SECRET_ARN_FIREBASE_SERVICE_ACCOUNT_JSON" \
    ApnsAuthKeySecretArn="$SECRET_ARN_APNS_AUTH_KEY_P8" \
    PushSyncSecretArn="$SECRET_ARN_PUSH_SYNC_SECRET" \
    ApiDesiredCount="${API_DESIRED_COUNT:-1}" \
    SyncWorkerDesiredCount="${SYNC_WORKER_DESIRED_COUNT:-1}" \
    PushSyncIntervalSeconds="${PUSH_SYNC_INTERVAL_SECONDS:-60}"

"$ROOT_DIR/scripts/aws-push-stack-outputs.sh" --stack-name "$STACK_NAME"

echo "aws_push_cloudformation=status=ok mode=deploy stack=$STACK_NAME"
