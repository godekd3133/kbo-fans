#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${AWS_PUSH_OUTPUT_DIR:-$ROOT_DIR/outputs/aws/cloudformation}"
STACK_NAME="${KBO_PUSH_STACK_NAME:-kbo-fans-push-demo}"
INPUT_JSON=""
WRITE_ENV_FILE=true

usage() {
  cat <<'EOF'
Usage:
  AWS_REGION=<region> ./scripts/aws-push-stack-outputs.sh

Options:
  --stack-name <name>   Override CloudFormation stack name.
  --input-json <file>   Parse a saved describe-stacks JSON file without AWS calls.
  --no-env-file         Do not write outputs/aws/cloudformation/stack.env.

Outputs:
  export RELEASE_API_BASE_URL=...
  export API_BASE_URL=...
  export KBO_PUSH_STACK_API_BASE_URL=...
  outputs/aws/cloudformation/stack.env
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack-name)
      if [[ -z "${2:-}" ]]; then
        echo "--stack-name requires a value." >&2
        exit 2
      fi
      STACK_NAME="$2"
      shift 2
      ;;
    --input-json)
      if [[ -z "${2:-}" ]]; then
        echo "--input-json requires a value." >&2
        exit 2
      fi
      INPUT_JSON="$2"
      shift 2
      ;;
    --no-env-file)
      WRITE_ENV_FILE=false
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

require_cmd python3

if [[ -n "$INPUT_JSON" ]]; then
  describe_json="$INPUT_JSON"
else
  if [[ -z "${AWS_REGION:-}" ]]; then
    echo "AWS_REGION is required." >&2
    exit 2
  fi
  require_cmd aws
  mkdir -p "$OUTPUT_DIR"
  describe_json="$OUTPUT_DIR/describe-stacks.json"
  aws cloudformation describe-stacks \
    --region "$AWS_REGION" \
    --stack-name "$STACK_NAME" \
    --output json > "$describe_json"
fi

env_content="$(python3 - "$describe_json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
stacks = payload.get("Stacks") or []
if not stacks:
    print(f"No CloudFormation stacks found in {path}", file=sys.stderr)
    raise SystemExit(2)

outputs = {
    item.get("OutputKey"): item.get("OutputValue", "")
    for item in stacks[0].get("Outputs", [])
}
api_base_url = outputs.get("ApiBaseUrl")
if not api_base_url:
    print("CloudFormation output ApiBaseUrl is missing.", file=sys.stderr)
    raise SystemExit(2)

mapping = {
    "RELEASE_API_BASE_URL": api_base_url,
    "API_BASE_URL": api_base_url,
    "KBO_PUSH_STACK_API_BASE_URL": api_base_url,
    "KBO_PUSH_STACK_LOAD_BALANCER_DNS_NAME": outputs.get("LoadBalancerDnsName", ""),
    "KBO_PUSH_STACK_CLUSTER_NAME": outputs.get("ClusterName", ""),
    "KBO_PUSH_STACK_API_SERVICE_NAME": outputs.get("ApiServiceName", ""),
    "KBO_PUSH_STACK_SYNC_WORKER_SERVICE_NAME": outputs.get("SyncWorkerServiceName", ""),
    "KBO_PUSH_STACK_EFS_FILE_SYSTEM_ID": outputs.get("PushRegistryFileSystemId", ""),
    "KBO_PUSH_STACK_LOG_GROUP_NAME": outputs.get("LogGroupName", ""),
}

for key, value in mapping.items():
    if value:
        print(f"export {key}={value}")
PY
)"

mkdir -p "$OUTPUT_DIR"
env_file="$OUTPUT_DIR/stack.env"
if [[ "$WRITE_ENV_FILE" == "true" ]]; then
  printf '%s\n' "$env_content" > "$env_file"
fi

echo "aws_push_stack_outputs=status=ok stack=$STACK_NAME"
printf '%s\n' "$env_content"
if [[ "$WRITE_ENV_FILE" == "true" ]]; then
  echo "$env_file"
fi
