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
  ./scripts/codex-run.sh android
  ./scripts/codex-run.sh web
  ./scripts/codex-run.sh web-static
  ./scripts/codex-run.sh backend
  ./scripts/codex-run.sh doctor

Commands:
  ios      Run the Flutter app on a connected iOS device (fallback: Simulator)
  android  Run the Flutter app on Android device/emulator
  web      Run the Flutter app in Chrome
  web-static  Build web release and serve it locally on port 7357
  backend  Run the FastAPI backend with a local virtualenv
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

running_android_serial() {
  local adb_bin
  adb_bin="$(android_adb_bin)"
  if [[ -z "$adb_bin" ]]; then
    echo ""
    return
  fi

  "$adb_bin" devices | awk '/^emulator-[0-9]+\tdevice$/ {print $1; exit}'
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

run_ios() {
  local device_id
  local device_name
  local destination_issue
  local backend_running
  local lan_ip
  local api_define=""
  device_id="$(pick_ios_device)"
  device_name="$(pick_ios_device_name)"
  backend_running="$(backend_is_running)"
  lan_ip="$(local_ipv4)"

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
    if [[ "$backend_running" == "1" && -n "$lan_ip" ]]; then
      api_define=" --dart-define=API_BASE_URL=http://$lan_ip:8000/api"
      echo "Using local backend for iOS device: http://$lan_ip:8000/api"
    fi
    run_flutter run -d "$device_id" --dart-define=APP_ENV=local$api_define
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
  if [[ "$backend_running" == "1" ]]; then
    api_define=" --dart-define=API_BASE_URL=http://localhost:8000/api"
    echo "Using local backend for iOS simulator: http://localhost:8000/api"
  fi
  run_flutter run -d ios --dart-define=APP_ENV=local$api_define
}

run_android() {
  local java_home
  local serial
  local adb_bin
  local backend_running
  local api_define=""

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
  backend_running="$(backend_is_running)"

  if [[ -n "$adb_bin" ]]; then
    echo "Uninstalling existing Android app: $ANDROID_APPLICATION_ID"
    "$adb_bin" -s "$serial" uninstall "$ANDROID_APPLICATION_ID" >/dev/null 2>&1 || true
  fi

  (
    export JAVA_HOME="$java_home"
    export ANDROID_SDK_ROOT="$(android_sdk_root)"
    cd "$APP_DIR"
    local flutter
    flutter="$(flutter_cmd)"
    if [[ -z "$flutter" ]]; then
      echo "Flutter or FVM is not installed or not on PATH." >&2
      exit 1
    fi
    if [[ "$backend_running" == "1" ]]; then
      api_define=" --dart-define=API_BASE_URL=http://10.0.2.2:8000/api"
      echo "Using local backend for Android: http://10.0.2.2:8000/api"
    fi
    eval "$flutter pub get"
    eval "$flutter run -d $serial --dart-define=APP_ENV=local$api_define"
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
    eval "$flutter build web --release"
    cd build/web
    echo "Serving Flutter web release build at http://localhost:7357"
    python3 -m http.server 7357
  )
}

run_backend() {
  require_cmd python3

  (
    cd "$BACKEND_DIR"

    if [[ ! -d ".venv" ]]; then
      python3 -m venv .venv
    fi

    # shellcheck disable=SC1091
    source .venv/bin/activate
    pip install -e ".[dev]"
    uvicorn kbo_fans_backend.main:app --reload
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
      run_ios
      ;;
    android)
      run_android
      ;;
    web)
      run_web
      ;;
    web-static)
      run_web_static
      ;;
    backend)
      run_backend
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
