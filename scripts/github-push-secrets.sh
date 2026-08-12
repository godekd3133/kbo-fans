#!/usr/bin/env bash

set -euo pipefail

APPLY=false
ENV_FILE=""
REPO=""
GENERATED_PUSH_SYNC_SECRET=false

usage() {
  cat <<'EOF'
Usage:
  ./scripts/github-push-secrets.sh --env-file /path/to/kbo-fans-aws.env
  ./scripts/github-push-secrets.sh --env-file /path/to/kbo-fans-aws.env --apply

Options:
  --env-file <path>  Source local AWS/Firebase/APNs deployment values.
  --repo <owner/repo> Override GitHub repository. Default: gh repo view.
  --apply            Write GitHub Actions secrets and variables. Default is dry-run.

Purpose:
  Prepare GitHub Actions Push Demo Deploy inputs from local env/file values.
  Secret values are never printed. In dry-run mode this only validates shape and
  reports which GitHub secret/variable names would be written.

Required secret inputs:
  - IOS_GOOGLE_SERVICE_INFO_PLIST or IOS_GOOGLE_SERVICE_INFO_PLIST_FILE
  - ANDROID_GOOGLE_SERVICES_JSON or ANDROID_GOOGLE_SERVICES_JSON_FILE
  - FIREBASE_SERVICE_ACCOUNT_JSON or FIREBASE_SERVICE_ACCOUNT_FILE
  - APNS_AUTH_KEY_P8 or APNS_AUTH_KEY_FILE
  - KBO_RELAY_USER_ID
  - KBO_RELAY_PASSWORD
  - PUSH_SYNC_SECRET (generated when missing)
  - AWS_ROLE_TO_ASSUME, or AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY

Required variable inputs:
  - AWS_REGION
  - FIREBASE_PROJECT_ID
  - APNS_KEY_ID
  - APNS_TEAM_ID
  - ECR_REPOSITORY_URI
  - VPC_ID
  - PUBLIC_SUBNET_A_ID
  - PUBLIC_SUBNET_B_ID
  - ACM_CERTIFICATE_ARN (when ENABLE_HTTPS=true)
  - API_DOMAIN_NAME (when ENABLE_HTTPS=true; must match ACM_CERTIFICATE_ARN)

Optional variable inputs:
  - ENABLE_HTTPS (default true; set false for temporary HTTP-only AWS smoke deploys)
  - API_DOMAIN_NAME (required for HTTPS; custom domain matching ACM_CERTIFICATE_ARN)
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
    --apply)
      APPLY=true
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

reject_placeholder_value() {
  local name="$1"
  local value="${!name:-}"

  if [[ -z "$value" ]]; then
    return
  fi

  case "$value" in
    *"<"*|*"your-"*|*"replace_"*|*"replace-with"*|*"XXXXXXXXXX"*|*"123456789012"*|*"000000000000"*|*"111111111111"*)
      echo "$name still looks like a placeholder. Replace it before uploading GitHub Actions inputs." >&2
      exit 2
      ;;
  esac
}

reject_placeholder_env() {
  local name
  for name in "$@"; do
    reject_placeholder_value "$name"
  done
}

read_secret_value() {
  local env_name="$1"
  local file_env_name="$2"
  local label="$3"
  local value="${!env_name:-}"
  local path="${!file_env_name:-}"

  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return
  fi

  if [[ -z "$path" ]]; then
    echo "Missing $label: set $env_name or $file_env_name." >&2
    exit 2
  fi
  if [[ ! -f "$path" ]]; then
    echo "$label file not found: $path" >&2
    exit 2
  fi
  cat "$path"
}

