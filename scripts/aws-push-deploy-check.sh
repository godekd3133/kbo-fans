#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_AWS=false

usage() {
  cat <<'EOF'
Usage:
  source /path/to/kbo-fans-aws.env
  source outputs/aws/ecs-fargate/secrets.env
  ./scripts/aws-push-deploy-check.sh

Options:
  --skip-aws   Validate local env and rendered JSON only. Do not call AWS APIs.

Checks:
  - Required env vars for Firebase/APNs/ECR/EFS/ECS task definitions.
  - Renderer validate-only path.
  - Rendered JSON files, if present.
  - AWS credentials and resource reachability, unless --skip-aws is set.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-aws)
      SKIP_AWS=true
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

json_check() {
  local file="$1"
  python3 -m json.tool "$file" >/dev/null
  if grep -Eq '<[A-Z0-9_]+>' "$file"; then
    echo "Unresolved placeholder found in $file" >&2
    exit 2
  fi
}

aws_check() {
  local label="$1"
  shift

  if "$@" >/dev/null; then
    echo "aws_check=$label status=ok"
    return
  fi

  echo "aws_check=$label status=fail" >&2
  echo "Command failed: $*" >&2
  exit 1
}

role_name_from_arn() {
  local arn="$1"
  echo "${arn##*/}"
}

repo_name_from_uri() {
  local uri="$1"
  echo "${uri#*/}"
}

require_cmd python3

require_env \
  AWS_REGION \
  ECR_REPOSITORY_URI \
  ECS_TASK_EXECUTION_ROLE_ARN \
  ECS_TASK_ROLE_ARN \
  EFS_FILE_SYSTEM_ID \
  FIREBASE_PROJECT_ID \
  APNS_KEY_ID \
  APNS_TEAM_ID \
  SECRET_ARN_FIREBASE_SERVICE_ACCOUNT_JSON \
  SECRET_ARN_APNS_AUTH_KEY_P8 \
  SECRET_ARN_PUSH_SYNC_SECRET \
  SECRET_ARN_KBO_RELAY_USER_ID \
  SECRET_ARN_KBO_RELAY_PASSWORD

"$ROOT_DIR/scripts/aws-push-task-definitions.sh" --validate-only

rendered_dir="$ROOT_DIR/outputs/aws/ecs-fargate"
if [[ -d "$rendered_dir" ]]; then
  for file in \
    "$rendered_dir/iam-task-execution-secrets-policy.rendered.json" \
    "$rendered_dir/task-definition-api.rendered.json" \
    "$rendered_dir/task-definition-sync-worker.rendered.json"; do
    if [[ -f "$file" ]]; then
      json_check "$file"
    fi
  done
fi

if [[ "$SKIP_AWS" == "true" ]]; then
  echo "aws_push_deploy_check=status=ok mode=skip-aws"
  exit 0
fi

require_cmd aws

aws_check sts \
  aws sts get-caller-identity \
  --region "$AWS_REGION"

aws_check secret_firebase \
  aws secretsmanager describe-secret \
  --region "$AWS_REGION" \
  --secret-id "$SECRET_ARN_FIREBASE_SERVICE_ACCOUNT_JSON"

aws_check secret_apns \
  aws secretsmanager describe-secret \
  --region "$AWS_REGION" \
  --secret-id "$SECRET_ARN_APNS_AUTH_KEY_P8"

aws_check secret_sync \
  aws secretsmanager describe-secret \
  --region "$AWS_REGION" \
  --secret-id "$SECRET_ARN_PUSH_SYNC_SECRET"

aws_check secret_kbo_relay_user \
  aws secretsmanager describe-secret \
  --region "$AWS_REGION" \
  --secret-id "$SECRET_ARN_KBO_RELAY_USER_ID"

aws_check secret_kbo_relay_password \
  aws secretsmanager describe-secret \
  --region "$AWS_REGION" \
  --secret-id "$SECRET_ARN_KBO_RELAY_PASSWORD"

aws_check execution_role \
  aws iam get-role \
  --role-name "$(role_name_from_arn "$ECS_TASK_EXECUTION_ROLE_ARN")"

aws_check task_role \
  aws iam get-role \
  --role-name "$(role_name_from_arn "$ECS_TASK_ROLE_ARN")"

aws_check ecr_repository \
  aws ecr describe-repositories \
  --region "$AWS_REGION" \
  --repository-names "$(repo_name_from_uri "$ECR_REPOSITORY_URI")"

aws_check efs_file_system \
  aws efs describe-file-systems \
  --region "$AWS_REGION" \
  --file-system-id "$EFS_FILE_SYSTEM_ID"

if ! log_group_count="$(aws logs describe-log-groups \
  --region "$AWS_REGION" \
  --log-group-name-prefix /ecs/kbo-fans-backend \
  --query "length(logGroups[?logGroupName=='/ecs/kbo-fans-backend'])" \
  --output text)"; then
  echo "aws_check=log_group status=fail" >&2
  echo "Command failed: aws logs describe-log-groups" >&2
  exit 1
fi
if [[ "$log_group_count" != "1" ]]; then
  echo "aws_check=log_group status=fail" >&2
  echo "Missing CloudWatch log group: /ecs/kbo-fans-backend" >&2
  exit 1
fi
echo "aws_check=log_group status=ok"

echo "aws_push_deploy_check=status=ok mode=aws"
