#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="/tmp/kbo-fans-aws.env"
REPO=""
SKIP_GH=false
SKIP_TOOLING=false
CREATE_ENV=true
FORCE_BOOTSTRAP=false
FAILURES=0
WARNINGS=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/push-demo-setup-status.sh [--env-file /tmp/kbo-fans-aws.env] [--repo owner/repo]

Options:
  --env-file <path>  Local untracked push demo env file. Default: /tmp/kbo-fans-aws.env
  --repo <owner/repo> GitHub repository. Default: resolved by gh when possible.
  --no-create-env    Do not create the env file when it is missing.
  --force-bootstrap  Recreate the env file even when it already exists.
  --skip-gh          Skip GitHub Actions remote inspection.
  --skip-tooling     Skip local AWS CLI / Docker tooling inspection.

Purpose:
  Show the current setup status for the iPhone-only push / Dynamic Island demo
  without deploying, dispatching workflows, or printing secret values.
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
    --no-create-env)
      CREATE_ENV=false
      shift
      ;;
    --force-bootstrap)
      FORCE_BOOTSTRAP=true
      shift
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

section() {
  echo
  echo "== $1 =="
}

print_required_values() {
  cat <<'EOF'
required_value[1]=Firebase iOS client config
  get_from: Firebase Console > Project settings > Your apps > iOS app
  put_in_env: IOS_GOOGLE_SERVICE_INFO_PLIST_FILE=/path/to/GoogleService-Info.plist
  github_target: secret IOS_GOOGLE_SERVICE_INFO_PLIST
  app_target: app/ios/Runner/GoogleService-Info.plist
required_value[2]=Firebase Android client config
  get_from: Firebase Console > Project settings > Your apps > Android app
  put_in_env: ANDROID_GOOGLE_SERVICES_JSON_FILE=/path/to/google-services.json
  github_target: secret ANDROID_GOOGLE_SERVICES_JSON
  app_target: app/android/app/google-services.json
required_value[3]=Firebase Admin service account JSON
  get_from: Firebase Console > Project settings > Service accounts > Generate new private key
  put_in_env: FIREBASE_SERVICE_ACCOUNT_FILE=/path/to/firebase-service-account.json and FIREBASE_PROJECT_ID=<project-id>
  github_target: secret FIREBASE_SERVICE_ACCOUNT_JSON and variable/secret FIREBASE_PROJECT_ID
  aws_runtime_target: Secrets Manager value injected as FIREBASE_SERVICE_ACCOUNT_JSON
required_value[4]=Apple APNs ActivityKit key
  get_from: Apple Developer > Certificates, Identifiers & Profiles > Keys > Apple Push Notifications service
  put_in_env: APNS_AUTH_KEY_FILE=/path/to/AuthKey_<KEY_ID>.p8, APNS_KEY_ID=<key-id>, APNS_TEAM_ID=<team-id>, APNS_USE_SANDBOX=false
  github_target: secret APNS_AUTH_KEY_P8 and variables/secrets APNS_KEY_ID, APNS_TEAM_ID
  aws_runtime_target: Secrets Manager value injected as APNS_AUTH_KEY_P8
required_value[5]=Push sync secret
  get_from: openssl rand -hex 32
  put_in_env: PUSH_SYNC_SECRET=<64-hex-secret>
  github_target: secret PUSH_SYNC_SECRET
  aws_runtime_target: Secrets Manager value injected as PUSH_SYNC_SECRET
required_value[6]=AWS deploy targets
  get_from: AWS Console/CLI for ap-northeast-2 ECR, VPC, two public subnets, ACM certificate
  put_in_env: AWS_REGION, ECR_REPOSITORY_URI, VPC_ID, PUBLIC_SUBNET_A_ID, PUBLIC_SUBNET_B_ID, ACM_CERTIFICATE_ARN
  github_target: GitHub Actions variables/secrets with the same names
  aws_runtime_target: CloudFormation creates ALB, ECS API service, ECS sync worker, EFS registry, IAM, CloudWatch logs
required_value[7]=GitHub Actions AWS auth
  get_from: ./scripts/aws-github-oidc-role.sh --env-file <env> --repo <owner/repo> --update-env-file
  put_in_env: AWS_ROLE_TO_ASSUME=<role-arn>
  github_target: secret AWS_ROLE_TO_ASSUME
  fallback: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY only if OIDC cannot be created
required_value[8]=Release app API base URL
  get_from: ./scripts/aws-push-stack-outputs.sh after CloudFormation deploy
  put_in_env: RELEASE_API_BASE_URL or API_BASE_URL=<stack ApiBaseUrl>
  app_runtime_target: token registration endpoint only; USE_BACKEND_API=true is still required to switch app data routing
EOF
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  echo "warn: $1" >&2
}

