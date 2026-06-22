#!/usr/bin/env bash

set -euo pipefail

REPO=""
REF=""
BASE_URL=""
TOPIC="${PUSH_TEST_TOPIC:-baseball_info_ALL}"
TOKEN="${PUSH_TEST_TOKEN:-}"
TITLE="${PUSH_TEST_TITLE:-KBO Fans Test}"
BODY="${PUSH_TEST_BODY:-Push delivery test}"
ALLOW_INSECURE="${ALLOW_INSECURE_PUSH_TEST:-true}"
WATCH=false

usage() {
  cat <<'EOF'
Usage:
  ./scripts/github-push-test-notification-run.sh --topic baseball_info_ALL --watch
  ./scripts/github-push-test-notification-run.sh --token <fcm-token> --watch

Options:
  --repo <owner/repo>       Override GitHub repository. Default: gh repo view.
  --ref <branch-or-sha>     Workflow ref. Default: current git branch.
  --base-url <url>          API base URL. Empty uses RELEASE_API_BASE_URL variable in GitHub Actions.
  --topic <topic>           FCM topic target. Mutually exclusive with --token.
  --token <token>           FCM device token target. Mutually exclusive with --topic.
  --title <text>            Notification title.
  --body <text>             Notification body.
  --allow-insecure <bool>   Allow temporary HTTP smoke backend. Default: true.
  --watch                   Wait for the triggered workflow run.

This helper never prints PUSH_SYNC_SECRET or device tokens. The workflow uses
GitHub Actions secrets to call scripts/push-test-notification.sh.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

resolve_repo() {
  if [[ -n "$REPO" ]]; then
    echo "$REPO"
    return
  fi
  gh repo view --json nameWithOwner --jq .nameWithOwner
}

resolve_ref() {
  if [[ -n "$REF" ]]; then
    echo "$REF"
    return
  fi
  git branch --show-current
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --ref)
      REF="${2:-}"
      shift 2
      ;;
    --base-url)
      BASE_URL="${2:-}"
      shift 2
      ;;
    --topic)
      TOPIC="${2:-}"
      TOKEN=""
      shift 2
      ;;
    --token)
      TOKEN="${2:-}"
      TOPIC=""
      shift 2
      ;;
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --body)
      BODY="${2:-}"
      shift 2
      ;;
    --allow-insecure)
      ALLOW_INSECURE="${2:-}"
      shift 2
      ;;
    --watch)
      WATCH=true
      shift
      ;;
    -h | --help)
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

case "$ALLOW_INSECURE" in
  true | false) ;;
  *)
    echo "--allow-insecure must be true or false." >&2
    exit 2
    ;;
esac

if [[ -n "$TOPIC" && -n "$TOKEN" ]]; then
  echo "Use only one of --topic or --token." >&2
  exit 2
fi
if [[ -z "$TOPIC" && -z "$TOKEN" ]]; then
  echo "One target is required: --topic or --token." >&2
  exit 2
fi

require_cmd gh
require_cmd git
gh auth status >/dev/null

repo="$(resolve_repo)"
ref="$(resolve_ref)"
if [[ -z "$ref" ]]; then
  echo "Could not resolve git branch. Pass --ref explicitly." >&2
  exit 2
fi

if ! gh workflow view push-test-notification.yml --repo "$repo" >/dev/null 2>&1; then
  cat >&2 <<EOF
GitHub workflow is not available on the repository default branch yet:
  repo: $repo
  workflow: .github/workflows/push-test-notification.yml

Commit and push the workflow file before dispatching.
EOF
  exit 1
fi

gh workflow run push-test-notification.yml \
  --repo "$repo" \
  --ref "$ref" \
  -f "base_url=$BASE_URL" \
  -f "topic=$TOPIC" \
  -f "token=$TOKEN" \
  -f "title=$TITLE" \
  -f "body=$BODY" \
  -f "allow_insecure=$ALLOW_INSECURE"

if [[ -n "$TOPIC" ]]; then
  echo "github_push_test_notification=status=dispatched repo=$repo ref=$ref target=topic:$TOPIC"
else
  echo "github_push_test_notification=status=dispatched repo=$repo ref=$ref target=token:<redacted>"
fi

if [[ "$WATCH" == "true" ]]; then
  sleep 3
  run_id="$(
    gh run list \
      --repo "$repo" \
      --workflow push-test-notification.yml \
      --branch "$ref" \
      --limit 1 \
      --json databaseId \
      --jq '.[0].databaseId'
  )"
  if [[ -z "$run_id" || "$run_id" == "null" ]]; then
    echo "Could not find the dispatched workflow run." >&2
    exit 1
  fi
  gh run watch "$run_id" --repo "$repo" --exit-status
fi