read_secret_value_with_default_file() {
  local env_name="$1"
  local file_env_name="$2"
  local default_path="$3"
  local label="$4"
  local value="${!env_name:-}"
  local path="${!file_env_name:-}"

  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return
  fi

  if [[ -z "$path" && -f "$default_path" ]]; then
    path="$default_path"
  fi

  if [[ -z "$path" ]]; then
    echo "Missing $label: set $env_name or $file_env_name." >&2
    exit 2
  fi
  if [[ ! -f "$path" ]]; then
    echo "$label file not found: $path" >&2
    exit 2
  fi
  cat "$path"
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

resolve_repo() {
  if [[ -n "$REPO" ]]; then
    echo "$REPO"
    return
  fi
  gh repo view --json nameWithOwner --jq .nameWithOwner
}

set_secret() {
  local name="$1"
  local value="$2"
  local repo="$3"

  if [[ "$APPLY" != "true" ]]; then
    echo "would_set_secret=$name"
    return
  fi

  gh secret set "$name" --repo "$repo" --body "$value" >/dev/null
  echo "set_secret=$name"
}

set_variable() {
  local name="$1"
  local value="$2"
  local repo="$3"

  if [[ "$APPLY" != "true" ]]; then
    echo "would_set_variable=$name"
    return
  fi

  gh variable set "$name" --repo "$repo" --body "$value" >/dev/null
  echo "set_variable=$name"
}

require_cmd gh
require_cmd python3
gh auth status >/dev/null
repo="$(resolve_repo)"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ios_google_plist="$(
  read_secret_value_with_default_file \
    IOS_GOOGLE_SERVICE_INFO_PLIST \
    IOS_GOOGLE_SERVICE_INFO_PLIST_FILE \
    "$root_dir/app/ios/Runner/GoogleService-Info.plist" \
    "iOS GoogleService-Info.plist"
)"
android_google_services_json="$(
  read_secret_value_with_default_file \
    ANDROID_GOOGLE_SERVICES_JSON \
    ANDROID_GOOGLE_SERVICES_JSON_FILE \
    "$root_dir/app/android/app/google-services.json" \
    "Android google-services.json"
)"
firebase_json="$(read_secret_value FIREBASE_SERVICE_ACCOUNT_JSON FIREBASE_SERVICE_ACCOUNT_FILE "Firebase Admin service account JSON")"
apns_key_p8="$(read_secret_value APNS_AUTH_KEY_P8 APNS_AUTH_KEY_FILE "APNs .p8 key")"
kbo_relay_user_id="${KBO_RELAY_USER_ID:-}"
kbo_relay_password="${KBO_RELAY_PASSWORD:-}"

printf '%s' "$ios_google_plist" | python3 -c 'import plistlib,sys; plistlib.loads(sys.stdin.buffer.read())' >/dev/null
printf '%s' "$android_google_services_json" | python3 -m json.tool >/dev/null
printf '%s' "$firebase_json" | python3 -m json.tool >/dev/null
if ! grep -q "BEGIN PRIVATE KEY" <<<"$apns_key_p8"; then
  echo "APNs key does not look like a .p8 private key." >&2
  exit 2
fi
if [[ -z "$kbo_relay_user_id" ]]; then
  echo "KBO_RELAY_USER_ID is required." >&2
  exit 2
fi
if [[ -z "$kbo_relay_password" ]]; then
  echo "KBO_RELAY_PASSWORD is required." >&2
  exit 2
fi

require_env \
  AWS_REGION \
  FIREBASE_PROJECT_ID \
  APNS_KEY_ID \
  APNS_TEAM_ID \
  ECR_REPOSITORY_URI \
  VPC_ID \
  PUBLIC_SUBNET_A_ID \
  PUBLIC_SUBNET_B_ID

ENABLE_HTTPS="${ENABLE_HTTPS:-true}"
case "$ENABLE_HTTPS" in
  true | false)
    ;;
  *)
    echo "ENABLE_HTTPS must be true or false." >&2
    exit 2
    ;;
esac

if [[ "$ENABLE_HTTPS" == "true" ]]; then
  require_env ACM_CERTIFICATE_ARN
fi

if [[ -z "${AWS_ROLE_TO_ASSUME:-}" ]]; then
  require_env AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
fi

reject_placeholder_env \
  AWS_REGION \
  FIREBASE_PROJECT_ID \
  APNS_KEY_ID \
  APNS_TEAM_ID \
  ECR_REPOSITORY_URI \
  VPC_ID \
  PUBLIC_SUBNET_A_ID \
  PUBLIC_SUBNET_B_ID \
  PUSH_SYNC_SECRET \
  KBO_RELAY_USER_ID \
  KBO_RELAY_PASSWORD \
  AWS_ROLE_TO_ASSUME \
  AWS_ACCESS_KEY_ID \
  AWS_SECRET_ACCESS_KEY

