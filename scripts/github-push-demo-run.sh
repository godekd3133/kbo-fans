#!/usr/bin/env bash

set -euo pipefail

REPO=""
REF=""
DRY_RUN=true
IMAGE_TAG="${KBO_BACKEND_IMAGE_TAG:-latest}"
SKIP_READINESS=false
WATCH=false

usage() {
  cat <<'EOF'
Usage:
  ./scripts/github-push-demo-run.sh [--dry-run true|false] [--tag latest] [--watch]

Options:
  --repo <owner/repo>       Override GitHub repository. Default: gh repo view.
  --ref <branch-or-sha>     Workflow ref. Default: current git branch.
  --dry-run <true|false>    Run workflow in dry-run mode. Default: true.
  --tag <tag>               Backend image tag. Default: KBO_BACKEND_IMAGE_TAG or latest.
  --skip-readiness          Skip deployed API readiness after stack deploy.
  --watch                   Wait for the triggered workflow run.

Purpose:
  Dispatch the GitHub Actions Push Demo Deploy workflow after secrets/variables
  are configured. If the workflow is not visible on GitHub yet, push the
  workflow file to the default branch first.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      if [[ -z "${2:-}" ]]; then
        echo "--repo requires owner/repo." >&2
        exit 2
      fi
      REPO="$2"
      shift 2
      ;;
    --ref)
      if [[ -z "${2:-}" ]]; then
        echo "--ref requires a branch or sha." >&2
        exit 2
      fi
      REF="$2"
      shift 2
      ;;
    --dry-run)
      if [[ "${2:-}" != "true" && "${2:-}" != "false" ]]; then
        echo "--dry-run requires true or false." >&2
        exit 2
      fi
      DRY_RUN="$2"
      shift 2
      ;;
    --tag)
      if [[ -z "${2:-}" ]]; then
        echo "--tag requires a value." >&2
        exit 2
      fi
      IMAGE_TAG="$2"
      shift 2
      ;;
    --skip-readiness)
      SKIP_READINESS=true
      shift
      ;;
    --watch)
      WATCH=true
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

require_cmd gh
require_cmd git
gh auth status >/dev/null

repo="$(resolve_repo)"
ref="$(resolve_ref)"

if [[ -z "$ref" ]]; then
  echo "Could not resolve git branch. Pass --ref explicitly." >&2
  exit 2
fi

if ! gh workflow view push-demo-deploy.yml --repo "$repo" >/dev/null 2>&1; then
  cat >&2 <<EOF
GitHub workflow is not available on the repository default branch yet:
  repo: $repo
  workflow: .github/workflows/push-demo-deploy.yml

Commit and push the workflow file before dispatching:
  git add .github/workflows/push-demo-deploy.yml scripts/*.sh README.md docs/PUSH_LIVE_ACTIVITY_BACKEND_SETUP.md CHANGELOG.md AGENTS.md CLAUDE.md docs/WORKLOG.md
  git commit -m "푸시 데모 배포 자동화 추가"
  git push
EOF
  exit 1
fi

gh workflow run push-demo-deploy.yml \
  --repo "$repo" \
  --ref "$ref" \
  -f "dry_run=$DRY_RUN" \
  -f "image_tag=$IMAGE_TAG" \
  -f "skip_readiness=$SKIP_READINESS"

echo "github_push_demo_run=status=dispatched repo=$repo ref=$ref dry_run=$DRY_RUN tag=$IMAGE_TAG skip_readiness=$SKIP_READINESS"

if [[ "$WATCH" == "true" ]]; then
  sleep 3
  run_id="$(
    gh run list \
      --repo "$repo" \
      --workflow push-demo-deploy.yml \
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
