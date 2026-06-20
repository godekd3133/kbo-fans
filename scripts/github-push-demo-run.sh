#!/usr/bin/env bash

set -euo pipefail

REPO=""
REF=""
DRY_RUN=true
IMAGE_TAG="${KBO_BACKEND_IMAGE_TAG:-latest}"
SKIP_READINESS=false
RESUBSCRIBE_TOPICS=false
WATCH=false
SKIP_CONFIG_CHECK=false

usage() {
  cat <<'EOF'
Usage:
  ./scripts/github-push-demo-run.sh [--dry-run true|false] [--tag latest] [--watch]

Options:
  --repo <owner/repo>       Override GitHub repository. Default: gh repo view.
  --ref <branch-or-sha>     Workflow ref. Default: current git branch.
  --dry-run <true|false>    Run workflow in dry-run mode. Default: true.
  --tag <tag>               Backend image tag. Default: KBO_BACKEND_IMAGE_TAG or latest.
  --skip-readiness          Skip deployed API readiness after stack deploy.
  --resubscribe-topics      Reconcile FCM topics from the push registry after deploy.
  --skip-config-check       Do not check GitHub secrets/variables before dispatch.
  --watch                   Wait for the triggered workflow run.

Purpose:
  Dispatch the GitHub Actions Push Demo Deploy workflow after secrets/variables
  are configured. If the workflow is not visible on GitHub yet, push the
  workflow file to the default branch first.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      if [[ -z "${2:-}" ]]; then
        echo "--repo requires owner/repo." >&2
        exit 2
      fi
      REPO="$2"
      shift 2
      ;;
    --ref)
      if [[ -z "${2:-}" ]]; then
        echo "--ref requires a branch or sha." >&2
        exit 2
      fi
      REF="$2"
      shift 2
      ;;
    --dry-run)
      if [[ "${2:-}" != "true" && "${2:-}" != "false" ]]; then
        echo "--dry-run requires true or false." >&2
        exit 2
      fi
      DRY_RUN="$2"
      shift 2
      ;;
    --tag)
      if [[ -z "${2:-}" ]]; then
        echo "--tag requires a value." >&2
        exit 2
      fi
      IMAGE_TAG="$2"
      shift 2
      ;;
    --skip-readiness)
      SKIP_READINESS=true
      shift
      ;;
    --resubscribe-topics)
      RESUBSCRIBE_TOPICS=true
      shift
      ;;
    --skip-config-check)
      SKIP_CONFIG_CHECK=true
      shift
      ;;
    --watch)
      WATCH=true
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

resolve_repo() {
  if [[ -n "$REPO" ]]; then
    echo "$REPO"
    return
  fi
  gh repo view --json nameWithOwner --jq .nameWithOwner
}

resolve_ref() {
  if [[ -n "$REF" ]]; then
    echo "$REF"
    return
  fi
  git branch --show-current
}

name_exists() {
  local name="$1"
  local names="$2"
  grep -Fxq "$name" <<<"$names"
}

github_variable_value() {
  local repo="$1"
  local name="$2"
  gh variable list \
    --repo "$repo" \
    --json name,value \
    --jq ".[] | select(.name == \"$name\") | .value" 2>/dev/null || true
}

