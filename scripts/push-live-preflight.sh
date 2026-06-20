#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"
CHECK_BACKEND=true
CHECK_AWS=false
ENV_FILE=""
FAILURES=0
WARNINGS=0
CHECKS=0

IOS_BUNDLE_ID="com.kbofans.kboFans"
ANDROID_PACKAGE_NAME="com.kbofans.kbo_fans"
APP_GROUP_ID="group.com.kbofans.kbo_fans"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/push-live-preflight.sh [--env-file /path/to/kbo-fans-aws.env] [--aws]

Options:
  --env-file <path>  Source local deployment env values before checking.
  --app-only         Check only app Firebase/APNs/Live Activity project files.
  --aws              Also check AWS deployment env prerequisites.

Purpose:
  Validate the local prerequisites for app-closed push notifications and
  iPhone Live Activity / Dynamic Island remote updates. This command does not
  call AWS and does not print secret values.
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
    --app-only)
      CHECK_BACKEND=false
      shift
      ;;
    --aws)
      CHECK_AWS=true
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

require_file() {
  local label="$1"
  local path="$2"
  if [[ -f "$path" ]]; then
    pass "$label found"
  else
    fail "$label missing: $path"
  fi
}

require_text() {
  local label="$1"
  local pattern="$2"
  local path="$3"
  if grep -Fq -- "$pattern" "$path" 2>/dev/null; then
    pass "$label configured"
  else
    fail "$label missing in $path"
  fi
}

require_env() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then
    pass "$name set"
  else
    fail "$name missing"
  fi
}

is_placeholder_value() {
  local value="$1"
  [[ "$value" == *"<"* \
    || "$value" == *"your-"* \
    || "$value" == *"replace_"* \
    || "$value" == *"replace-with"* \
    || "$value" == *"XXXXXXXXXX"* \
    || "$value" == *"123456789012"* \
    || "$value" == *"000000000000"* \
    || "$value" == *"111111111111"* ]]
}

warn_placeholder_env() {
  local name="$1"
  local value="${!name:-}"
  if is_placeholder_value "$value"; then
    warn "$name still looks like a placeholder"
  fi
}

fail_placeholder_env() {
  local name="$1"
  local value="${!name:-}"
  if is_placeholder_value "$value"; then
    fail "$name still looks like a placeholder"
  fi
}

is_truthy() {
  case "${1:-}" in
    1 | true | TRUE | True | yes | YES | Yes)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

plist_value() {
  python3 - "$1" "$2" <<'PY'
import plistlib
import sys

path, key = sys.argv[1], sys.argv[2]
with open(path, "rb") as file:
    data = plistlib.load(file)
value = data.get(key, "")
if isinstance(value, list):
    print("\n".join(str(item) for item in value))
elif isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

json_value() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

path, dotted = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as file:
    data = json.load(file)
value = data
for part in dotted.split("."):
    if isinstance(value, list):
        value = value[int(part)]
    else:
        value = value.get(part, "")
print(value)
PY
}

check_ios_firebase() {
  local path="$APP_DIR/ios/Runner/GoogleService-Info.plist"
  require_file "iOS Firebase config" "$path"
  if [[ ! -f "$path" ]]; then
    return 0
  fi

  local bundle_id
  local project_id
  bundle_id="$(plist_value "$path" BUNDLE_ID)"
  project_id="$(plist_value "$path" PROJECT_ID)"
  if [[ "$bundle_id" == "$IOS_BUNDLE_ID" ]]; then
    pass "iOS Firebase bundle ID matches $IOS_BUNDLE_ID"
  else
    fail "iOS Firebase bundle ID is $bundle_id, expected $IOS_BUNDLE_ID"
  fi
  if [[ -n "${FIREBASE_PROJECT_ID:-}" && "$project_id" != "$FIREBASE_PROJECT_ID" ]]; then
    fail "iOS Firebase project ID is $project_id, expected FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID"
  else
    pass "iOS Firebase project ID present"
  fi
}

