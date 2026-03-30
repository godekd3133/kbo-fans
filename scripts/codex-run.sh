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
  ./scripts/codex-run.sh backend
  ./scripts/codex-run.sh doctor

Commands:
  ios      Run the Flutter app on iOS Simulator
  android  Run the Flutter app on Android device/emulator
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
  if command -v open >/dev/null 2>&1; then
    open -a Simulator >/dev/null 2>&1 || true
  fi

  run_flutter run -d ios
}

run_android() {
  run_flutter run -d android
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