check_github_inputs() {
  local repo="$1"
  local secret_names
  local variable_names
  local enable_https
  local missing=()
  local name

  secret_names="$(gh secret list --repo "$repo" | awk '{print $1}')"
  variable_names="$(gh variable list --repo "$repo" | awk '{print $1}')"
  enable_https="$(github_variable_value "$repo" ENABLE_HTTPS)"
  if [[ -z "$enable_https" ]]; then
    enable_https="true"
  fi

  for name in \
    FIREBASE_SERVICE_ACCOUNT_JSON \
    APNS_AUTH_KEY_P8 \
    KBO_RELAY_USER_ID \
    KBO_RELAY_PASSWORD; do
    if ! name_exists "$name" "$secret_names"; then
      missing+=("secret:$name")
    fi
  done

  if ! name_exists AWS_ROLE_TO_ASSUME "$secret_names"; then
    if ! name_exists AWS_ACCESS_KEY_ID "$secret_names" || ! name_exists AWS_SECRET_ACCESS_KEY "$secret_names"; then
      missing+=("secret:AWS_ROLE_TO_ASSUME or secret:AWS_ACCESS_KEY_ID+AWS_SECRET_ACCESS_KEY")
    fi
  fi

  for name in \
    FIREBASE_PROJECT_ID \
    APNS_KEY_ID \
    APNS_TEAM_ID \
    ECR_REPOSITORY_URI \
    VPC_ID \
    PUBLIC_SUBNET_A_ID \
    PUBLIC_SUBNET_B_ID; do
    if ! name_exists "$name" "$variable_names" && ! name_exists "$name" "$secret_names"; then
      missing+=("variable_or_secret:$name")
    fi
  done

  if [[ "$enable_https" != "false" ]]; then
    if ! name_exists ACM_CERTIFICATE_ARN "$variable_names" && ! name_exists ACM_CERTIFICATE_ARN "$secret_names"; then
      missing+=("variable_or_secret:ACM_CERTIFICATE_ARN")
    fi
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing GitHub Actions inputs for Push Demo Deploy:" >&2
    for name in "${missing[@]}"; do
      echo "  - $name" >&2
    done
    cat >&2 <<EOF

Prepare them with:
  ./scripts/github-push-secrets.sh --env-file /path/to/kbo-fans-aws.env --repo $repo --apply
EOF
    exit 2
  fi
}

require_cmd gh
require_cmd git
gh auth status >/dev/null

repo="$(resolve_repo)"
ref="$(resolve_ref)"

if [[ -z "$ref" ]]; then
  echo "Could not resolve git branch. Pass --ref explicitly." >&2
  exit 2
fi

if ! gh workflow view push-demo-deploy.yml --repo "$repo" >/dev/null 2>&1; then
  cat >&2 <<EOF
GitHub workflow is not available on the repository default branch yet:
  repo: $repo
  workflow: .github/workflows/push-demo-deploy.yml

Commit and push the workflow file before dispatching:
  git add .github/workflows/push-demo-deploy.yml scripts/*.sh README.md docs/PUSH_LIVE_ACTIVITY_BACKEND_SETUP.md CHANGELOG.md AGENTS.md CLAUDE.md docs/WORKLOG.md
  git commit -m "푸시 데모 배포 자동화 추가"
  git push
EOF
  exit 1
fi

if [[ "$SKIP_CONFIG_CHECK" != "true" ]]; then
  check_github_inputs "$repo"
fi

gh workflow run push-demo-deploy.yml \
  --repo "$repo" \
  --ref "$ref" \
  -f "dry_run=$DRY_RUN" \
  -f "image_tag=$IMAGE_TAG" \
  -f "skip_readiness=$SKIP_READINESS" \
  -f "resubscribe_topics=$RESUBSCRIBE_TOPICS"

echo "github_push_demo_run=status=dispatched repo=$repo ref=$ref dry_run=$DRY_RUN tag=$IMAGE_TAG skip_readiness=$SKIP_READINESS resubscribe_topics=$RESUBSCRIBE_TOPICS"

if [[ "$WATCH" == "true" ]]; then
  sleep 3
  run_id="$(
    gh run list \
      --repo "$repo" \
      --workflow push-demo-deploy.yml \
      --branch "$ref" \
      --limit 1 \
      --json databaseId \
      --jq '.[0].databaseId'
  )"
  if [[ -z "$run_id" || "$run_id" == "null" ]]; then
    echo "Could not find the dispatched workflow run." >&2
    exit 1
  fi
  gh run watch "$run_id" --repo "$repo" --exit-status
fi