check_android_firebase() {
  local path="$APP_DIR/android/app/google-services.json"
  require_file "Android Firebase config" "$path"
  if [[ ! -f "$path" ]]; then
    return 0
  fi

  local package_name
  local project_id
  package_name="$(json_value "$path" client.0.client_info.android_client_info.package_name)"
  project_id="$(json_value "$path" project_info.project_id)"
  if [[ "$package_name" == "$ANDROID_PACKAGE_NAME" ]]; then
    pass "Android Firebase package matches $ANDROID_PACKAGE_NAME"
  else
    fail "Android Firebase package is $package_name, expected $ANDROID_PACKAGE_NAME"
  fi
  if [[ -n "${FIREBASE_PROJECT_ID:-}" && "$project_id" != "$FIREBASE_PROJECT_ID" ]]; then
    fail "Android Firebase project ID is $project_id, expected FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID"
  else
    pass "Android Firebase project ID present"
  fi
}

check_ios_activity_capabilities() {
  local runner_entitlements="$APP_DIR/ios/Runner/Runner.entitlements"
  local widget_entitlements="$APP_DIR/ios/KboFansWidgetExtension.entitlements"
  require_file "Runner entitlements" "$runner_entitlements"
  require_file "Widget entitlements" "$widget_entitlements"
  [[ -f "$runner_entitlements" ]] && require_text "Runner APNs environment" "<key>aps-environment</key>" "$runner_entitlements"
  [[ -f "$runner_entitlements" ]] && require_text "Runner App Group" "$APP_GROUP_ID" "$runner_entitlements"
  [[ -f "$widget_entitlements" ]] && require_text "Widget App Group" "$APP_GROUP_ID" "$widget_entitlements"

  local runner_info="$APP_DIR/ios/Runner/Info.plist"
  local widget_info="$APP_DIR/ios/KboFansWidget/Info.plist"
  require_file "Runner Info.plist" "$runner_info"
  require_file "Widget Info.plist" "$widget_info"
  [[ -f "$runner_info" ]] && require_text "Runner Live Activities" "NSSupportsLiveActivities" "$runner_info"
  [[ -f "$runner_info" ]] && require_text "Runner frequent Live Activity updates" "NSSupportsLiveActivitiesFrequentUpdates" "$runner_info"
  [[ -f "$widget_info" ]] && require_text "Widget Live Activities" "NSSupportsLiveActivities" "$widget_info"
  [[ -f "$widget_info" ]] && require_text "Widget frequent Live Activity updates" "NSSupportsLiveActivitiesFrequentUpdates" "$widget_info"

  local project="$APP_DIR/ios/Runner.xcodeproj/project.pbxproj"
  require_text "Debug/Profile APNs development build setting" "APS_ENVIRONMENT = development;" "$project"
  require_text "Release APNs production build setting" "APS_ENVIRONMENT = production;" "$project"
}

check_android_gradle() {
  require_text "Android google-services Gradle plugin declaration" 'id("com.google.gms.google-services") version' "$APP_DIR/android/settings.gradle.kts"
  require_text "Android google-services Gradle plugin application" 'id("com.google.gms.google-services")' "$APP_DIR/android/app/build.gradle.kts"
}

check_flutter_push_code() {
  require_text "Firebase background handler registration" "FirebaseMessaging.onBackgroundMessage" "$APP_DIR/lib/main.dart"
  require_text "FCM dependency" "firebase_messaging:" "$APP_DIR/pubspec.yaml"
  require_text "Firebase Core dependency" "firebase_core:" "$APP_DIR/pubspec.yaml"
  require_text "Live Activity API base URL handoff" "apiBaseUrl: AppConfig.instance.apiBaseUrl" "$APP_DIR/lib/services/live_activity_service.dart"
  require_text "Codex release push backend URL define" '--dart-define=API_BASE_URL=$(release_api_base_url)' "$ROOT_DIR/scripts/codex-run.sh"
  require_text "CI release push backend URL input" "release_api_base_url:" "$ROOT_DIR/.github/workflows/app-build-artifacts.yml"
  require_text "CI release API_BASE_URL dart define" '--dart-define=API_BASE_URL=${push_api_base_url}' "$ROOT_DIR/.github/workflows/app-build-artifacts.yml"
  require_text "CI push API base URL artifact metadata" "PUSH_API_BASE_URL" "$ROOT_DIR/.github/workflows/app-build-artifacts.yml"
}

