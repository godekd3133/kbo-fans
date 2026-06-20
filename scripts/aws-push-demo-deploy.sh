#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=false
SKIP_SECRETS=false
SKIP_IMAGE=false
SKIP_STACK=false
SKIP_READINESS=false
IMAGE_TAG="${KBO_BACKEND_IMAGE_TAG:-latest}"
GENERATED_PUSH_SYNC_SECRET=false

usage() {
  cat <<'EOF'
Usage:
  source /path/to/kbo-fans-aws.env
  ./scripts/aws-push-demo-deploy.sh

Options:
  --dry-run         Validate the full deployment flow without AWS/Docker calls.
  --tag <tag>       Backend image tag. Default: KBO_BACKEND_IMAGE_TAG or latest.
  --skip-secrets    Do not create/update Secrets Manager values.
  --skip-image      Do not build/push the backend image.
  --skip-stack      Do not deploy the CloudFormation stack.
  --skip-readiness  Do not run push readiness after deploy.

Pipeline:
  1. Firebase/APNs/sync secret upload.
  2. Backend image build/tag/push to ECR.
  3. CloudFormation deploy for ALB/ECS/EFS/IAM/logs.
  4. Stack output export to RELEASE_API_BASE_URL / API_BASE_URL.
  5. Push readiness check against the deployed API.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --tag)
      if [[ -z "${2:-}" ]]; then
        echo "--tag requires a value." >&2
        exit 2
      fi
      IMAGE_TAG="$2"
      shift 2
      ;;
    --skip-secrets)
      SKIP_SECRETS=true
      shift
      ;;
    --skip-image)
      SKIP_IMAGE=true
      shift
      ;;
    --skip-stack)
      SKIP_STACK=true
      shift
      ;;
    --skip-readiness)
      SKIP_READINESS=true
      shift
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

normalize_enable_https() {
  local value="${ENABLE_HTTPS:-true}"
  case "$value" in
    true | false)
      echo "$value"
      ;;
    *)
      echo "ENABLE_HTTPS must be true or false." >&2
      exit 2
      ;;
  esac
}

ensure_push_sync_secret() {
  if [[ -n "${PUSH_SYNC_SECRET:-}" ]]; then
    return
  fi

  if command -v openssl >/dev/null 2>&1; then
    PUSH_SYNC_SECRET="$(openssl rand -hex 32)"
  else
    PUSH_SYNC_SECRET="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
)"
  fi
  export PUSH_SYNC_SECRET
  GENERATED_PUSH_SYNC_SECRET=true
}

source_if_exists() {
  local path="$1"
  if [[ -f "$path" ]]; then
    # shellcheck disable=SC1090
    source "$path"
  fi
}

mock_stack_outputs_json() {
  local path="$1"
  cat > "$path" <<'JSON'
{
  "Stacks": [
    {
      "StackName": "kbo-fans-push-demo",
      "StackStatus": "CREATE_COMPLETE",
      "Outputs": [
        {
          "OutputKey": "ApiBaseUrl",
          "OutputValue": "https://kbo-fans-api.example.elb.amazonaws.com/api"
        },
        {
          "OutputKey": "LoadBalancerDnsName",
          "OutputValue": "kbo-fans-api.example.elb.amazonaws.com"
        },
        {
          "OutputKey": "ClusterName",
          "OutputValue": "kbo-fans"
        },
        {
          "OutputKey": "ApiServiceName",
          "OutputValue": "kbo-fans-api"
        },
        {
          "OutputKey": "SyncWorkerServiceName",
          "OutputValue": "kbo-fans-sync-worker"
        },
        {
          "OutputKey": "PushRegistryFileSystemId",
          "OutputValue": "fs-1234567890abcdef0"
        },
        {
          "OutputKey": "LogGroupName",
          "OutputValue": "/ecs/kbo-fans-backend"
        }
      ]
    }
  ]
}
JSON
}

require_env AWS_REGION ECR_REPOSITORY_URI
enable_https="$(normalize_enable_https)"
ensure_push_sync_secret

if [[ "$SKIP_SECRETS" != "true" ]]; then
  if [[ "$DRY_RUN" == "true" ]]; then
    "$ROOT_DIR/scripts/aws-push-secrets.sh" --dry-run
  else
    "$ROOT_DIR/scripts/aws-push-secrets.sh"
  fi
fi
source_if_exists "$ROOT_DIR/outputs/aws/ecs-fargate/secrets.env"

if [[ "$SKIP_IMAGE" != "true" ]]; then
  if [[ "$DRY_RUN" == "true" ]]; then
    "$ROOT_DIR/scripts/aws-push-image.sh" --dry-run --tag "$IMAGE_TAG"
  else
    "$ROOT_DIR/scripts/aws-push-image.sh" --tag "$IMAGE_TAG"
  fi
fi
source_if_exists "$ROOT_DIR/outputs/aws/ecr/image.env"

require_env \
  VPC_ID \
  PUBLIC_SUBNET_A_ID \
  PUBLIC_SUBNET_B_ID \
  FIREBASE_PROJECT_ID \
  APNS_KEY_ID \
  APNS_TEAM_ID \
  SECRET_ARN_FIREBASE_SERVICE_ACCOUNT_JSON \
  SECRET_ARN_APNS_AUTH_KEY_P8 \
  SECRET_ARN_PUSH_SYNC_SECRET \
  SECRET_ARN_KBO_RELAY_USER_ID \
  SECRET_ARN_KBO_RELAY_PASSWORD

if [[ "$enable_https" == "true" ]]; then
  require_env ACM_CERTIFICATE_ARN
fi

if [[ "$SKIP_STACK" != "true" ]]; then
  if [[ "$DRY_RUN" == "true" ]]; then
    "$ROOT_DIR/scripts/aws-push-cloudformation.sh" --dry-run
  else
    "$ROOT_DIR/scripts/aws-push-cloudformation.sh"
  fi
fi

if [[ "$DRY_RUN" == "true" ]]; then
  mock_json="$(mktemp)"
  mock_stack_outputs_json "$mock_json"
  "$ROOT_DIR/scripts/aws-push-stack-outputs.sh" \
    --input-json "$mock_json" \
    --no-env-file >/dev/null
  rm -f "$mock_json"
else
  "$ROOT_DIR/scripts/aws-push-stack-outputs.sh"
  source_if_exists "$ROOT_DIR/outputs/aws/cloudformation/stack.env"
fi

if [[ "$SKIP_READINESS" != "true" ]]; then
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "push_readiness=skipped mode=dry-run"
  else
    require_env RELEASE_API_BASE_URL PUSH_SYNC_SECRET
    if [[ "$enable_https" == "false" && -z "${ALLOW_INSECURE_PUSH_READINESS:-}" ]]; then
      ALLOW_INSECURE_PUSH_READINESS=true \
        "$ROOT_DIR/scripts/push-readiness-check.sh" "$RELEASE_API_BASE_URL"
    else
      "$ROOT_DIR/scripts/push-readiness-check.sh" "$RELEASE_API_BASE_URL"
    fi
  fi
fi

if [[ "$GENERATED_PUSH_SYNC_SECRET" == "true" && "$DRY_RUN" != "true" ]]; then
  cat >&2 <<'EOF'
PUSH_SYNC_SECRET was generated for this deploy run and was not printed.
For later manual readiness checks, retrieve /kbo-fans/push-sync-secret from AWS Secrets Manager.
EOF
fi

echo "aws_push_demo_deploy=status=ok dry_run=$DRY_RUN"
