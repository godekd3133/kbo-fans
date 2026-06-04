#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE=""
REPO=""
SKIP_GH=false
SKIP_TOOLING=false
FAILURES=0
WARNINGS=0
CHECKS=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/push-demo-readiness-audit.sh [--env-file /path/to/kbo-fans-aws.env]

Options:
  --env-file <path>  Source/check the local push demo env checklist.
  --repo <owner/repo> Override GitHub repository. Default: gh repo view.
  --skip-gh          Skip GitHub Actions workflow/secrets/variables inspection.
  --skip-tooling     Skip local AWS CLI / Docker tooling inspection.

Purpose:
  Audit the current readiness for an iPhone-only push / Live Activity demo.
  This script does not deploy, does not dispatch workflows, and does not print
  secret values.
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
    --skip-gh)
      SKIP_GH=true
      shift
      ;;
    --skip-tooling)
      SKIP_TOOLING=true
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

pass() {
  CHECKS=$((CHECKS + 1))
  echo "ok: $1"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  echo "warn: $1" >&2
}

fail() {
  FAILURES=$((FAILURES + 1))
  echo "fail: $1" >&2
}

section() {
  echo
  echo "== $1 =="
}

run_and_report() {
  local label="$1"
  shift

  local output
  if output="$("$@" 2>&1)"; then
    pass "$label"
    printf '%s\n' "$output" | tail -n 8 | sed 's/^/  /'
    return 0
  fi

  fail "$label"
  printf '%s\n' "$output" | tail -n 16 | sed 's/^/  /' >&2
  return 1
}

run_and_warn() {
  local label="$1"
  shift

  local output
  if output="$("$@" 2>&1)"; then
    pass "$label"
    printf '%s\n' "$output" | tail -n 8 | sed 's/^/  /'
    return 0
  fi

  warn "$label"
  printf '%s\n' "$output" | tail -n 12 | sed 's/^/  /' >&2
  return 1
}

name_exists() {
  local name="$1"
  local names="$2"
  grep -Fxq "$name" <<<"$names"
}

resolve_repo() {
  if [[ -n "$REPO" ]]; then
    echo "$REPO"
    return
  fi

  if ! command -v gh >/dev/null 2>&1; then
    echo ""
    return
  fi

  gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true
}

check_github_secret() {
  local name="$1"
  local secret_names="$2"
  if name_exists "$name" "$secret_names"; then
    pass "GitHub secret configured: $name"
  else
    fail "GitHub secret missing: $name"
  fi
}

check_github_variable_or_secret() {
  local name="$1"
  local secret_names="$2"
  local variable_names="$3"
  if name_exists "$name" "$variable_names" || name_exists "$name" "$secret_names"; then
    pass "GitHub variable/secret configured: $name"
  else
    fail "GitHub variable/secret missing: $name"
  fi
}