check_service_account_file() {
  local path="${FIREBASE_SERVICE_ACCOUNT_FILE:-${FIREBASE_SERVICE_ACCOUNT_PATH:-}}"
  if [[ -n "${FIREBASE_SERVICE_ACCOUNT_JSON:-}" ]]; then
    if python3 - <<'PY'
import json
import os
import sys

raw = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON", "")
expected = os.environ.get("FIREBASE_PROJECT_ID", "")
try:
    data = json.loads(raw)
except Exception:
    sys.exit(1)
if expected and data.get("project_id") != expected:
    sys.exit(2)
PY
    then
      pass "FIREBASE_SERVICE_ACCOUNT_JSON parses and matches project when provided"
    else
      fail "FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON or does not match FIREBASE_PROJECT_ID"
    fi
    return
  fi

  if [[ -z "$path" ]]; then
    fail "Firebase Admin secret missing: set FIREBASE_SERVICE_ACCOUNT_JSON or FIREBASE_SERVICE_ACCOUNT_FILE"
    return
  fi
  require_file "Firebase Admin service account file" "$path"
  if [[ ! -f "$path" ]]; then
    return 0
  fi
  if python3 - "$path" <<'PY'
import json
import os
import sys

path = sys.argv[1]
expected = os.environ.get("FIREBASE_PROJECT_ID", "")
with open(path, "r", encoding="utf-8") as file:
    data = json.load(file)
if expected and data.get("project_id") != expected:
    sys.exit(2)
PY
  then
    pass "Firebase Admin service account JSON parses"
  else
    fail "Firebase Admin service account JSON is invalid or project_id mismatches"
  fi
}

check_apns_key() {
  local path="${APNS_AUTH_KEY_FILE:-${APNS_AUTH_KEY_PATH:-}}"
  if [[ -n "${APNS_AUTH_KEY_P8:-}" ]]; then
    if [[ "$APNS_AUTH_KEY_P8" == *"BEGIN PRIVATE KEY"* ]]; then
      pass "APNS_AUTH_KEY_P8 present"
    else
      fail "APNS_AUTH_KEY_P8 does not look like a .p8 private key"
    fi
    return
  fi

  if [[ -z "$path" ]]; then
    fail "APNs key missing: set APNS_AUTH_KEY_P8 or APNS_AUTH_KEY_FILE"
    return
  fi
  require_file "APNs .p8 key file" "$path"
  if [[ ! -f "$path" ]]; then
    return 0
  fi
  if grep -q "BEGIN PRIVATE KEY" "$path"; then
    pass "APNs .p8 key format looks valid"
  else
    fail "APNs .p8 key does not contain BEGIN PRIVATE KEY"
  fi
}

