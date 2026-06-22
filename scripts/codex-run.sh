#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"
BACKEND_DIR="$ROOT_DIR/backend"
DEFAULT_ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
DEFAULT_ANDROID_AVD="Medium_Phone_API_36"
ANDROID_APPLICATION_ID="com.kbofans.kbo_fans"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/codex-run.sh ios
  ./scripts/codex-run.sh ios-debug
  ./scripts/codex-run.sh ios-profile
  ./scripts/codex-run.sh ios-local-release
  ./scripts/codex-run.sh ios-release
  ./scripts/codex-run.sh android
  ./scripts/codex-run.sh android-release
  ./scripts/codex-run.sh web
  ./scripts/codex-run.sh web-dev
  ./scripts/codex-run.sh web-static
  ./scripts/codex-run.sh web-release
  ./scripts/codex-run.sh backend
  ./scripts/codex-run.sh release-api-health
  ./scripts/codex-run.sh push-live-preflight [--env-file /path/to/kbo-fans-aws.env] [--aws]
  ./scripts/codex-run.sh push-readiness
  ./scripts/codex-run.sh aws-push-secrets
  ./scripts/codex-run.sh aws-push-task-defs
  ./scripts/codex-run.sh aws-push-deploy-check [--skip-aws]
  ./scripts/codex-run.sh aws-push-image [--dry-run]
  ./scripts/codex-run.sh aws-push-cloudformation [--dry-run]
  ./scripts/codex-run.sh aws-push-stack-outputs
  ./scripts/codex-run.sh aws-push-demo-deploy [--dry-run]
  ./scripts/codex-run.sh aws-push-tooling
  ./scripts/codex-run.sh aws-github-oidc-role [--env-file /path/to/kbo-fans-aws.env] [--dry-run]
  ./scripts/codex-run.sh push-demo-env-bootstrap [--output /tmp/kbo-fans-aws.env] [--repo owner/repo] [--force]
  ./scripts/codex-run.sh push-demo-setup-status [--env-file /tmp/kbo-fans-aws.env] [--repo owner/repo]
  ./scripts/codex-run.sh push-demo-audit [--env-file /path/to/kbo-fans-aws.env]
  ./scripts/codex-run.sh github-push-secrets --env-file /path/to/kbo-fans-aws.env [--apply]
  ./scripts/codex-run.sh github-push-demo-run [--dry-run true] [--watch]
  ./scripts/codex-run.sh github-push-test-notification-run [--topic baseball_info_ALL] [--watch]
  ./scripts/codex-run.sh github-push-receipt-status-run [--expect-receipt] [--watch]
  ./scripts/codex-run.sh doctor

Commands:
  ios      Run the Flutter app on a connected iOS device in profile mode (fallback: Simulator)
  ios-debug    Run the Flutter app on a connected iOS device in debug mode
  ios-profile  Run the Flutter app on a connected iPhone in profile mode
  ios-local-release  Run a release-mode local build on a connected iPhone
  ios-release  Run the Flutter app on a connected iPhone in production release mode
  android  Run the Flutter app on Android device/emulator
  android-release  Run Android in release mode with backend API data
  web      Build web release with backend API data and serve it locally
  web-dev  Run the Flutter app in Chrome for a debug session
  web-static  Build web release and serve it locally on port 7357
  web-release  Build web release with backend API data and serve it locally
  backend  Run the FastAPI backend with a local virtualenv on a LAN-reachable host
  release-api-health  Check the production API DNS/TLS and release-critical endpoints
  push-live-preflight  Check local Firebase/APNs/Live Activity/AWS prerequisites
  push-readiness  Check production push/Live Activity backend readiness
  aws-push-secrets  Create or update AWS Secrets Manager values for push deployment
  aws-push-task-defs  Render AWS ECS task definitions and IAM policy for push/Live Activity demo deployment
  aws-push-deploy-check  Validate AWS push deployment env, rendered JSON, and AWS resources
  aws-push-image  Build backend Docker image and push it to ECR
  aws-push-cloudformation  Deploy ALB/EFS/ECS/IAM CloudFormation stack for the push demo
  aws-push-stack-outputs  Export CloudFormation ApiBaseUrl for release API_BASE_URL
  aws-push-demo-deploy  Run the secret/image/stack/output/readiness pipeline
  aws-push-tooling  Check local AWS CLI and Docker daemon availability
  aws-github-oidc-role  Create the GitHub Actions OIDC AWS role for push deploy
  push-demo-env-bootstrap  Create a local push demo env starter file
  push-demo-setup-status  Create/check the local push demo setup status without deploying
  push-demo-audit  Audit iPhone-only push demo readiness without deploying
  github-push-secrets  Validate or upload GitHub Actions secrets/variables for push deploy
  github-push-demo-run  Dispatch the GitHub Actions push demo deploy workflow
  github-push-test-notification-run  Dispatch the GitHub Actions push test notification workflow
  github-push-receipt-status-run  Dispatch the GitHub Actions push receipt status workflow
  doctor   Check local Flutter/FVM and Python prerequisites
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

