#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"
BACKEND_DIR="$ROOT_DIR/backend"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/codex-run.sh ios
  ./scripts/codex-run.sh android
  ./scripts/codex-run.sh web
  ./scripts/codex-run.sh backend
  ./scripts/codex-run.sh doctor

Commands:
  ios      Run the Flutter app on iOS Simulator
  android  Run the Flutter app on Android device/emulator
  web      Run the Flutter app in Chrome
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

has_android_emulator() {
  if ! command -v emulator >/dev/null 2>&1; then
    return 1
  fi

  [[ -n "$(emulator -list-avds 2>/dev/null)" ]]
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
  if ! has_ios_simulator; then
    cat >&2 <<'EOF'
No available iOS Simulator runtime was found.

Next step:
1. Open Xcode
2. Go to Settings > Platforms
3. Download an iOS Simulator runtime
4. Open Simulator.app once, then rerun:
   ./scripts/codex-run.sh ios
EOF
    exit 1
  fi

  if command -v open >/dev/null 2>&1; then
    open -a Simulator >/dev/null 2>&1 || true
  fi

  run_flutter run -d ios
}

run_android() {
  if ! has_android_emulator; then
    cat >&2 <<'EOF'
No Android emulator (AVD) was found.

Next step:
1. Open Android Studio
2. Open Device Manager
3. Create and start an Android Virtual Device
4. Rerun:
   ./scripts/codex-run.sh android
EOF
    exit 1
  fi

  run_flutter run -d android
}

run_web() {
  run_flutter run -d chrome
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
