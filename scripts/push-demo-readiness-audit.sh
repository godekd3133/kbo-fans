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
NEXT_ACTIONS=""

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

repo_hint="${REPO:-<owner/repo>}"

if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

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

add_next_action() {
  local item="$1"
  local existing
  while IFS= read -r existing; do
    if [[ -z "$existing" ]]; then
      continue
    fi
    if [[ "$existing" == "$item" ]]; then
      return
    fi
  done <<<"$NEXT_ACTIONS"

  if [[ -z "$NEXT_ACTIONS" ]]; then
    NEXT_ACTIONS="$item"
  else
    NEXT_ACTIONS="${NEXT_ACTIONS}"$'\n'"$item"
  fi
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
  local action="${3:-}"
  if name_exists "$name" "$secret_names"; then
    pass "GitHub secret configured: $name"
  else
    fail "GitHub secret missing: $name"
    if [[ -n "$action" ]]; then
      add_next_action "$action"
    fi
  fi
}

check_github_variable_or_secret() {
  local name="$1"
  local secret_names="$2"
  local variable_names="$3"
  local action="${4:-}"
  if name_exists "$name" "$variable_names" || name_exists "$name" "$secret_names"; then
    pass "GitHub variable/secret configured: $name"
  else
    fail "GitHub variable/secret missing: $name"
    if [[ -n "$action" ]]; then
      add_next_action "$action"
    fi
  fi
}

looks_like_placeholder_value() {
  local value="$1"

  if [[ -z "$value" ]]; then
    return 1
  fi

  case "$value" in
    *"<"*|*"your-"*|*"replace_"*|*"replace-with"*|*"XXXXXXXXXX"*|*"123456789012"*|*"000000000000"*|*"111111111111"*)
      return 0
      ;;
  esac

  return 1
}

env_value_ready() {
  local name="$1"
  local value="${!name:-}"

  [[ -n "$value" ]] || return 1
  ! looks_like_placeholder_value "$value"
}

secret_file_ready() {
  local value_name="$1"
  local file_name="$2"
  local default_path="${3:-}"
  local value="${!value_name:-}"
  local path="${!file_name:-}"

  if [[ -n "$value" ]] && ! looks_like_placeholder_value "$value"; then
    return 0
  fi
  if [[ -n "$path" && -f "$path" ]] && ! looks_like_placeholder_value "$path"; then
    return 0
  fi
  if [[ -n "$default_path" && -f "$default_path" ]]; then
    return 0
  fi

  return 1
}

github_upload_command_hint() {
  if [[ -n "$ENV_FILE" ]]; then
    echo "./scripts/github-push-secrets.sh --env-file $ENV_FILE --apply"
  else
    echo "./scripts/github-push-secrets.sh --env-file <env> --apply"
  fi
}

github_secret_action() {
  local label="$1"
  local value_name="$2"
  local file_name="$3"
  local default_path="${4:-}"
  local setup_action="$5"
  local upload_cmd
  upload_cmd="$(github_upload_command_hint)"

  if secret_file_ready "$value_name" "$file_name" "$default_path"; then
    echo "$label: local value/file is available; upload it to GitHub Actions with $upload_cmd"
  else
    echo "$setup_action"
  fi
}

github_variable_action() {
  local label="$1"
  local env_name="$2"
  local setup_action="$3"
  local upload_cmd
  upload_cmd="$(github_upload_command_hint)"

  if env_value_ready "$env_name"; then
    echo "$label: env value is available; upload it to GitHub Actions with $upload_cmd"
  else
    echo "$setup_action"
  fi
}