has_ios_simulator() {
  if ! command -v xcrun >/dev/null 2>&1; then
    return 1
  fi

  xcrun simctl list devices available 2>/dev/null | grep -q "("
}

ios_destination_issue() {
  local device_id="$1"

  if [[ -z "$device_id" ]]; then
    echo ""
    return
  fi

  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo ""
    return
  fi

  local output
  output="$(
    cd "$APP_DIR/ios" && xcodebuild -workspace Runner.xcworkspace -scheme Runner -showdestinations 2>&1 || true
  )"

  if [[ -z "$output" ]]; then
    echo ""
    return
  fi

  printf '%s\n' "$output" | python3 - "$device_id" <<'PY'
import re
import sys

device_id = sys.argv[1]
text = sys.stdin.read()
for line in text.splitlines():
    if device_id not in line:
        continue
    match = re.search(r"error:([^}]+)", line)
    if match:
        print(match.group(1).strip())
        raise SystemExit(0)

print("")
PY
}

pick_ios_device() {
  local flutter
  flutter="$(flutter_cmd)"

  if [[ -z "$flutter" ]]; then
    echo ""
    return
  fi

  local devices_json
  devices_json="$(
    cd "$APP_DIR" && eval "$flutter devices --machine" 2>/dev/null || true
  )"

  if [[ -z "$devices_json" ]]; then
    echo ""
    return
  fi

  local tmp_json
  tmp_json="$(mktemp)"
  printf '%s' "$devices_json" > "$tmp_json"

  python3 - "$tmp_json" <<'PY'
import json
import sys

path = sys.argv[1]
raw = open(path, "r", encoding="utf-8").read().strip()
if not raw:
    print("")
    raise SystemExit(0)

try:
    devices = json.loads(raw)
except Exception:
    print("")
    raise SystemExit(0)

ios_devices = [d for d in devices if d.get("targetPlatform") == "ios"]
physical = [
    d for d in ios_devices
    if d.get("sdk", "").startswith("iOS")
    and d.get("emulator") is False
    and d.get("id") not in {"ios", "iphone"}
]
if physical:
    print(physical[0].get("id", ""))
    raise SystemExit(0)

simulators = [
    d for d in ios_devices
    if d.get("id") in {"ios", "iphone"} or d.get("emulator") is True
]
if simulators:
    print(simulators[0].get("id", "ios"))
    raise SystemExit(0)

print("")
PY
  local status=$?
  rm -f "$tmp_json"
  return $status
}

pick_ios_device_name() {
  local flutter
  flutter="$(flutter_cmd)"

  if [[ -z "$flutter" ]]; then
    echo ""
    return
  fi

  local devices_json
  devices_json="$(
    cd "$APP_DIR" && eval "$flutter devices --machine" 2>/dev/null || true
  )"

  if [[ -z "$devices_json" ]]; then
    echo ""
    return
  fi

  local tmp_json
  tmp_json="$(mktemp)"
  printf '%s' "$devices_json" > "$tmp_json"

  python3 - "$tmp_json" <<'PY'
import json
import sys

path = sys.argv[1]
raw = open(path, "r", encoding="utf-8").read().strip()
if not raw:
    print("")
    raise SystemExit(0)

try:
    devices = json.loads(raw)
except Exception:
    print("")
    raise SystemExit(0)

