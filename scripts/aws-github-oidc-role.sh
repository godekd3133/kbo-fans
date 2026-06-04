#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_FILE="$ROOT_DIR/infra/aws/cloudformation/github-actions-oidc-role.json"
OUTPUT_DIR="${AWS_GITHUB_OIDC_OUTPUT_DIR:-$ROOT_DIR/outputs/aws/github-actions-oidc}"
ENV_FILE=""
REPO="${GITHUB_REPOSITORY:-}"
BRANCH_NAME="${GITHUB_BRANCH_NAME:-main}"
ROLE_NAME="${AWS_GITHUB_OIDC_ROLE_NAME:-kbo-fans-github-actions-push-demo}"
STACK_NAME="${AWS_GITHUB_OIDC_STACK_NAME:-kbo-fans-github-actions-oidc}"
DRY_RUN=false
UPDATE_ENV_FILE=false

usage() {
  cat <<'EOF'
Usage:
  AWS_REGION=ap-northeast-2 \
  ./scripts/aws-github-oidc-role.sh --repo godekd3133/kbo-fans

Options:
  --env-file <path>       Source local push demo env values first.
  --repo <owner/repo>     GitHub repository allowed to assume the role.
  --branch <name>         GitHub branch allowed to assume the role. Default: main
  --role-name <name>      IAM role name. Default: kbo-fans-github-actions-push-demo
  --stack-name <name>     CloudFormation stack name for the OIDC role.
  --update-env-file       Replace/add AWS_ROLE_TO_ASSUME in --env-file after deploy.
  --dry-run               Validate inputs and print the planned AWS operations.

Purpose:
  Create the AWS IAM role used by GitHub Actions Push Demo Deploy through OIDC.
  This avoids storing long-lived AWS access keys in GitHub secrets.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      if [[ -z "${2:-}" ]]; then
        echo "--env-file requires a path." >&2
        exit 2
      fi
      ENV_FILE="$2"
      shift 2
      ;;
    --repo)
      if [[ -z "${2:-}" ]]; then
        echo "--repo requires owner/repo." >&2
        exit 2
      fi
      REPO="$2"
      shift 2
      ;;
    --branch)
      if [[ -z "${2:-}" ]]; then
        echo "--branch requires a branch name." >&2
        exit 2
      fi
      BRANCH_NAME="$2"
      shift 2
      ;;
    --role-name)
      if [[ -z "${2:-}" ]]; then
        echo "--role-name requires a role name." >&2
        exit 2
      fi
      ROLE_NAME="$2"
      shift 2
      ;;
    --stack-name)
      if [[ -z "${2:-}" ]]; then
        echo "--stack-name requires a stack name." >&2
        exit 2
      fi
      STACK_NAME="$2"
      shift 2
      ;;
    --update-env-file)
      UPDATE_ENV_FILE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
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

if [[ -n "$ENV_FILE" ]]; then
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "Env file not found: $ENV_FILE" >&2
    exit 2
  fi
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

if [[ "$UPDATE_ENV_FILE" == "true" && -z "$ENV_FILE" ]]; then
  echo "--update-env-file requires --env-file." >&2
  exit 2
fi