fail() {
  FAILURES=$((FAILURES + 1))
  echo "fail: $1" >&2
}

run_required() {
  local label="$1"
  shift

  local output
  if output="$("$@" 2>&1)"; then
    echo "ok: $label"
    printf '%s\n' "$output" | tail -n 12 | sed 's/^/  /'
    return 0
  fi

  fail "$label"
  printf '%s\n' "$output" | tail -n 20 | sed 's/^/  /' >&2
  return 1
}

run_attention() {
  local label="$1"
  shift

  local output
  if output="$("$@" 2>&1)"; then
    echo "ok: $label"
    printf '%s\n' "$output" | tail -n 12 | sed 's/^/  /'
    return 0
  fi

  warn "$label"
  printf '%s\n' "$output" | tail -n 24 | sed 's/^/  /' >&2
  return 1
}

repo_args=()
next_repo="${REPO:-<owner/repo>}"
if [[ -n "$REPO" ]]; then
  repo_args=(--repo "$REPO")
fi

echo "push_demo_setup_status=started env_file=$ENV_FILE repo=$next_repo"

section "Env File"
if [[ "$FORCE_BOOTSTRAP" == "true" || ! -f "$ENV_FILE" ]]; then
  if [[ "$CREATE_ENV" == "true" ]]; then
    bootstrap_args=(--output "$ENV_FILE")
    if [[ -n "$REPO" ]]; then
      bootstrap_args+=(--repo "$REPO")
    fi
    if [[ "$FORCE_BOOTSTRAP" == "true" ]]; then
      bootstrap_args+=(--force)
    fi
    run_required "env bootstrap" \
      bash "$ROOT_DIR/scripts/push-demo-env-bootstrap.sh" "${bootstrap_args[@]}" || true
  else
    fail "env file missing and --no-create-env was set: $ENV_FILE"
  fi
else
  echo "ok: env file exists: $ENV_FILE"
fi

if [[ -f "$ENV_FILE" ]]; then
  mode=""
  if stat -f "%Lp" "$ENV_FILE" >/dev/null 2>&1; then
    mode="$(stat -f "%Lp" "$ENV_FILE")"
  elif stat -c "%a" "$ENV_FILE" >/dev/null 2>&1; then
    mode="$(stat -c "%a" "$ENV_FILE")"
  fi
  if [[ -n "$mode" ]]; then
    echo "ok: env file mode=$mode"
  fi
fi

section "AWS OIDC"
if [[ -f "$ENV_FILE" ]]; then
  run_attention "GitHub Actions AWS OIDC role dry-run" \
    bash "$ROOT_DIR/scripts/aws-github-oidc-role.sh" \
      --env-file "$ENV_FILE" \
      "${repo_args[@]}" \
      --dry-run \
      --update-env-file || true
else
  warn "OIDC dry-run skipped because env file is missing"
fi

section "Readiness Audit"
if [[ -f "$ENV_FILE" ]]; then
  audit_args=(--env-file "$ENV_FILE")
  if [[ "$SKIP_GH" == "true" ]]; then
    audit_args+=(--skip-gh)
  fi
  if [[ "$SKIP_TOOLING" == "true" ]]; then
    audit_args+=(--skip-tooling)
  fi
  audit_args+=("${repo_args[@]}")
  run_attention "push demo readiness audit" \
    bash "$ROOT_DIR/scripts/push-demo-readiness-audit.sh" "${audit_args[@]}" || true
else
  warn "readiness audit skipped because env file is missing"
fi

section "Required Values"
print_required_values

section "Next Commands"
if [[ -f "$ENV_FILE" ]]; then
  echo "next_command: edit $ENV_FILE and replace Firebase Admin, Apple APNs, and AWS placeholders by following the inline comments"
  echo "next_command: ./scripts/aws-github-oidc-role.sh --env-file $ENV_FILE --repo $next_repo --update-env-file"
  echo "next_command: ./scripts/github-push-secrets.sh --env-file $ENV_FILE --apply"
  echo "next_command: ./scripts/github-push-demo-run.sh --dry-run true --watch"
  echo "next_command: ./scripts/github-push-demo-run.sh --dry-run false --watch"
else
  echo "next_command: ./scripts/push-demo-setup-status.sh --env-file $ENV_FILE --repo $next_repo"
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo "push_demo_setup_status=status=failed warnings=$WARNINGS failures=$FAILURES" >&2
  exit 1
fi

if [[ "$WARNINGS" -gt 0 ]]; then
  echo "push_demo_setup_status=status=attention warnings=$WARNINGS failures=0" >&2
  exit 1
fi

echo "push_demo_setup_status=status=ok warnings=0 failures=0"