ios_devices = [d for d in devices if d.get("targetPlatform") == "ios"]
physical = [
    d for d in ios_devices
    if d.get("sdk", "").startswith("iOS")
    and d.get("emulator") is False
    and d.get("id") not in {"ios", "iphone"}
]
if physical:
    print(physical[0].get("name", ""))
    raise SystemExit(0)

simulators = [
    d for d in ios_devices
    if d.get("id") in {"ios", "iphone"} or d.get("emulator") is True
]
if simulators:
    print(simulators[0].get("name", "iOS Simulator"))
    raise SystemExit(0)

print("")
PY
  local status=$?
  rm -f "$tmp_json"
  return $status
}

has_android_emulator() {
  local emulator_bin
  emulator_bin="$(android_emulator_bin)"
  if [[ -z "$emulator_bin" ]]; then
    return 1
  fi

  [[ -n "$("$emulator_bin" -list-avds 2>/dev/null)" ]]
}

android_sdk_root() {
  if [[ -n "${ANDROID_SDK_ROOT:-}" && -d "${ANDROID_SDK_ROOT:-}" ]]; then
    echo "$ANDROID_SDK_ROOT"
    return
  fi

  if [[ -n "${ANDROID_HOME:-}" && -d "${ANDROID_HOME:-}" ]]; then
    echo "$ANDROID_HOME"
    return
  fi

  if [[ -d "$DEFAULT_ANDROID_SDK_ROOT" ]]; then
    echo "$DEFAULT_ANDROID_SDK_ROOT"
    return
  fi

  echo ""
}

android_adb_bin() {
  local sdk_root
  sdk_root="$(android_sdk_root)"
  if [[ -n "$sdk_root" && -x "$sdk_root/platform-tools/adb" ]]; then
    echo "$sdk_root/platform-tools/adb"
    return
  fi

  command -v adb 2>/dev/null || true
}

android_emulator_bin() {
  local sdk_root
  sdk_root="$(android_sdk_root)"
  if [[ -n "$sdk_root" && -x "$sdk_root/emulator/emulator" ]]; then
    echo "$sdk_root/emulator/emulator"
    return
  fi

  command -v emulator 2>/dev/null || true
}

android_java_home() {
  if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
    echo "$JAVA_HOME"
    return
  fi

  local android_studio_jbr
  android_studio_jbr="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  if [[ -x "$android_studio_jbr/bin/java" ]]; then
    echo "$android_studio_jbr"
    return
  fi

  if command -v /usr/libexec/java_home >/dev/null 2>&1; then
    /usr/libexec/java_home -v 17 2>/dev/null || true
    return
  fi

  echo ""
}

configure_android_gradle_launch() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    return
  fi

  local launch_opt="-Djdk.lang.Process.launchMechanism=FORK"
  case " ${GRADLE_OPTS:-} " in
    *" $launch_opt "*)
      ;;
    *)
      export GRADLE_OPTS="${GRADLE_OPTS:-} $launch_opt"
      ;;
  esac
}

running_android_serial() {
  local adb_bin
  adb_bin="$(android_adb_bin)"
  if [[ -z "$adb_bin" ]]; then
    echo ""
    return
  fi

  "$adb_bin" devices | awk '
    /^[^[:space:]]+\tdevice$/ && $1 !~ /^emulator-/ && physical == "" {physical = $1}
    /^[^[:space:]]+\tdevice$/ && $1 ~ /^emulator-/ && emulator == "" {emulator = $1}
    END {
      if (physical != "") print physical
      else if (emulator != "") print emulator
    }
  '
}

android_serial_is_emulator() {
  local serial="$1"
  local adb_bin="$2"

  if [[ "$serial" == emulator-* ]]; then
    return 0
  fi

  if [[ -n "$adb_bin" ]]; then
    [[ "$("$adb_bin" -s "$serial" shell getprop ro.kernel.qemu 2>/dev/null | tr -d '\r')" == "1" ]]
    return
  fi

  return 1
}

pick_android_avd() {
  local emulator_bin
  emulator_bin="$(android_emulator_bin)"
  if [[ -z "$emulator_bin" ]]; then
    echo ""
    return
  fi

  local avds
  avds="$("$emulator_bin" -list-avds 2>/dev/null || true)"
  if [[ -z "$avds" ]]; then
    echo ""
    return
  fi

  if printf '%s\n' "$avds" | rg -x "$DEFAULT_ANDROID_AVD" >/dev/null 2>&1; then
    echo "$DEFAULT_ANDROID_AVD"
    return
  fi

  printf '%s\n' "$avds" | head -n 1
}

