#!/usr/bin/env bash

set -euo pipefail

START_DOCKER=false
FAILURES=0
WARNINGS=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/aws-push-tooling-check.sh [--start-docker]

Options:
  --start-docker  Try to open Docker Desktop on macOS before checking daemon status.

Checks:
  - Homebrew availability for local AWS CLI installation guidance.
  - AWS CLI availability and current credential identity.
  - Docker CLI and Docker daemon availability for backend image build/push.

This command does not install packages and does not configure AWS credentials.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --start-docker)
      START_DOCKER=true
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

if command -v brew >/dev/null 2>&1; then
  pass "Homebrew found: $(command -v brew)"
else
  warn "Homebrew not found; install AWS CLI another way if local deploy is needed"
fi

if command -v aws >/dev/null 2>&1; then
  pass "AWS CLI found: $(command -v aws)"
  if identity="$(aws sts get-caller-identity --output json 2>&1)"; then
    account="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("Account", ""))' <<<"$identity")"
    arn="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("Arn", ""))' <<<"$identity")"
    pass "AWS credentials usable account=$account arn=$arn"
  else
    fail "AWS CLI is installed but credentials are not usable: $identity"
  fi
else
  fail "AWS CLI not found; install with: brew install awscli"
fi

if command -v docker >/dev/null 2>&1; then
  pass "Docker CLI found: $(command -v docker)"
else
  fail "Docker CLI not found; install Docker Desktop or use GitHub Actions deploy"
fi

if [[ "$START_DOCKER" == "true" ]]; then
  if command -v open >/dev/null 2>&1; then
    open -a Docker >/dev/null 2>&1 || warn "Could not open Docker Desktop"
  else
    warn "--start-docker requested but macOS open command is unavailable"
  fi
fi

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    pass "Docker daemon is running"
  else
    fail "Docker daemon is not running; start Docker Desktop or run GitHub Actions deploy"
  fi
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo "aws_push_tooling=status=failed warnings=$WARNINGS failures=$FAILURES" >&2
  exit 1
fi

echo "aws_push_tooling=status=ok warnings=$WARNINGS failures=0"
