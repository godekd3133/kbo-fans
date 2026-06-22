#!/usr/bin/env bash

set -euo pipefail

REPO=""
REF=""
BASE_URL=""
EXPECT_RECEIPT=false
GAME_ID="${PUSH_RECEIPT_GAME_ID:-}"
TYPE="${PUSH_RECEIPT_TYPE:-}"
SOURCE="${PUSH_RECEIPT_SOURCE:-}"
SINCE="${PUSH_RECEIPT_SINCE:-}"
ALLOW_INSECURE="${ALLOW_INSECURE_PUSH_RECEIPT_STATUS:-true}"
WATCH=false

usage() {
  cat <<'EOF'
Usage:
  ./scripts/github-push-receipt-status-run.sh --watch
  ./scripts/github-push-receipt-status-run.sh --expect-receipt --game-id GAME_20260620HTKT0 --type hit --watch

Options:
  --repo <owner/repo>       Override GitHub repository. Default: gh repo view.
  --ref <branch-or-sha>     Workflow ref. Default: current git branch.
  --base-url <url>          API base URL. Empty uses RELEASE_API_BASE_URL variable in GitHub Actions.
  --expect-receipt          Fail workflow when no recent receipt matches filters.
  --game-id <gameId>        Match a specific receipt gameId.
  --type <type>             Match a specific receipt type, such as hit or scoring.
  --source <source>         Match a receipt source, such as foreground or opened.
  --since <iso-time>        Match receipts received/recorded at or after this time.
  --allow-insecure <bool>   Allow temporary HTTP smoke backend. Default: true.
  --watch                   Wait for the triggered workflow run.

This helper never prints PUSH_SYNC_SECRET or raw device tokens. The workflow uses
GitHub Actions secrets to call scripts/push-receipt-status.sh.
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
    --expect-receipt)
      EXPECT_RECEIPT=true
      shift
      ;;
    --game-id)
      GAME_ID="${2:-}"
      shift 2
      ;;
    --type)
      TYPE="${2:-}"
      shift 2
      ;;
    --source)
      SOURCE="${2:-}"
      shift 2
      ;;
    --since)
      SINCE="${2:-}"
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

require_cmd gh
require_cmd git
gh auth status >/dev/null

repo="$(resolve_repo)"
ref="$(resolve_ref)"
if [[ -z "$ref" ]]; then
  echo "Could not resolve git branch. Pass --ref explicitly." >&2
  exit 2
fi

if ! gh workflow view push-receipt-status.yml --repo "$repo" >/dev/null 2>&1; then
  cat >&2 <<EOF
GitHub workflow is not available on the repository default branch yet:
  repo: $repo
  workflow: .github/workflows/push-receipt-status.yml

Commit and push the workflow file before dispatching.
EOF
  exit 1
fi

gh workflow run push-receipt-status.yml \
  --repo "$repo" \
  --ref "$ref" \
  -f "base_url=$BASE_URL" \
  -f "expect_receipt=$EXPECT_RECEIPT" \
  -f "game_id=$GAME_ID" \
  -f "type=$TYPE" \
  -f "source=$SOURCE" \
  -f "since=$SINCE" \
  -f "allow_insecure=$ALLOW_INSECURE"

echo "github_push_receipt_status=status=dispatched repo=$repo ref=$ref expectReceipt=$EXPECT_RECEIPT"

if [[ "$WATCH" == "true" ]]; then
  sleep 3
  run_id="$(
    gh run list \
      --repo "$repo" \
      --workflow push-receipt-status.yml \
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