github_variable_value() {
  local repo="$1"
  local name="$2"
  gh variable list \
    --repo "$repo" \
    --json name,value \
    --jq ".[] | select(.name == \"$name\") | .value" 2>/dev/null || true
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

  local github_enable_https
  github_enable_https="$(github_variable_value "$repo" ENABLE_HTTPS)"
  if [[ -z "$github_enable_https" ]]; then
    github_enable_https="${ENABLE_HTTPS:-true}"
  fi

  check_github_secret \
    IOS_GOOGLE_SERVICE_INFO_PLIST \
    "$secret_names" \
    "$(github_secret_action \
      "firebase-client-ios" \
      IOS_GOOGLE_SERVICE_INFO_PLIST \
      IOS_GOOGLE_SERVICE_INFO_PLIST_FILE \
      "$ROOT_DIR/app/ios/Runner/GoogleService-Info.plist" \
      "firebase-client-ios: download Firebase iOS GoogleService-Info.plist, set IOS_GOOGLE_SERVICE_INFO_PLIST_FILE in the env file, then run github-push-secrets.sh --apply")"
  check_github_secret \
    ANDROID_GOOGLE_SERVICES_JSON \
    "$secret_names" \
    "$(github_secret_action \
      "firebase-client-android" \
      ANDROID_GOOGLE_SERVICES_JSON \
      ANDROID_GOOGLE_SERVICES_JSON_FILE \
      "$ROOT_DIR/app/android/app/google-services.json" \
      "firebase-client-android: download Firebase Android google-services.json, set ANDROID_GOOGLE_SERVICES_JSON_FILE in the env file, then run github-push-secrets.sh --apply")"
  check_github_secret \
    FIREBASE_SERVICE_ACCOUNT_JSON \
    "$secret_names" \
    "$(github_secret_action \
      "firebase-admin" \
      FIREBASE_SERVICE_ACCOUNT_JSON \
      FIREBASE_SERVICE_ACCOUNT_FILE \
      "" \
      "firebase-admin: create a Firebase Admin service account JSON, set FIREBASE_SERVICE_ACCOUNT_FILE in the env file, then run github-push-secrets.sh --apply")"
  check_github_secret \
    APNS_AUTH_KEY_P8 \
    "$secret_names" \
    "$(github_secret_action \
      "apple-apns-key" \
      APNS_AUTH_KEY_P8 \
      APNS_AUTH_KEY_FILE \
      "" \
      "apple-apns-key: create/download an Apple APNs .p8 key, set APNS_AUTH_KEY_FILE, APNS_KEY_ID, and APNS_TEAM_ID in the env file, then run github-push-secrets.sh --apply")"
  check_github_secret \
    KBO_RELAY_USER_ID \
    "$secret_names" \
    "$(github_secret_action \
      "kbo-relay-user" \
      KBO_RELAY_USER_ID \
      KBO_RELAY_USER_ID \
      "" \
      "kbo-relay-user: set KBO_RELAY_USER_ID in the env file from local secure storage, then run github-push-secrets.sh --apply")"
  check_github_secret \
    KBO_RELAY_PASSWORD \
    "$secret_names" \
    "$(github_secret_action \
      "kbo-relay-password" \
      KBO_RELAY_PASSWORD \
      KBO_RELAY_PASSWORD \
      "" \
      "kbo-relay-password: set KBO_RELAY_PASSWORD in the env file from local secure storage, then run github-push-secrets.sh --apply")"

  if name_exists AWS_ROLE_TO_ASSUME "$secret_names"; then
    pass "GitHub AWS auth configured: AWS_ROLE_TO_ASSUME"
  elif name_exists AWS_ACCESS_KEY_ID "$secret_names" && name_exists AWS_SECRET_ACCESS_KEY "$secret_names"; then
    pass "GitHub AWS auth configured: AWS access key pair"
  else
    fail "GitHub AWS auth missing: AWS_ROLE_TO_ASSUME or AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY"
    if env_value_ready AWS_ROLE_TO_ASSUME; then
      add_next_action "aws-auth: AWS_ROLE_TO_ASSUME is available in env; upload it to GitHub Actions with $(github_upload_command_hint)"
    elif env_value_ready AWS_ACCESS_KEY_ID && env_value_ready AWS_SECRET_ACCESS_KEY; then
      add_next_action "aws-auth: AWS access key pair is available in env; upload it to GitHub Actions with $(github_upload_command_hint)"
    else
      add_next_action "aws-auth: prefer ./scripts/aws-github-oidc-role.sh --env-file <env> --repo $repo_hint --update-env-file, then run github-push-secrets.sh --apply"
    fi
  fi

  if name_exists PUSH_SYNC_SECRET "$secret_names"; then
    pass "GitHub secret configured: PUSH_SYNC_SECRET"
  else
    warn "GitHub secret PUSH_SYNC_SECRET missing; workflow can generate one, but a stable secret is easier to verify later"
    add_next_action "$(github_variable_action \
      "push-sync" \
      PUSH_SYNC_SECRET \
      "push-sync: generate PUSH_SYNC_SECRET with openssl rand -hex 32, put it in the env file, then run github-push-secrets.sh --apply")"
  fi

  check_github_variable_or_secret \
    AWS_REGION \
    "$secret_names" \
    "$variable_names" \
    "$(github_variable_action \
      "aws-region" \
      AWS_REGION \
      "aws-region: set AWS_REGION in the env file and re-run github-push-secrets.sh --apply")"
  check_github_variable_or_secret \
    FIREBASE_PROJECT_ID \
    "$secret_names" \
    "$variable_names" \
    "$(github_variable_action \
      "firebase-project" \
      FIREBASE_PROJECT_ID \
      "firebase-project: set FIREBASE_PROJECT_ID from the Firebase project settings and re-run github-push-secrets.sh --apply")"
  check_github_variable_or_secret \
    APNS_KEY_ID \
    "$secret_names" \
    "$variable_names" \
    "$(github_variable_action \
      "apple-apns-key-id" \
      APNS_KEY_ID \
      "apple-apns-key-id: set APNS_KEY_ID from the Apple APNs key and re-run github-push-secrets.sh --apply")"
  check_github_variable_or_secret \
    APNS_TEAM_ID \
    "$secret_names" \
    "$variable_names" \
    "$(github_variable_action \
      "apple-apns-team-id" \
      APNS_TEAM_ID \
      "apple-apns-team-id: set APNS_TEAM_ID from Apple Developer membership and re-run github-push-secrets.sh --apply")"
  check_github_variable_or_secret \
    ECR_REPOSITORY_URI \
    "$secret_names" \
    "$variable_names" \
    "$(github_variable_action \
      "aws-ecr" \
      ECR_REPOSITORY_URI \
      "aws-ecr: create/select an ECR repository, set ECR_REPOSITORY_URI, then re-run github-push-secrets.sh --apply")"
  check_github_variable_or_secret \
    VPC_ID \
    "$secret_names" \
    "$variable_names" \
    "$(github_variable_action \
      "aws-network-vpc" \
      VPC_ID \
      "aws-network-vpc: choose the demo VPC, set VPC_ID, then re-run github-push-secrets.sh --apply")"
  check_github_variable_or_secret \
    PUBLIC_SUBNET_A_ID \
    "$secret_names" \
    "$variable_names" \
    "$(github_variable_action \
      "aws-network-subnet-a" \
      PUBLIC_SUBNET_A_ID \
      "aws-network-subnet-a: choose public subnet A for the ALB/ECS service and set PUBLIC_SUBNET_A_ID")"
  check_github_variable_or_secret \
    PUBLIC_SUBNET_B_ID \
    "$secret_names" \
    "$variable_names" \
    "$(github_variable_action \
      "aws-network-subnet-b" \
      PUBLIC_SUBNET_B_ID \
      "aws-network-subnet-b: choose public subnet B in a different AZ and set PUBLIC_SUBNET_B_ID")"
  if [[ "${ENABLE_HTTPS:-}" == "false" ]] \
    && ! name_exists ENABLE_HTTPS "$variable_names" \
    && ! name_exists ENABLE_HTTPS "$secret_names"; then
    fail "GitHub variable/secret missing: ENABLE_HTTPS=false for HTTP-only demo mode"
    add_next_action "aws-http-only: env has ENABLE_HTTPS=false; upload it to GitHub Actions with $(github_upload_command_hint)"
  elif [[ "$github_enable_https" == "false" ]]; then
    pass "GitHub HTTPS mode disabled for HTTP-only AWS smoke deploy"
  else
    check_github_variable_or_secret \
      ACM_CERTIFICATE_ARN \
      "$secret_names" \
      "$variable_names" \
      "$(github_variable_action \
        "aws-https" \
        ACM_CERTIFICATE_ARN \
        "aws-https: issue or select an ACM certificate in the deploy region and set ACM_CERTIFICATE_ARN")"
    check_github_variable_or_secret \
      API_DOMAIN_NAME \
      "$secret_names" \
      "$variable_names" \
      "$(github_variable_action \
        "aws-https-domain" \
        API_DOMAIN_NAME \
        "aws-https-domain: set the custom DNS name covered by ACM_CERTIFICATE_ARN")"
  fi

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
  add_next_action "prepare-env: cp infra/aws/ecs-fargate/deploy.env.example /tmp/kbo-fans-aws.env"
  add_next_action "prepare-env: edit /tmp/kbo-fans-aws.env with Firebase, Apple, and AWS values"
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
if [[ -n "$NEXT_ACTIONS" ]]; then
  index=1
  while IFS= read -r action; do
    if [[ -z "$action" ]]; then
      continue
    fi
    echo "next_config[$index]: $action"
    index=$((index + 1))
  done <<<"$NEXT_ACTIONS"
fi

if [[ -z "$ENV_FILE" ]]; then
  echo "next_command: ./scripts/push-demo-readiness-audit.sh --env-file /tmp/kbo-fans-aws.env --repo $repo_hint"
else
  echo "next_command: ./scripts/github-push-secrets.sh --env-file $ENV_FILE --apply"
  echo "next_command: ./scripts/push-demo-readiness-audit.sh --env-file $ENV_FILE --repo $repo_hint"
  echo "next_command: ./scripts/github-push-demo-run.sh --dry-run true --watch"
  echo "next_command: ./scripts/github-push-demo-run.sh --dry-run false --watch"
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo "push_demo_readiness_audit=status=attention checks=$CHECKS warnings=$WARNINGS failures=$FAILURES" >&2
  exit 1
fi

echo "push_demo_readiness_audit=status=ok checks=$CHECKS warnings=$WARNINGS failures=0"