wait_for_android_boot() {
  local adb_bin="$1"
  local serial="$2"
  local attempts="${3:-90}"

  local i
  for ((i = 0; i < attempts; i++)); do
    if [[ "$("$adb_bin" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
      return 0
    fi
    sleep 2
  done

  return 1
}

ensure_android_runtime() {
  local adb_bin
  local emulator_bin
  local serial
  local avd_name

  adb_bin="$(android_adb_bin)"
  emulator_bin="$(android_emulator_bin)"

  if [[ -z "$adb_bin" || -z "$emulator_bin" ]]; then
    cat >&2 <<'EOF'
Android SDK tools were not found.

Expected:
- ~/Library/Android/sdk/platform-tools/adb
- ~/Library/Android/sdk/emulator/emulator

Next step:
1. Install Android Studio
2. Install Android SDK Platform-Tools and Emulator
3. Rerun:
   ./scripts/codex-run.sh android
EOF
    exit 1
  fi

  serial="$(running_android_serial)"
  if [[ -n "$serial" ]]; then
    echo "$serial"
    return
  fi

  avd_name="$(pick_android_avd)"
  if [[ -z "$avd_name" ]]; then
    cat >&2 <<'EOF'
No Android emulator (AVD) was found.

Next step:
1. Open Android Studio
2. Open Device Manager
3. Create an Android Virtual Device
4. Rerun:
   ./scripts/codex-run.sh android
EOF
    exit 1
  fi

  echo "Launching Android emulator: $avd_name"
  "$emulator_bin" -avd "$avd_name" >/tmp/kbo-fans-android-emulator.log 2>&1 &

  local i
  for ((i = 0; i < 90; i++)); do
    serial="$(running_android_serial)"
    if [[ -n "$serial" ]]; then
      break
    fi
    sleep 2
  done

  if [[ -z "$serial" ]]; then
    echo "Android emulator did not appear in adb devices." >&2
    exit 1
  fi

  if ! wait_for_android_boot "$adb_bin" "$serial"; then
    echo "Android emulator boot did not complete in time." >&2
    exit 1
  fi

  echo "$serial"
}

flutter_cmd() {
  if command -v fvm >/dev/null 2>&1; then
    echo "fvm flutter"
    return
  fi

  if command -v flutter >/dev/null 2>&1; then
    echo "flutter"
    return
  fi

  echo ""
}

local_ipv4() {
  ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true
}

backend_is_running() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.settimeout(0.5)
try:
    s.connect(("127.0.0.1", 8000))
except Exception:
    print("0")
else:
    print("1")
finally:
    s.close()
PY
}

backend_health_url() {
  local api_url="$1"
  curl -fsS --max-time 2 "$api_url/health" >/dev/null 2>&1
}

local_backend_api_url_for_host() {
  local host="$1"
  local port

  for port in 8000 8001; do
    local api_url="http://$host:$port/api"
    if backend_health_url "$api_url"; then
      echo "$api_url"
      return 0
    fi
  done

  return 1
}

local_backend_api_url_for_localhost() {
  if [[ -n "${API_BASE_URL:-}" ]]; then
    echo "$API_BASE_URL"
    return 0
  fi

  local_backend_api_url_for_host "localhost" ||
    local_backend_api_url_for_host "127.0.0.1"
}

local_backend_api_url_for_lan() {
  if [[ -n "${API_BASE_URL:-}" ]]; then
    echo "$API_BASE_URL"
    return 0
  fi

  local lan_ip
  lan_ip="$(local_ipv4)"
  if [[ -z "$lan_ip" ]]; then
    return 1
  fi

  local_backend_api_url_for_host "$lan_ip"
}

local_backend_api_url_for_android_emulator() {
  if [[ -n "${API_BASE_URL:-}" ]]; then
    echo "$API_BASE_URL"
    return 0
  fi

  local port
  for port in 8000 8001; do
    if backend_health_url "http://127.0.0.1:$port/api"; then
      echo "http://10.0.2.2:$port/api"
      return 0
    fi
  done

  return 1
}

run_flutter() {
  local flutter
  flutter="$(flutter_cmd)"

  if [[ -z "$flutter" ]]; then
    echo "Flutter or FVM is not installed or not on PATH." >&2
    exit 1
  fi

  (
    cd "$APP_DIR"
    eval "$flutter pub get"
    eval "$flutter $*"
  )
}

release_api_base_url() {
  if [[ -n "${RELEASE_API_BASE_URL:-}" ]]; then
    echo "$RELEASE_API_BASE_URL"
    return
  fi
  if [[ -n "${API_BASE_URL:-}" ]]; then
    echo "$API_BASE_URL"
    return
  fi

  local stack_env="$ROOT_DIR/outputs/aws/cloudformation/stack.env"
  local line
  if [[ -f "$stack_env" ]]; then
    line="$(grep -E '^export RELEASE_API_BASE_URL=' "$stack_env" | tail -n 1 || true)"
    if [[ -n "$line" ]]; then
      echo "${line#export RELEASE_API_BASE_URL=}"
      return
    fi
  fi

  echo "https://api.kbofans.com/api"
}

run_release_api_health() {
  "$ROOT_DIR/scripts/release-api-health-check.sh" "$(release_api_base_url)"
}

run_push_readiness() {
  bash "$ROOT_DIR/scripts/push-readiness-check.sh" "$(release_api_base_url)"
}

run_push_live_preflight() {
  bash "$ROOT_DIR/scripts/push-live-preflight.sh" "$@"
}

run_aws_push_task_definitions() {
  bash "$ROOT_DIR/scripts/aws-push-task-definitions.sh"
}

run_aws_push_secrets() {
  bash "$ROOT_DIR/scripts/aws-push-secrets.sh"
}

run_aws_push_deploy_check() {
  bash "$ROOT_DIR/scripts/aws-push-deploy-check.sh" "$@"
}

run_aws_push_image() {
  bash "$ROOT_DIR/scripts/aws-push-image.sh" "$@"
}

run_aws_push_cloudformation() {
  bash "$ROOT_DIR/scripts/aws-push-cloudformation.sh" "$@"
}

run_aws_push_stack_outputs() {
  bash "$ROOT_DIR/scripts/aws-push-stack-outputs.sh" "$@"
}

run_aws_push_demo_deploy() {
  bash "$ROOT_DIR/scripts/aws-push-demo-deploy.sh" "$@"
}

run_aws_push_tooling() {
  bash "$ROOT_DIR/scripts/aws-push-tooling-check.sh" "$@"
}

run_aws_github_oidc_role() {
  bash "$ROOT_DIR/scripts/aws-github-oidc-role.sh" "$@"
}

run_push_demo_env_bootstrap() {
  bash "$ROOT_DIR/scripts/push-demo-env-bootstrap.sh" "$@"
}

run_push_demo_setup_status() {
  bash "$ROOT_DIR/scripts/push-demo-setup-status.sh" "$@"
}

run_push_demo_audit() {
  bash "$ROOT_DIR/scripts/push-demo-readiness-audit.sh" "$@"
}

run_github_push_secrets() {
  bash "$ROOT_DIR/scripts/github-push-secrets.sh" "$@"
}

run_github_push_demo_run() {
  bash "$ROOT_DIR/scripts/github-push-demo-run.sh" "$@"
}

run_github_push_test_notification_run() {
  bash "$ROOT_DIR/scripts/github-push-test-notification-run.sh" "$@"
}

run_github_push_receipt_status_run() {
  bash "$ROOT_DIR/scripts/github-push-receipt-status-run.sh" "$@"
}

backend_api_define() {
  local app_env="$1"
  local api_define=" --dart-define=USE_BACKEND_API=true"

  if [[ "$app_env" == "release" ]]; then
    api_define="$api_define --dart-define=API_BASE_URL=$(release_api_base_url)"
  fi

  echo "$api_define"
}

run_ios() {
  local flutter_mode="${1:-profile}"
  local app_env="${2:-local}"
  local data_mode="${3:-api}"
  local device_id
  local device_name
  local destination_issue
  local api_define=""
  local release_api_url=""
  local local_api_url=""
  device_id="$(pick_ios_device)"
  device_name="$(pick_ios_device_name)"

  if [[ "$data_mode" == "api" && "$app_env" == "release" ]]; then
    release_api_url="$(release_api_base_url)"
    run_release_api_health
    api_define=" --dart-define=USE_BACKEND_API=true --dart-define=API_BASE_URL=$release_api_url"
  elif [[ "$data_mode" == "direct" ]]; then
    api_define="$(backend_api_define "$app_env")"
  fi

  if [[ -n "$device_id" && "$device_id" != "ios" && "$device_id" != "iphone" ]]; then
    destination_issue="$(ios_destination_issue "$device_id")"
    if [[ -n "$destination_issue" ]]; then
      cat >&2 <<EOF
Connected iOS device detected but Xcode cannot build for it yet.

Device:
  ${device_name:-$device_id} ($device_id)

Reason:
  $destination_issue

Next step:
1. Open Xcode
2. Go to Settings > Components
3. Install the required iOS platform/device support for the device OS version
4. Keep the device unlocked and rerun:
   ./scripts/codex-run.sh ios
EOF
      exit 1
    fi

    echo "Running on connected iOS device: ${device_name:-$device_id} ($device_id)"
    echo "Using ${flutter_mode} mode for iOS device."
    if [[ "$app_env" != "release" ]]; then
      local_api_url="$(local_backend_api_url_for_lan || true)"
      if [[ -n "$local_api_url" ]]; then
        api_define=" --dart-define=USE_BACKEND_API=true --dart-define=API_BASE_URL=$local_api_url"
        echo "Using local backend for iOS device: $local_api_url"
      else
        cat >&2 <<'EOF'
No LAN-reachable local backend was found for the connected iOS device.

Start the LAN-reachable backend first:
  ./scripts/codex-run.sh backend

Or provide an explicit API URL:
  API_BASE_URL=http://<mac-lan-ip>:8000/api ./scripts/codex-run.sh ios
EOF
        exit 1
      fi
    elif [[ "$data_mode" == "api" ]]; then
      echo "Using release API for iOS device: $release_api_url"
    else
      echo "Using release API for iOS device: $(release_api_base_url)"
    fi
    run_flutter run --"$flutter_mode" -d "$device_id" --dart-define=APP_ENV="$app_env"$api_define
    return
  fi

  if ! has_ios_simulator; then
    cat >&2 <<'EOF'
No connected iOS device or available iOS Simulator runtime was found.

Next step:
1. Connect and unlock an iPhone/iPad with Developer Mode enabled
2. Or open Xcode > Settings > Platforms and install an iOS Simulator runtime
3. If using a simulator, open Simulator.app once
4. Rerun:
   ./scripts/codex-run.sh ios
EOF
    exit 1
  fi

  if command -v open >/dev/null 2>&1; then
    open -a Simulator >/dev/null 2>&1 || true
  fi

  echo "Running on iOS Simulator"
  if [[ "$app_env" != "release" ]]; then
    local_api_url="$(local_backend_api_url_for_localhost || true)"
    if [[ -n "$local_api_url" ]]; then
      api_define=" --dart-define=USE_BACKEND_API=true --dart-define=API_BASE_URL=$local_api_url"
      echo "Using local backend for iOS simulator: $local_api_url"
    else
      cat >&2 <<'EOF'
No local backend was found for the iOS Simulator.

Start the backend first:
  ./scripts/codex-run.sh backend

Or provide an explicit API URL:
  API_BASE_URL=http://localhost:8000/api ./scripts/codex-run.sh ios
EOF
      exit 1
    fi
  elif [[ "$data_mode" == "api" ]]; then
    echo "Using release API for iOS simulator: $release_api_url"
  else
    echo "Using release API for iOS simulator: $(release_api_base_url)"
  fi
  run_flutter run -d ios --dart-define=APP_ENV="$app_env"$api_define
}

run_android() {
  local java_home
  local serial
  local adb_bin
  local api_define=""
  local local_api_url

  java_home="$(android_java_home)"
  if [[ -z "$java_home" ]]; then
    cat >&2 <<'EOF'
Java 17 runtime was not found for Android builds.

Next step:
1. Install Android Studio (recommended), or
2. Install JDK 17 and export JAVA_HOME
3. Rerun:
   ./scripts/codex-run.sh android
EOF
    exit 1
  fi

  serial="$(ensure_android_runtime)"
  adb_bin="$(android_adb_bin)"
  echo "Running on Android device/emulator: $serial"

  if [[ -n "$adb_bin" ]]; then
    echo "Uninstalling existing Android app: $ANDROID_APPLICATION_ID"
    "$adb_bin" -s "$serial" uninstall "$ANDROID_APPLICATION_ID" >/dev/null 2>&1 || true
  fi

  (
    export JAVA_HOME="$java_home"
    export ANDROID_SDK_ROOT="$(android_sdk_root)"
    configure_android_gradle_launch
    cd "$APP_DIR"
    local flutter
    flutter="$(flutter_cmd)"
    if [[ -z "$flutter" ]]; then
      echo "Flutter or FVM is not installed or not on PATH." >&2
      exit 1
    fi
    local_api_url="$(local_backend_api_url_for_android_emulator || true)"
    if [[ -z "$local_api_url" ]]; then
      cat >&2 <<'EOF'
No local backend was found for Android.

Start the backend first:
  ./scripts/codex-run.sh backend

Or provide an explicit API URL:
  API_BASE_URL=http://10.0.2.2:8000/api ./scripts/codex-run.sh android
EOF
      exit 1
    fi
    api_define=" --dart-define=USE_BACKEND_API=true --dart-define=API_BASE_URL=$local_api_url"
    echo "Using local backend for Android: $local_api_url"
    echo "Cleaning Flutter build outputs"
    eval "$flutter clean"
    eval "$flutter pub get"
    eval "$flutter run --uninstall-first -d $serial --dart-define=APP_ENV=local$api_define"
  )
}

run_android_release() {
  local java_home
  local serial
  local adb_bin

  java_home="$(android_java_home)"
  if [[ -z "$java_home" ]]; then
    cat >&2 <<'EOF'
Java 17 runtime was not found for Android builds.

Next step:
1. Install Android Studio (recommended), or
2. Install JDK 17 and export JAVA_HOME
3. Rerun:
   ./scripts/codex-run.sh android-release
EOF
    exit 1
  fi

  serial="$(ensure_android_runtime)"
  adb_bin="$(android_adb_bin)"
  echo "Running Android release with backend API data"

  if [[ -n "$adb_bin" ]]; then
    "$adb_bin" -s "$serial" uninstall "$ANDROID_APPLICATION_ID" >/dev/null 2>&1 || true
  fi

  (
    export JAVA_HOME="$java_home"
    export ANDROID_SDK_ROOT="$(android_sdk_root)"
    configure_android_gradle_launch
    cd "$APP_DIR"
    local flutter
    flutter="$(flutter_cmd)"
    if [[ -z "$flutter" ]]; then
      echo "Flutter or FVM is not installed or not on PATH." >&2
      exit 1
    fi
    eval "$flutter clean"
    eval "$flutter pub get"
    eval "$flutter run --release --uninstall-first -d $serial --dart-define=APP_ENV=release$(backend_api_define release)"
  )
}

run_web() {
  run_flutter run -d chrome
}

run_web_static() {
  local flutter
  flutter="$(flutter_cmd)"

  if [[ -z "$flutter" ]]; then
    echo "Flutter or FVM is not installed or not on PATH." >&2
    exit 1
  fi

  require_cmd python3

  (
    cd "$APP_DIR"
    eval "$flutter pub get"
    eval "$flutter build web --release --dart-define=USE_BACKEND_API=true"
    cd build/web
    echo "Serving Flutter web release build at http://localhost:7357"
    python3 -m http.server 7357
  )
}

run_web_release_static() {
  local flutter

  flutter="$(flutter_cmd)"

  if [[ -z "$flutter" ]]; then
    echo "Flutter or FVM is not installed or not on PATH." >&2
    exit 1
  fi

  require_cmd python3

  (
    cd "$APP_DIR"
    eval "$flutter pub get"
    eval "$flutter build web --release --dart-define=APP_ENV=release$(backend_api_define release)"
    cd build/web
    echo "Serving Flutter web release build at http://localhost:7357"
    echo "Using backend API web release data mode"
    python3 -m http.server 7357
  )
}

run_backend() {
  require_cmd python3
  local backend_host="${BACKEND_HOST:-0.0.0.0}"
  local backend_port="${BACKEND_PORT:-8000}"

  (
    cd "$BACKEND_DIR"

    if [[ ! -d ".venv" ]]; then
      python3 -m venv .venv
    fi

    # shellcheck disable=SC1091
    source .venv/bin/activate
    pip install -e ".[dev]"
    echo "Starting FastAPI backend on ${backend_host}:${backend_port}"
    uvicorn kbo_fans_backend.main:app --host "$backend_host" --port "$backend_port" --reload
  )
}

run_doctor() {
  echo "[Flutter]"
  if command -v fvm >/dev/null 2>&1; then
    echo "fvm: $(command -v fvm)"
    (
      cd "$APP_DIR"
      fvm flutter --version
    )
  elif command -v flutter >/dev/null 2>&1; then
    echo "flutter: $(command -v flutter)"
    flutter --version
  else
    echo "flutter/fvm not found"
  fi

  echo
  echo "[Devices]"
  if has_ios_simulator; then
    echo "iOS simulator runtime: available"
  else
    echo "iOS simulator runtime: not installed"
  fi

  if has_android_emulator; then
    echo "Android emulator (AVD): available"
    echo "android sdk: $(android_sdk_root)"
    echo "android adb: $(android_adb_bin)"
    echo "android emulator: $(android_emulator_bin)"
    echo "android java: $(android_java_home)"
  else
    echo "Android emulator (AVD): not installed"
  fi

  echo
  echo "[Python]"
  if command -v python3 >/dev/null 2>&1; then
    echo "python3: $(command -v python3)"
    python3 --version
  else
    echo "python3 not found"
  fi
}

main() {
  local command="${1:-}"

  case "$command" in
    ios)
      run_ios profile
      ;;
    ios-debug)
      run_ios debug
      ;;
    ios-profile)
      run_ios profile
      ;;
    ios-local-release)
      run_ios release local direct
      ;;
    ios-release)
      run_ios release release
      ;;
    android)
      run_android
      ;;
    android-release)
      run_android_release
      ;;
    web)
      run_web_release_static
      ;;
    web-dev)
      run_web
      ;;
    web-static)
      run_web_static
      ;;
    web-release)
      run_web_release_static
      ;;
    backend)
      run_backend
      ;;
    release-api-health)
      run_release_api_health
      ;;
    push-live-preflight)
      run_push_live_preflight "${@:2}"
      ;;
    push-readiness)
      run_push_readiness
      ;;
    aws-push-secrets)
      run_aws_push_secrets
      ;;
    aws-push-task-defs)
      run_aws_push_task_definitions
      ;;
    aws-push-deploy-check)
      run_aws_push_deploy_check "${@:2}"
      ;;
    aws-push-image)
      run_aws_push_image "${@:2}"
      ;;
    aws-push-cloudformation)
      run_aws_push_cloudformation "${@:2}"
      ;;
    aws-push-stack-outputs)
      run_aws_push_stack_outputs "${@:2}"
      ;;
    aws-push-demo-deploy)
      run_aws_push_demo_deploy "${@:2}"
      ;;
    aws-push-tooling)
      run_aws_push_tooling "${@:2}"
      ;;
    aws-github-oidc-role)
      run_aws_github_oidc_role "${@:2}"
      ;;
    push-demo-env-bootstrap)
      run_push_demo_env_bootstrap "${@:2}"
      ;;
    push-demo-setup-status)
      run_push_demo_setup_status "${@:2}"
      ;;
    push-demo-audit)
      run_push_demo_audit "${@:2}"
      ;;
    github-push-secrets)
      run_github_push_secrets "${@:2}"
      ;;
    github-push-demo-run)
      run_github_push_demo_run "${@:2}"
      ;;
    github-push-test-notification-run)
      run_github_push_test_notification_run "${@:2}"
      ;;
    github-push-receipt-status-run)
      run_github_push_receipt_status_run "${@:2}"
      ;;
    doctor)
      run_doctor
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