audit_github() {
  section "GitHub Actions"

  if [[ "$SKIP_GH" == "true" ]]; then
    warn "GitHub audit skipped by --skip-gh"
    return
  fi

  if ! command -v gh >/dev/null 2>&1; then
    fail "GitHub CLI not found; install gh or use local AWS deploy"
    return
  fi

  if ! gh auth status >/dev/null 2>&1; then
    fail "GitHub CLI is not authenticated"
    return
  fi

  local repo
  repo="$(resolve_repo)"
  if [[ -z "$repo" ]]; then
    fail "GitHub repository could not be resolved; pass --repo owner/repo"
    return
  fi
  pass "GitHub repository resolved: $repo"

  if gh workflow view push-demo-deploy.yml --repo "$repo" >/dev/null 2>&1; then
    pass "Push Demo Deploy workflow is visible on GitHub"
  else
    fail "Push Demo Deploy workflow is not visible on GitHub default branch"
  fi

  local secret_names
  local variable_names
  if ! secret_names="$(gh secret list --repo "$repo" | awk '{print $1}')"; then
    fail "Could not list GitHub Actions secrets"
    return
  fi
  if ! variable_names="$(gh variable list --repo "$repo" | awk '{print $1}')"; then
    fail "Could not list GitHub Actions variables"
    return
  fi

  for name in \
    IOS_GOOGLE_SERVICE_INFO_PLIST \
    ANDROID_GOOGLE_SERVICES_JSON \
    FIREBASE_SERVICE_ACCOUNT_JSON \
    APNS_AUTH_KEY_P8; do
    check_github_secret "$name" "$secret_names"
  done

  if name_exists AWS_ROLE_TO_ASSUME "$secret_names"; then
    pass "GitHub AWS auth configured: AWS_ROLE_TO_ASSUME"
  elif name_exists AWS_ACCESS_KEY_ID "$secret_names" && name_exists AWS_SECRET_ACCESS_KEY "$secret_names"; then
    pass "GitHub AWS auth configured: AWS access key pair"
  else
    fail "GitHub AWS auth missing: AWS_ROLE_TO_ASSUME or AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY"
  fi

  if name_exists PUSH_SYNC_SECRET "$secret_names"; then
    pass "GitHub secret configured: PUSH_SYNC_SECRET"
  else
    warn "GitHub secret PUSH_SYNC_SECRET missing; workflow can generate one, but a stable secret is easier to verify later"
  fi

  for name in \
    AWS_REGION \
    FIREBASE_PROJECT_ID \
    APNS_KEY_ID \
    APNS_TEAM_ID \
    ECR_REPOSITORY_URI \
    VPC_ID \
    PUBLIC_SUBNET_A_ID \
    PUBLIC_SUBNET_B_ID \
    ACM_CERTIFICATE_ARN; do
    check_github_variable_or_secret "$name" "$secret_names" "$variable_names"
  done

  local latest_run
  latest_run="$(
    gh run list \
      --repo "$repo" \
      --workflow push-demo-deploy.yml \
      --limit 1 \
      --json databaseId,status,conclusion,url \
      --jq '.[0] // empty' 2>/dev/null || true
  )"
  if [[ -n "$latest_run" ]]; then
    pass "Latest Push Demo Deploy run found: $latest_run"
  else
    warn "No Push Demo Deploy workflow run found yet"
  fi
}

echo "push_demo_readiness_audit=started"

section "App Project"
run_and_report "App Firebase/APNs/Live Activity project files" \
  bash "$ROOT_DIR/scripts/push-live-preflight.sh" --app-only || true

section "Local Env Checklist"
if [[ -n "$ENV_FILE" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    pass "env file found: $ENV_FILE"
    run_and_report "env file passes push/live AWS preflight" \
      bash "$ROOT_DIR/scripts/push-live-preflight.sh" --env-file "$ENV_FILE" --aws || true
    if [[ "$SKIP_GH" != "true" ]]; then
      github_push_args=(--env-file "$ENV_FILE")
      if [[ -n "$REPO" ]]; then
        github_push_args+=(--repo "$REPO")
      fi
      run_and_report "env file can populate GitHub Actions inputs (dry-run)" \
        bash "$ROOT_DIR/scripts/github-push-secrets.sh" "${github_push_args[@]}" || true
    fi
  else
    fail "env file not found: $ENV_FILE"
  fi
else
  warn "env file not supplied; copy infra/aws/ecs-fargate/deploy.env.example to a local untracked env file"
fi

section "Local AWS/Docker Tooling"
if [[ "$SKIP_TOOLING" == "true" ]]; then
  warn "local AWS/Docker tooling audit skipped by --skip-tooling"
else
  run_and_warn "local AWS CLI / Docker tooling" \
    bash "$ROOT_DIR/scripts/aws-push-tooling-check.sh" || true
fi

audit_github

section "Next Actions"
if [[ -z "$ENV_FILE" ]]; then
  echo "next: cp infra/aws/ecs-fargate/deploy.env.example /tmp/kbo-fans-aws.env"
  echo "next: edit /tmp/kbo-fans-aws.env with Firebase, Apple, and AWS values"
  echo "next: ./scripts/push-demo-readiness-audit.sh --env-file /tmp/kbo-fans-aws.env --repo <owner/repo>"
else
  echo "next: ./scripts/github-push-secrets.sh --env-file $ENV_FILE --apply"
  echo "next: ./scripts/github-push-demo-run.sh --dry-run true --watch"
  echo "next: ./scripts/github-push-demo-run.sh --dry-run false --watch"
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo "push_demo_readiness_audit=status=attention checks=$CHECKS warnings=$WARNINGS failures=$FAILURES" >&2
  exit 1
fi

echo "push_demo_readiness_audit=status=ok checks=$CHECKS warnings=$WARNINGS failures=0"