resolve_repo() {
  if [[ -n "$REPO" ]]; then
    echo "$REPO"
    return
  fi

  if command -v gh >/dev/null 2>&1; then
    gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true
    return
  fi

  echo ""
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

update_env_file_role() {
  local path="$1"
  local role_arn="$2"
  local quoted
  local tmp

  quoted="$(printf '%q' "$role_arn")"
  tmp="$(mktemp "${path}.tmp.XXXXXX")"
  if [[ -f "$path" ]]; then
    awk -v line="export AWS_ROLE_TO_ASSUME=$quoted" '
      BEGIN { replaced = 0 }
      /^export AWS_ROLE_TO_ASSUME=/ {
        print line
        replaced = 1
        next
      }
      { print }
      END {
        if (replaced == 0) {
          print line
        }
      }
    ' "$path" >"$tmp"
  else
    printf 'export AWS_ROLE_TO_ASSUME=%s\n' "$quoted" >"$tmp"
  fi
  mv "$tmp" "$path"
  chmod 600 "$path"
}

repo="$(resolve_repo)"
if [[ -z "$repo" || "$repo" != */* ]]; then
  echo "GitHub repo could not be resolved. Pass --repo owner/repo." >&2
  exit 2
fi

github_owner="${repo%%/*}"
github_repo="${repo#*/}"
aws_region="${AWS_REGION:-ap-northeast-2}"
stack_name_prefix="${KBO_STACK_NAME_PREFIX:-kbo-fans}"
aws_secret_prefix="${AWS_PUSH_SECRET_PREFIX:-/kbo-fans}"

require_cmd python3
python3 -m json.tool "$TEMPLATE_FILE" >/dev/null

if [[ "$DRY_RUN" == "true" ]]; then
  echo "aws_github_oidc_role=status=ok mode=dry-run"
  echo "repo=$repo"
  echo "branch=$BRANCH_NAME"
  echo "stack=$STACK_NAME"
  echo "role_name=$ROLE_NAME"
  echo "aws_region=$aws_region"
  echo "would_create_or_reuse_oidc_provider=https://token.actions.githubusercontent.com audience=sts.amazonaws.com"
  echo "would_deploy_template=$TEMPLATE_FILE"
  if [[ "$UPDATE_ENV_FILE" == "true" ]]; then
    echo "would_update_env_file=$ENV_FILE"
  fi
  exit 0
fi

require_cmd aws

caller_account="$(aws sts get-caller-identity --query Account --output text)"
caller_arn="$(aws sts get-caller-identity --query Arn --output text)"
partition="$(printf '%s' "$caller_arn" | cut -d: -f2)"
provider_arn="arn:${partition}:iam::${caller_account}:oidc-provider/token.actions.githubusercontent.com"
existing_provider_arn=""

if provider_clients="$(aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "$provider_arn" \
  --query ClientIDList \
  --output text 2>/dev/null)"; then
  existing_provider_arn="$provider_arn"
  echo "oidc_provider=reuse arn=$provider_arn"
  if grep -qw "sts.amazonaws.com" <<<"$provider_clients"; then
    echo "oidc_provider_audience=exists value=sts.amazonaws.com"
  else
    aws iam add-client-id-to-open-id-connect-provider \
      --open-id-connect-provider-arn "$provider_arn" \
      --client-id sts.amazonaws.com
    echo "oidc_provider_audience=added value=sts.amazonaws.com"
  fi
else
  echo "oidc_provider=create_in_stack url=https://token.actions.githubusercontent.com"
fi

aws cloudformation deploy \
  --region "$aws_region" \
  --stack-name "$STACK_NAME" \
  --template-file "$TEMPLATE_FILE" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    GitHubOwner="$github_owner" \
    GitHubRepo="$github_repo" \
    GitHubBranchName="$BRANCH_NAME" \
    RoleName="$ROLE_NAME" \
    StackNamePrefix="$stack_name_prefix" \
    AwsSecretPrefix="$aws_secret_prefix" \
    ExistingGitHubOidcProviderArn="$existing_provider_arn"

role_arn="$(
  aws cloudformation describe-stacks \
    --region "$aws_region" \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='RoleArn'].OutputValue | [0]" \
    --output text
)"
trusted_subject="$(
  aws cloudformation describe-stacks \
    --region "$aws_region" \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='TrustedSubject'].OutputValue | [0]" \
    --output text
)"

mkdir -p "$OUTPUT_DIR"
role_env="$OUTPUT_DIR/role.env"
cat >"$role_env" <<EOF
export AWS_ROLE_TO_ASSUME=$role_arn
export AWS_GITHUB_OIDC_STACK_NAME=$STACK_NAME
export AWS_GITHUB_OIDC_TRUSTED_SUBJECT=$trusted_subject
EOF
chmod 600 "$role_env"

if [[ "$UPDATE_ENV_FILE" == "true" ]]; then
  if [[ -z "$ENV_FILE" ]]; then
    echo "--update-env-file requires --env-file." >&2
    exit 2
  fi
  update_env_file_role "$ENV_FILE" "$role_arn"
  echo "updated_env_file=$ENV_FILE"
fi

echo "aws_github_oidc_role=status=ok mode=deploy"
echo "export AWS_ROLE_TO_ASSUME=$role_arn"
echo "$role_env"