if [[ "$ENABLE_HTTPS" == "true" ]]; then
  require_env ACM_CERTIFICATE_ARN API_DOMAIN_NAME
  reject_placeholder_env ACM_CERTIFICATE_ARN API_DOMAIN_NAME
fi
if [[ -n "${API_DOMAIN_NAME:-}" ]]; then
  reject_placeholder_env API_DOMAIN_NAME
fi

ensure_push_sync_secret
if [[ ${#PUSH_SYNC_SECRET} -lt 32 ]]; then
  echo "PUSH_SYNC_SECRET should be at least 32 characters." >&2
  exit 2
fi

echo "github_push_secrets=started repo=$repo mode=$([[ "$APPLY" == "true" ]] && echo apply || echo dry-run)"

set_variable AWS_REGION "$AWS_REGION" "$repo"
set_variable FIREBASE_PROJECT_ID "$FIREBASE_PROJECT_ID" "$repo"
set_variable APNS_KEY_ID "$APNS_KEY_ID" "$repo"
set_variable APNS_TEAM_ID "$APNS_TEAM_ID" "$repo"
set_variable ECR_REPOSITORY_URI "$ECR_REPOSITORY_URI" "$repo"
set_variable VPC_ID "$VPC_ID" "$repo"
set_variable PUBLIC_SUBNET_A_ID "$PUBLIC_SUBNET_A_ID" "$repo"
set_variable PUBLIC_SUBNET_B_ID "$PUBLIC_SUBNET_B_ID" "$repo"
set_variable ENABLE_HTTPS "$ENABLE_HTTPS" "$repo"
if [[ -n "${API_DOMAIN_NAME:-}" ]]; then
  set_variable API_DOMAIN_NAME "$API_DOMAIN_NAME" "$repo"
fi
if [[ "$ENABLE_HTTPS" == "true" ]]; then
  set_variable ACM_CERTIFICATE_ARN "$ACM_CERTIFICATE_ARN" "$repo"
elif [[ -n "${ACM_CERTIFICATE_ARN:-}" ]]; then
  case "$ACM_CERTIFICATE_ARN" in
    *"<"*|*"your-"*|*"replace_"*|*"replace-with"*|*"XXXXXXXXXX"*|*"123456789012"*|*"000000000000"*|*"111111111111"*)
      ;;
    *)
      set_variable ACM_CERTIFICATE_ARN "$ACM_CERTIFICATE_ARN" "$repo"
      ;;
  esac
fi

set_secret IOS_GOOGLE_SERVICE_INFO_PLIST "$ios_google_plist" "$repo"
set_secret ANDROID_GOOGLE_SERVICES_JSON "$android_google_services_json" "$repo"
set_secret FIREBASE_SERVICE_ACCOUNT_JSON "$firebase_json" "$repo"
set_secret APNS_AUTH_KEY_P8 "$apns_key_p8" "$repo"
set_secret PUSH_SYNC_SECRET "$PUSH_SYNC_SECRET" "$repo"
set_secret KBO_RELAY_USER_ID "$kbo_relay_user_id" "$repo"
set_secret KBO_RELAY_PASSWORD "$kbo_relay_password" "$repo"

if [[ -n "${AWS_ROLE_TO_ASSUME:-}" ]]; then
  set_secret AWS_ROLE_TO_ASSUME "$AWS_ROLE_TO_ASSUME" "$repo"
else
  set_secret AWS_ACCESS_KEY_ID "$AWS_ACCESS_KEY_ID" "$repo"
  set_secret AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY" "$repo"
fi

if [[ "$GENERATED_PUSH_SYNC_SECRET" == "true" ]]; then
  echo "generated_secret=PUSH_SYNC_SECRET"
fi

echo "github_push_secrets=status=ok repo=$repo mode=$([[ "$APPLY" == "true" ]] && echo apply || echo dry-run)"