check_backend_env() {
  require_env FIREBASE_PROJECT_ID
  check_service_account_file
  require_env APNS_KEY_ID
  require_env APNS_TEAM_ID
  check_apns_key

  local bundle="${APNS_BUNDLE_ID:-$IOS_BUNDLE_ID}"
  if [[ "$bundle" == "$IOS_BUNDLE_ID" ]]; then
    pass "APNS_BUNDLE_ID matches $IOS_BUNDLE_ID"
  else
    fail "APNS_BUNDLE_ID is $bundle, expected $IOS_BUNDLE_ID"
  fi

  if [[ -n "${PUSH_SYNC_SECRET:-}" ]]; then
    if [[ ${#PUSH_SYNC_SECRET} -ge 32 ]]; then
      pass "PUSH_SYNC_SECRET length is sufficient"
    else
      fail "PUSH_SYNC_SECRET should be at least 32 characters"
    fi
  else
    fail "PUSH_SYNC_SECRET missing"
  fi

  if [[ "${APNS_USE_SANDBOX:-false}" == "true" ]]; then
    warn "APNS_USE_SANDBOX=true; TestFlight/production demo needs false"
  else
    pass "APNS_USE_SANDBOX is production-compatible"
  fi

  fail_placeholder_env FIREBASE_PROJECT_ID
  fail_placeholder_env APNS_KEY_ID
  fail_placeholder_env APNS_TEAM_ID
  fail_placeholder_env PUSH_SYNC_SECRET
}

check_aws_env() {
  local enable_https="${ENABLE_HTTPS:-true}"
  case "$enable_https" in
    true | false | TRUE | FALSE | True | False)
      ;;
    *)
      fail "ENABLE_HTTPS must be true or false"
      ;;
  esac

  require_env AWS_REGION
  require_env ECR_REPOSITORY_URI
  require_env VPC_ID
  require_env PUBLIC_SUBNET_A_ID
  require_env PUBLIC_SUBNET_B_ID

  if is_truthy "$enable_https"; then
    require_env ACM_CERTIFICATE_ARN
    if [[ -n "${ACM_CERTIFICATE_ARN:-}" && "$ACM_CERTIFICATE_ARN" != arn:aws:acm:* ]]; then
      fail "ACM_CERTIFICATE_ARN must be an ACM certificate ARN"
    fi
  else
    warn "ENABLE_HTTPS=false; AWS backend can be smoke-tested over HTTP, but iPhone release token registration still needs HTTPS later"
  fi

  if [[ -n "${RELEASE_API_BASE_URL:-}" ]]; then
    if is_truthy "$enable_https"; then
      if [[ "$RELEASE_API_BASE_URL" == https://*/api ]]; then
        pass "RELEASE_API_BASE_URL is HTTPS and ends with /api"
      else
        fail "RELEASE_API_BASE_URL should look like https://<host>/api"
      fi
    elif [[ "$RELEASE_API_BASE_URL" == http://*/api || "$RELEASE_API_BASE_URL" == https://*/api ]]; then
      pass "RELEASE_API_BASE_URL uses HTTP/HTTPS and ends with /api"
    else
      fail "RELEASE_API_BASE_URL should look like http(s)://<host>/api"
    fi
  else
    warn "RELEASE_API_BASE_URL is not set yet; CloudFormation outputs will generate it after deploy"
  fi

  if [[ -z "${SECRET_ARN_FIREBASE_SERVICE_ACCOUNT_JSON:-}" ]]; then
    warn "SECRET_ARN_FIREBASE_SERVICE_ACCOUNT_JSON not set yet; aws-push-secrets.sh will create outputs/aws/ecs-fargate/secrets.env"
  fi
  if [[ -z "${SECRET_ARN_APNS_AUTH_KEY_P8:-}" ]]; then
    warn "SECRET_ARN_APNS_AUTH_KEY_P8 not set yet; aws-push-secrets.sh will create outputs/aws/ecs-fargate/secrets.env"
  fi
  if [[ -z "${SECRET_ARN_PUSH_SYNC_SECRET:-}" ]]; then
    warn "SECRET_ARN_PUSH_SYNC_SECRET not set yet; aws-push-secrets.sh will create outputs/aws/ecs-fargate/secrets.env"
  fi

  fail_placeholder_env AWS_REGION
  fail_placeholder_env ECR_REPOSITORY_URI
  fail_placeholder_env VPC_ID
  fail_placeholder_env PUBLIC_SUBNET_A_ID
  fail_placeholder_env PUBLIC_SUBNET_B_ID
  if is_truthy "$enable_https"; then
    fail_placeholder_env ACM_CERTIFICATE_ARN
  fi
  warn_placeholder_env AWS_ROLE_TO_ASSUME
}

echo "push_live_preflight=started"

check_ios_firebase
check_android_firebase
check_ios_activity_capabilities
check_android_gradle
check_flutter_push_code

if [[ "$CHECK_BACKEND" == "true" ]]; then
  check_backend_env
else
  warn "Backend secret checks skipped by --app-only"
fi

if [[ "$CHECK_AWS" == "true" ]]; then
  check_aws_env
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo "push_live_preflight=status=failed checks=$CHECKS warnings=$WARNINGS failures=$FAILURES" >&2
  exit 1
fi

echo "push_live_preflight=status=ok checks=$CHECKS warnings=$WARNINGS failures=0"
